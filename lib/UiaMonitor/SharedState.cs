using System;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;

namespace UiaMonitor
{
    /// <summary>
    /// 共有メモリのデータ構造（合計16バイト）
    ///
    /// Offset  Size  Field            Values
    /// ──────────────────────────────────────────
    ///  0      1     isTextEditable   0=No, 1=Yes
    ///  1      1     hasSelection     0=No, 1=Yes
    ///  2      1     controlType      0=Edit, 1=RichEdit, 2=Document, 3=Browser, 0xFF=Unknown
    ///  3      1     reserved         (アライメント用)
    ///  4      4     processId        フォーカス先プロセスID
    ///  8      1     shutdownSignal   0=通常, 1=シャットダウン要求
    ///  9-15         reserved
    /// </summary>
    internal sealed class SharedState : IDisposable
    {
        public const int Size = 16;

        // オフセット定数
        private const int OffsetIsEditable = 0;
        private const int OffsetHasSelection = 1;
        private const int OffsetControlType = 2;
        private const int OffsetProcessId = 4;
        private const int OffsetShutdown = 8;

        private readonly MemoryMappedFile _mmf;
        private readonly MemoryMappedViewAccessor _accessor;
        private bool _disposed;

        public SharedState(string name)
        {
            _mmf = MemoryMappedFile.CreateOrOpen(name, Size);
            _accessor = _mmf.CreateViewAccessor(0, Size);

            // 初期化：全てゼロクリア
            for (int i = 0; i < Size; i++)
                _accessor.Write(i, (byte)0);
        }

        // ── 書込み（C# 側が使用）──

        public void WriteIsEditable(bool value)
            => _accessor.Write(OffsetIsEditable, (byte)(value ? 1 : 0));

        public void WriteHasSelection(bool value)
            => _accessor.Write(OffsetHasSelection, (byte)(value ? 1 : 0));

        public void WriteControlType(ControlKind kind)
            => _accessor.Write(OffsetControlType, (byte)kind);

        public void WriteProcessId(int pid)
            => _accessor.Write(OffsetProcessId, pid);

        /// <summary>テキスト欄でない状態にリセット</summary>
        public void Reset()
        {
            WriteIsEditable(false);
            WriteHasSelection(false);
            WriteControlType(ControlKind.Unknown);
            WriteProcessId(0);
        }

        // ── シャットダウンシグナル ──

        public bool IsShutdownRequested
            => _accessor.ReadByte(OffsetShutdown) != 0;

        /// <summary>外部から既存プロセスにシャットダウンを要求する</summary>
        public static void SignalShutdown(string name)
        {
            try
            {
                using var mmf = MemoryMappedFile.OpenExisting(name);
                using var accessor = mmf.CreateViewAccessor(0, Size);
                accessor.Write(OffsetShutdown, (byte)1);
            }
            catch { /* 共有メモリが存在しない場合は無視 */ }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _accessor?.Dispose();
            _mmf?.Dispose();
        }
    }

    /// <summary>コントロール種別</summary>
    internal enum ControlKind : byte
    {
        Edit = 0,
        RichEdit = 1,
        Document = 2,
        Browser = 3,
        Unknown = 0xFF,
    }
}
