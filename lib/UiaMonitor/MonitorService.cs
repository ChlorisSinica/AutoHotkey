using System;
using Debug = System.Diagnostics.Debug;
using System.Threading;
using System.Threading.Tasks;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.EventHandlers;
using FlaUI.UIA3;

namespace UiaMonitor
{
    internal sealed class MonitorService : IDisposable
    {
        // ── 定数 ──
        private const int FastPollMs = 60;
        private const int SlowPollMs = 200;
        private const int SlowdownThresholdMs = 3000;
        private const int SelectionCheckTimeoutMs = 200;
        private const int WatchdogIntervalMs = 3000;

        private readonly SharedState _state;
        private readonly UIA3Automation _automation;

        private FocusChangedEventHandlerBase? _focusHandler;
        private Timer? _selectionTimer;
        private Timer? _watchdogTimer;

        // 現在フォーカス中の要素（ポーリング用に保持）
        private AutomationElement? _currentElement;
        private readonly object _elementLock = new();

        // ポーリング間隔の動的調整
        private bool _lastHasSelection;
        private long _lastChangeTickMs;
        private int _currentIntervalMs = FastPollMs;

        // ウォッチドッグ: FocusChanged 最終発火時刻
        private long _lastFocusEventTick;

        private bool _disposed;

        public MonitorService(string mmfName)
        {
            _state = new SharedState(mmfName);
            _automation = new UIA3Automation();
            _lastChangeTickMs = Environment.TickCount64;
        }

        public bool IsShutdownRequested => _state.IsShutdownRequested;

        public void Start()
        {
            // フォーカス変更イベントを登録
            _focusHandler = _automation.RegisterFocusChangedEvent(OnFocusChanged);
            _lastFocusEventTick = Environment.TickCount64;

            // ウォッチドッグタイマー開始
            _watchdogTimer = new Timer(OnWatchdog, null, WatchdogIntervalMs, WatchdogIntervalMs);

            // 初回：現在のフォーカス要素を取得
            try
            {
                var focused = _automation.FocusedElement();
                if (focused != null)
                    OnFocusChanged(focused);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[UiaMonitor] 初期フォーカス取得失敗: {ex.Message}");
            }
        }

        public void Stop()
        {
            var watchdog = Interlocked.Exchange(ref _watchdogTimer, null);
            watchdog?.Dispose();

            StopSelectionPolling();

            if (_focusHandler != null)
            {
                try { _automation.UnregisterFocusChangedEvent(_focusHandler); }
                catch { /* 終了時は無視 */ }
                _focusHandler = null;
            }

            _state.Reset();
        }

        private void OnFocusChanged(AutomationElement element)
        {
            _lastFocusEventTick = Environment.TickCount64;
            try
            {
                ProcessFocusChange(element);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[UiaMonitor] フォーカス処理エラー: {ex.Message}");
                _state.Reset();
                StopSelectionPolling();
            }
        }

        private void ProcessFocusChange(AutomationElement element)
        {
            var controlType = GetControlType(element);
            bool isEditable = IsEditableElement(element, controlType);

            // プロセスID取得
            int pid = 0;
            try { pid = element.Properties.ProcessId.ValueOrDefault; }
            catch { /* 取得失敗は無視 */ }

            // 共有メモリ書込み
            _state.WriteIsEditable(isEditable);
            _state.WriteControlType(ClassifyControl(element, controlType));
            _state.WriteProcessId(pid);

            if (isEditable)
            {
                // テキスト欄にフォーカス → 選択状態ポーリング開始
                lock (_elementLock)
                {
                    _currentElement = element;
                }
                _lastHasSelection = false;
                _lastChangeTickMs = Environment.TickCount64;
                _currentIntervalMs = FastPollMs;
                StartSelectionPolling(FastPollMs);

                // 初回即時チェック
                PollSelection(null);
            }
            else
            {
                // テキスト欄でない → ポーリング停止、選択なし
                _state.WriteHasSelection(false);
                StopSelectionPolling();
                lock (_elementLock)
                {
                    _currentElement = null;
                }
            }
        }

        // ── ウォッチドッグ: FocusChanged 未発火時の回復 ──

        private void OnWatchdog(object? _)
        {
            long elapsed = Environment.TickCount64 - _lastFocusEventTick;
            if (elapsed < WatchdogIntervalMs)
                return;

            Debug.WriteLine($"[UiaMonitor] ウォッチドッグ: {elapsed}ms FocusChanged 未発火。回復試行。");
            try
            {
                var focused = _automation.FocusedElement();
                if (focused != null)
                {
                    _lastFocusEventTick = Environment.TickCount64;
                    ProcessFocusChange(focused);
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[UiaMonitor] ウォッチドッグ回復失敗: {ex.Message}");
            }
        }

        // ── テキスト編集可能判定 ──

        private bool IsEditableElement(AutomationElement element, ControlType ct)
        {
            // 1) ControlType による判定
            if (ct == ControlType.Edit || ct == ControlType.Document)
            {
                // ReadOnly チェック
                if (!IsReadOnly(element))
                    return true;
            }

            // 2) パターンによる判定（ComboBox 内の Edit 等）
            if (ct == ControlType.ComboBox)
            {
                try
                {
                    if (element.Patterns.Value.IsSupported && !IsReadOnly(element))
                        return true;
                }
                catch { }
            }

            // 3) SpreadsheetItem（Excel セル等）
            if (ct == ControlType.DataItem || ct == ControlType.Custom)
            {
                try
                {
                    if (element.Patterns.Value.IsSupported && !IsReadOnly(element))
                        return true;
                }
                catch { }
            }

            // Layer 2: パターンベースフォールバック
            // TextPattern をサポートし、キーボードフォーカス可能で、ReadOnly でない要素は
            // 編集可能と判定 (PPT テキストボックス等の非標準 ControlType に対応)
            try
            {
                if (element.Patterns.Text.IsSupported)
                {
                    bool focusable = false;
                    try { focusable = element.Properties.IsKeyboardFocusable.ValueOrDefault; }
                    catch { focusable = true; }

                    if (focusable && !IsReadOnly(element))
                        return true;
                }
            }
            catch { }

            return false;
        }

        private static bool IsReadOnly(AutomationElement element)
        {
            try
            {
                if (element.Patterns.Value.IsSupported)
                {
                    return element.Patterns.Value.Pattern.IsReadOnly.ValueOrDefault;
                }
            }
            catch { }
            return false; // 判定不能な場合は編集可能と仮定
        }

        private static ControlType GetControlType(AutomationElement element)
        {
            try
            {
                return element.Properties.ControlType.ValueOrDefault;
            }
            catch
            {
                return ControlType.Custom;
            }
        }

        private static ControlKind ClassifyControl(AutomationElement element, ControlType ct)
        {
            if (ct == ControlType.Edit)
            {
                try
                {
                    var className = element.Properties.ClassName.ValueOrDefault ?? "";
                    if (className.Contains("RichEdit", StringComparison.OrdinalIgnoreCase))
                        return ControlKind.RichEdit;
                }
                catch { }
                return ControlKind.Edit;
            }

            if (ct == ControlType.Document)
            {
                try
                {
                    var frameworkId = element.Properties.FrameworkId.ValueOrDefault ?? "";
                    if (frameworkId.Equals("Chrome", StringComparison.OrdinalIgnoreCase) ||
                        frameworkId.Equals("InternetExplorer", StringComparison.OrdinalIgnoreCase))
                        return ControlKind.Browser;
                }
                catch { }
                return ControlKind.Document;
            }

            return ControlKind.Unknown;
        }

        // ── 選択状態ポーリング ──

        private void StartSelectionPolling(int intervalMs)
        {
            StopSelectionPolling();
            _selectionTimer = new Timer(
                PollSelection,
                null,
                intervalMs,
                intervalMs
            );
        }

        private void StopSelectionPolling()
        {
            var timer = Interlocked.Exchange(ref _selectionTimer, null);
            timer?.Dispose();
        }

        private void PollSelection(object? _)
        {
            // RefreshRequest チェック: AHK から再チェック要求があれば即時回復
            if (_state.ReadRefreshRequest())
            {
                _state.ClearRefreshRequest();
                Debug.WriteLine("[UiaMonitor] RefreshRequest 受信。フォーカス再取得。");
                try
                {
                    var focused = _automation.FocusedElement();
                    if (focused != null)
                    {
                        _lastFocusEventTick = Environment.TickCount64;
                        ProcessFocusChange(focused);
                    }
                }
                catch (Exception ex)
                {
                    Debug.WriteLine($"[UiaMonitor] RefreshRequest 再取得失敗: {ex.Message}");
                }
                return;
            }

            AutomationElement? el;
            lock (_elementLock)
            {
                el = _currentElement;
            }

            if (el == null)
            {
                _state.WriteHasSelection(false);
                return;
            }

            // 要素の生存チェック（軽量）
            if (!IsElementAlive(el))
            {
                Debug.WriteLine("[UiaMonitor] 要素が無効になりました。リセットします。");
                ResetCurrentElement();
                return;
            }

            // タイムアウト付き選択チェック
            bool hasSelection;
            try
            {
                hasSelection = CheckSelectionWithTimeout(el);
            }
            catch (System.Runtime.InteropServices.COMException)
            {
                ResetCurrentElement();
                return;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[UiaMonitor] 選択ポーリングエラー: {ex.Message}");
                _state.WriteHasSelection(false);
                return;
            }

            _state.WriteHasSelection(hasSelection);

            // 動的ポーリング間隔調整
            AdjustPollingInterval(hasSelection);
        }

        private bool CheckSelectionWithTimeout(AutomationElement element)
        {
            using var cts = new CancellationTokenSource(SelectionCheckTimeoutMs);
            try
            {
                var task = Task.Run(() => CheckSelection(element), cts.Token);
                return task.Wait(SelectionCheckTimeoutMs) ? task.Result : false;
            }
            catch (OperationCanceledException)
            {
                return false;
            }
            catch (AggregateException ae) when (ae.InnerException is System.Runtime.InteropServices.COMException)
            {
                throw ae.InnerException;
            }
            catch (AggregateException ae)
            {
                Debug.WriteLine($"[UiaMonitor] タイムアウト/エラー: {ae.InnerException?.Message}");
                return false;
            }
        }

        private static bool IsElementAlive(AutomationElement element)
        {
            try
            {
                _ = element.Properties.ProcessId.ValueOrDefault;
                return true;
            }
            catch
            {
                return false;
            }
        }

        private void ResetCurrentElement()
        {
            _state.Reset();
            StopSelectionPolling();
            lock (_elementLock)
            {
                _currentElement = null;
            }
        }

        private void AdjustPollingInterval(bool hasSelection)
        {
            if (hasSelection != _lastHasSelection)
            {
                _lastHasSelection = hasSelection;
                _lastChangeTickMs = Environment.TickCount64;

                // 状態変化 → 高速ポーリングに戻す
                if (_currentIntervalMs != FastPollMs)
                {
                    _currentIntervalMs = FastPollMs;
                    StartSelectionPolling(FastPollMs);
                }
            }
            else if (_currentIntervalMs == FastPollMs)
            {
                // 一定時間変化なし → 低速ポーリングへ
                long elapsed = Environment.TickCount64 - _lastChangeTickMs;
                if (elapsed > SlowdownThresholdMs)
                {
                    _currentIntervalMs = SlowPollMs;
                    StartSelectionPolling(SlowPollMs);
                }
            }
        }

        private static bool CheckSelection(AutomationElement element)
        {
            // 1) TextPattern による選択範囲取得（最も正確）
            if (TryCheckSelectionByTextPattern(element, out bool result))
                return result;

            // 2) TextPattern2 による選択確認
            if (TryCheckSelectionByTextPattern2(element, out result))
                return result;

            // 3) ValuePattern フォールバック（Electron 等の TextPattern 非対応アプリ向け）
            if (TryCheckSelectionByValuePattern(element, out result))
                return result;

            return false;
        }

        private static bool TryCheckSelectionByTextPattern(AutomationElement element, out bool hasSelection)
        {
            hasSelection = false;
            try
            {
                if (!element.Patterns.Text.IsSupported)
                    return false;

                var textPattern = element.Patterns.Text.Pattern;
                var selections = textPattern.GetSelection();

                if (selections != null && selections.Length > 0)
                {
                    var text = selections[0].GetText(1);
                    hasSelection = !string.IsNullOrEmpty(text);
                }
                return true; // パターンはサポートされている（結果が空でも）
            }
            catch
            {
                return false; // パターン非サポートまたは取得失敗 → 次へ
            }
        }

        private static bool TryCheckSelectionByTextPattern2(AutomationElement element, out bool hasSelection)
        {
            hasSelection = false;
            try
            {
                if (!element.Patterns.Text2.IsSupported)
                    return false;

                var textPattern2 = element.Patterns.Text2.Pattern;
                var selections = textPattern2.GetSelection();
                if (selections != null && selections.Length > 0)
                {
                    var text = selections[0].GetText(1);
                    hasSelection = !string.IsNullOrEmpty(text);
                }
                return true;
            }
            catch
            {
                return false;
            }
        }

        private static bool TryCheckSelectionByValuePattern(AutomationElement element, out bool hasSelection)
        {
            hasSelection = false;
            try
            {
                if (!element.Patterns.Value.IsSupported)
                    return false;

                // ValuePattern では選択状態を直接判定できないが、
                // 値が存在する = テキスト入力欄として機能している、という補助情報を返す。
                // 選択状態は判定不能なので false を返す。
                return false;
            }
            catch
            {
                return false;
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            Stop();
            _automation?.Dispose();
            _state?.Dispose();
        }
    }
}
