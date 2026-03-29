# Tasks: チャタリング防止プラグイン + CSharpUIA 導入

## Phase 1: ChatterGuard プラグイン作成

- [ ] **Task 1.1**: `Plugins/ChatterGuard.ahk` を新規作成
  - .logs/MouseChatterGuard.ahk をベースに、グローバル直書きの `CG_Thresholds` / `CG_ComboThresholds` を削除
  - `CG_Init(thresholds)` で外部から閾値を受け取る設計を維持
  - `CG_RawDown`, `CG_RawUp`, `CG_Stamp`, `CG_IsHeld` の4関数 + コールバック変数
  - トップレベルホットキー/ラベル禁止（ahk-style.md 準拠）
  - **DoD**: ファイルが存在し、AHK 構文エラーなし。`CG_Init({})` 呼び出し後に `CG_State` が空 Object

- [ ] **Task 1.2**: `Plugins/KeyRouter.ahk` を新規作成
  - .logs/MouseKeyRouter.ahk をベースに、グローバル直書きの自動初期化コード（L21-23）を削除
  - `MK_Init()` 関数を新設: `CG_Init` 呼び出し + コールバック接続を内部で行う
  - `MK_ActionMap`, `MK_ComboMap`, `MK_WheelMap` は空 Object のまま外部設定を待つ
  - 全公開関数を維持: `MK_OnDown`, `MK_OnUp`, `MK_OnWheel`, `MK_Exec`, `MK_ResolveAction`, `MK_HasWheelModifier`, `MK_RegisterRelease`
  - **DoD**: ファイルが存在し、AHK 構文エラーなし。`MK_Init(thresholds)` で CG 層が初期化される

- [ ] **Task 1.3**: main.ahk にキー設定テーブルとホットキーを定義
  - `#Include ChatterGuard.ahk` + `#Include KeyRouter.ahk` を追加
  - 初期化セクションで `MK_Init(thresholds)` + `MK_ActionMap`/`MK_ComboMap`/`MK_WheelMap` 設定
  - `#If (EnableMouseBtn)` セクションのホットキーを `CG_RawDown`/`CG_RawUp` 経由に書き換え
  - ホイールホットキーは `MK_OnWheel` 経由に書き換え
  - **DoD**: plan.md §3.1-§3.3 の状態遷移・コールバック契約と一致。既存6キーの動作が同等

- [ ] **Task 1.4**: 動作検証
  - `"C:\Program Files\AutoHotkey\AutoHotkey.exe" /ErrorStdOut main.ahk` でエラーなし
  - F15(ペースト), F16(コピー), F17(タブ閉じ), XButton1(戻る), XButton2(進む), MButton のマッピング確認
  - F15+MButton(再生), XButton1+Wheel(横スクロール), XButton2+Wheel(ズーム), F15+Wheel(音量), F16+Wheel(AltTab) のコンボ確認
  - **DoD**: 全ホットキーが変更前と同等に動作

## Phase 2: CSharpUIA 導入

- [ ] **Task 2.1**: C# プロジェクトのビルド確認
  - `dotnet --version` で .NET SDK の存在確認
  - `lib/CSharpUIA/` で `dotnet restore` + `dotnet publish -c Release -r win-x64 --self-contained false -o ./UiaMonitor`
  - publish 先を `lib/CSharpUIA/UiaMonitor/` に合わせる（`UIA_MONITOR_EXE` のパスと一致）
  - **DoD**: `lib/CSharpUIA/UiaMonitor/UiaMonitor.exe` が生成される

- [ ] **Task 2.2**: main.ahk に UIA 接続コードを追加
  - `#Include %A_ScriptDir%\lib\CSharpUIA\UiaIntegration.ahk` を追加（WindowGrid の後）
  - 初期化セクションに `UiaInit()` を追加
  - `OnExit("UiaCleanup")` を追加
  - **DoD**: AHK 構文エラーなし。起動時に UiaMonitor.exe プロセスが起動する

- [ ] **Task 2.3**: 動作確認
  - AHK 起動後、`UiaIsEditable()` がテキスト欄フォーカス時に 1 を返すことを確認
  - AHK 終了時に UiaMonitor.exe も終了することを確認
  - **DoD**: 共有メモリ経由で状態取得が機能している
