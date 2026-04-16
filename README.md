# AutoHotkey Tips

個人用の AutoHotkey v1.1 スクリプト集です．エントリポイントは `main.ahk` で，主要な処理は `Plugins` 配下にあります．

vk1c(変換キー) + F1の設定欄でON/OFFが可能です．

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

## PowerPoint Source Manager

- Plugins/PowerPoint.ahkでは.pptx内の画像のソース管理を行っています．エクスプローラーでコピーした画像をCtrl+Vでペーストするとメタデータを挿入するホットキーが発火します．
- source manager の正式入口は `Ctrl+Alt+E` です。scan / re-scan / export / manual pick は manager 内から行います。
- 現行の source manager 本体は PowerShell 版です。旧 `ppt_scan.py` / `ppt_scan_gui.py` は `_tmp/` に退避しています。
- `Plugins/ppt_extract_media.ps1` にも置き換えたため，PowerPoint source manager の Python 依存は外れました。[Everything](./docs/ppt_scan_setup.md) は引き続き有効です。

## UiaMonitor

BracketWrap 廃止に伴い、`lib/UiaMonitor/` は repo から削除しました。
現行構成で使っている UI Automation 依存は `lib/UIA_Interface.ahk` と `lib/UIA_Browser.ahk` のみです。

## Appendix

- `lib\UIA_Interface.ahk` and `lib\UIA_Browser.ahk` are UI Automation dependency libraries.
- In `#Include` files, avoid top-level labels followed by a bare `return`.
- Included files are effectively inlined into `main.ahk`, so auto-execute can fall into that label body and stop early at `return`.
- Also avoid top-level hotkeys, hotstrings, and `#If` hotkey blocks in `#Include` files when later startup lines in `main.ahk` still need to run.
- A top-level hotkey definition in an included file can end the auto-execute section before later lines such as `TrayTip`, config load, or other initialization.
- Keep context-sensitive hotkeys in `main.ahk` after startup initialization, or register them later from functions.
- This can silently break later initialization and make unrelated hotkeys appear dead.
- Prefer function timers such as `SetTimer, % Func("MyHandler"), -10` instead of label timers in plugin files.


## 初めての方へ

- 必要インストール:
  - `AHKv1.1`: https://www.autohotkey.com/
  - `VSCode`: https://code.visualstudio.com/download (拡張機能はAHK++を推奨)
  - `git`: https://gitforwindows.org/
- 実行方法
  - インストール後，任意のフォルダで `git clone https://github.com/ChlorisSinica/AutoHotkey`
  - main.ahkを実行後，タスクバー右下のインジケータに常駐します
  - shell:startupに追加 (再起動しても自動実行) する場合は，インジケータから「スタートアップで実行する」を有効化してください
- プロジェクトを最新版にアップデートする場合は `git pull` を実行し, 追加要望があればIssueを投げてください. 
- 下記文献を参考に，.ahkファイルを試作することを推奨します


## Reference

- https://ahkwiki.net/KeyList
- https://qiita.com/draganmaistir/items/0bf4a2ff484523a2dee9
- https://qiita.com/ryoheiszk/items/092cc5d76838cb5a13f1
- https://qiita.com/riekure/items/49b941fa5159f9948313
