# AutoHotkey

個人用の AutoHotkey v1.1 スクリプト集です．エントリポイントは `main.ahk` で，主要な処理は `Plugins` 配下にあります．

## 構成

- `main.ahk`
  - 初期化
  - 機能トグル
  - ホットキー定義
- `Plugins/Application.ahk`
  - アプリ起動補助
  - ウィンドウグループ定義
- `Plugins/WindowManager.ahk`
  - ウィンドウ移動補助
  - モニター作業領域取得
- `Plugins/WindowGrid.ahk`
  - グリッド単位の移動とリサイズ
- `Plugins/Browser.ahk`
  - ブラウザ操作
  - URL 取得
  - PDF / YouTube 補助
- `Plugins/PowerPoint.ahk`
  - PowerPoint 操作自動化
- `Plugins/MouseGesture.ahk`
  - 右クリックベースのマウスジェスチャ
  - 右クリック不具合のデバッグログ

## マウスジェスチャの補足

- ジェスチャが成立しなかった場合は，通常の右クリックを `Click, Right` で復帰します．
- `右クリック + スクロール` を行った場合，その押下中はジェスチャ認識を無効化します．
- ジェスチャ対象は Browser / Explorer / Editor / Office / PyCharm です．

## 右クリック不具合のデバッグ

右クリックしてもコンテキストメニューが開かなくなる不具合に備えて，軽量なデバッグログを実装しています．

ログ出力先:

- `.claude\mouse_gesture_debug.log`

手動記録方法:

- `vk1C + F2`
  - その時点の状態を `snapshot` として記録します．
- トレイメニューの右クリック状態記録項目
  - 同じく `snapshot` を記録します．
- トレイメニューのログ表示項目
  - ログファイルをメモ帳で開きます．

主な記録内容:

- `RButton` ホットキーが発火したか
- `MG_IsActive`, `MG_CancelMenu`, `MG_WheelUsed`
- 右ボタンの物理状態と論理状態
- マウス下ウィンドウとアクティブウィンドウの `hwnd / exe / class / title`
- 最終分岐
  - 通常右クリック復帰
  - ホイール介入によるキャンセル
  - ジェスチャ実行

主なイベント名:

- `startup`
- `snapshot`
- `RButton_hotkey_start`
- `recognize_start`
- `gesture_dir_append`
- `recognize_disabled_by_wheel`
- `recognize_finish`
- `execute_passthrough_right_click`
- `execute_empty_gesture_cancelled`
- `execute_gesture`
- `scroll_action`

## デバッグ手順

1. 不具合が再発したら，まず `vk1C + F2` を押します．
2. `.claude\mouse_gesture_debug.log` を開きます．
3. 発生直前のログで次を確認します．
   - `RButton_hotkey_start` があるか
   - `recognize_finish` がどう終了しているか
   - `execute_passthrough_right_click` まで到達しているか
4. `execute_empty_gesture_cancelled` が出ていれば，ジェスチャ状態により右クリックが抑止されています．

## UiaMonitor セットアップ

`lib/UiaMonitor/` はフォーカス状態を共有メモリ経由で取得する C# 監視プロセスです。
未ビルドの場合、BracketWrap 等の UIA 依存機能は自動的に無効化されます。

初回 / 別 PC への移行時:

```bash
# 1. AutoHotkey v1.1 のインストール
winget install AutoHotkey.AutoHotkey --version 1.1.37.02

# 2. .NET SDK のインストール（ビルド時のみ必要）
winget install Microsoft.DotNet.SDK.10

# 3. UiaMonitor のビルド
cd lib/UiaMonitor
dotnet publish -c Release -r win-x64 --self-contained true -o ./UiaMonitor
```

- 生成される `UiaMonitor/UiaMonitor.exe` は self-contained のため実行時に .NET 不要
- `main.ahk` 起動時に `UiaInit()` で自動起動され，終了時に `UiaCleanup()` で停止

## Appendix

- `Plugins\UIA_Interface.ahk` and `Plugins\UIA_Browser.ahk` are UI Automation dependency libraries.
- In `#Include` files, avoid top-level labels followed by a bare `return`.
- Included files are effectively inlined into `main.ahk`, so auto-execute can fall into that label body and stop early at `return`.
- Also avoid top-level hotkeys, hotstrings, and `#If` hotkey blocks in `#Include` files when later startup lines in `main.ahk` still need to run.
- A top-level hotkey definition in an included file can end the auto-execute section before later lines such as `TrayTip`, config load, or other initialization.
- Keep context-sensitive hotkeys in `main.ahk` after startup initialization, or register them later from functions.
- This can silently break later initialization and make unrelated hotkeys appear dead.
- Prefer function timers such as `SetTimer, % Func("MyHandler"), -10` instead of label timers in plugin files.

## Reference

- https://ahkwiki.net/KeyList
- https://qiita.com/draganmaistir/items/0bf4a2ff484523a2dee9
- https://qiita.com/ryoheiszk/items/092cc5d76838cb5a13f1
- https://qiita.com/riekure/items/49b941fa5159f9948313

