; ==============================================================================
; インジケーター＆設定初期化関数
; ==============================================================================
Indicator_Init() {
    Global StartupShortcutPath, TargetScriptPath

    ; --- 1. 変数・パスの初期化 ---
    TargetScriptPath := A_ScriptDir . "\main.ahk"
    StartupShortcutPath := A_Startup . "\ahk_main_shorcut.lnk"

    Menu, Tray, Add     ; メニュー区切り線
    Menu, Tray, Add, スタートアップで実行する, Startup_Toggle
    Menu, Tray, Add, 機能設定 (Settings), Settings_Open

    IfExist, %StartupShortcutPath%
    {
        Menu, Tray, Check, スタートアップで実行する
    }
}

; ==============================================================================
; 設定GUI 表示関数
; ==============================================================================
Settings_Open(ItemName="", ItemPos="", MenuName="") {
    Global EnableNavLayer, EnableWinMgr, EnableMouseExt, EnableAppSpec, EnableMouseEmu, EnableGestures

    ; 既存のGUIがあれば破棄して新規作成 (常に最新の状態にするため)
    Gui, Settings:Destroy
    Gui, Settings:New, +AlwaysOnTop, 機能のON/OFF設定
    Gui, Settings:Font, s10, Meiryo UI

    ; 各チェックボックス
    ; "gSettings_Save" で、変更時に Settings_Save 関数を呼び出す
    Gui, Settings:Add, CheckBox, vEnableNavLayer gSettings_Save Checked%EnableNavLayer%, 変換キー拡張 (カーソル移動など)
    Gui, Settings:Add, CheckBox, vEnableWinMgr     gSettings_Save Checked%EnableWinMgr%, Window操作 (Win+矢印など)
    Gui, Settings:Add, CheckBox, vEnableMouseExt   gSettings_Save Checked%EnableMouseExt%, マウスボタン拡張 (F13-F24)
    Gui, Settings:Add, CheckBox, vEnableAppSpec    gSettings_Save Checked%EnableAppSpec%, アプリ固有設定 (Excel/PPT/Browser)
    Gui, Settings:Add, CheckBox, vEnableMouseEmu   gSettings_Save Checked%EnableMouseEmu%, キーボードマウス (vk1C+WASD)
    Gui, Settings:Add, CheckBox, vEnableGestures   gSettings_Save Checked%EnableGestures%, マウスジェスチャー

    Gui, Settings:Show
}

Settings_Close() {
    Gui, Settings:Submit  ; 画面の値を保存して変数に反映
    Gui, Settings:Destroy ; 画面を破棄
}

; ==============================================================================
; 設定保存関数
; GUIのイベント(gラベル)として呼ばれる関数は、4つの引数を受け取る必要がある
; ==============================================================================
Settings_Save(CtrlHwnd="", GuiEvent="", EventInfo="", ErrLvl="") {
    ; GUIの値を読み取ってグローバル変数を更新
    Gui, Settings:Submit, NoHide
}

; ==============================================================================
; スタートアップ切替関数 (既存機能)
; ==============================================================================
Startup_Toggle(ItemName, ItemPos="", MenuName="") {
    Global StartupShortcutPath, TargetScriptPath

    if (ItemName = "")
        return

    IfNotExist, %TargetScriptPath%
    {
        MsgBox, 16, エラー, 同一フォルダに main.ahk が見つかりません。`n%TargetScriptPath%
        return
    }

    IfExist, %StartupShortcutPath%
    {
        FileDelete, %StartupShortcutPath%
        if (ErrorLevel = 0) {
            Menu, Tray, Uncheck, %ItemName%
            MsgBox, 64, 設定変更, スタートアップから削除しました。
        } else {
            MsgBox, 16, エラー, 削除に失敗しました。`n%StartupShortcutPath%
        }
    }
    Else
    {
        FileCreateShortcut, %TargetScriptPath%, %StartupShortcutPath%, %A_ScriptDir%
        if (ErrorLevel = 0) {
            Menu, Tray, Check, %ItemName%
            MsgBox, 64, 設定変更, スタートアップに登録しました。
        } else {
            MsgBox, 16, エラー, 作成に失敗しました。
        }
    }
}