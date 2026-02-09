; ==============================================================================
; インジケーター＆設定初期化関数
; ==============================================================================
Indicator_Init() {
    SettingsUI.Init()
}

Settings_Open() {
    SettingsUI.Show()
}

Settings_Close() {
    Gui, Settings:Destroy
    Gui, SubSettings:Destroy ; サブウィンドウも閉じる
}

; ==============================================================================
; 設定管理クラス
; ==============================================================================
class SettingsUI {
    static EditorType := 1  ; 1: Notepads, 2: Notepad

    ; 設定項目リスト
    static CheckBoxes := {"EnableNavLayer": "変換キー拡張 (カーソル移動など)"
        , "EnableWinMgr":   "Window操作 (Win+矢印など)"
        , "EnableMouseExt": "マウスボタン拡張 (F13-F24)"
        , "EnableAppSpec":  "アプリ固有設定 (Excel/PPT/Browser)"
        , "EnableMouseEmu": "キーボードマウス (vk1C+WASD)"
        , "EnableGestures": "マウスジェスチャー"}

    ; --- 初期化 ---
    Init() {
        Global StartupShortcutPath, TargetScriptPath
        TargetScriptPath := A_ScriptDir . "\main.ahk"
        StartupShortcutPath := A_Startup . "\ahk_main_shorcut.lnk"

        Menu, Tray, Add
        Menu, Tray, Add
        Menu, Tray, Add, スタートアップで実行する, Startup_Toggle
        Menu, Tray, Add, 機能設定 (Settings), Settings_Open

        IfExist, %StartupShortcutPath%
            Menu, Tray, Check, スタートアップで実行する
    }

    ; --- メイン設定画面の表示 ---
    Show() {
        Global
        Gui, Settings:Destroy
        Gui, Settings:New, +AlwaysOnTop +HwndhGui, 機能のON/OFF設定
        Gui, Settings:Font, s10, Meiryo UI
        Gui, Settings:Color, White

        fnSave   := ObjBindMethod(this, "OnCheckSave")
        fnDetail := ObjBindMethod(this, "ShowDetailWindow") ; 詳細ボタン用

        Gui, Settings:Add, Text, xm ym, ■ 機能の有効化
        Gui, Settings:Add, Text, h5

        ; チェックボックス生成
        For param, labelText in this.CheckBoxes {
            CurrentVal := %param%
            Gui, Settings:Add, CheckBox, xs+10 y+5 v%param% g%fnSave% Checked%CurrentVal%, %labelText%
        }

        Gui, Settings:Add, Text, h10

        ; ★ここを変更：開閉ではなく「ボタン」にする
        Gui, Settings:Add, Button, xs+10 w200 g%fnDetail%, エディタ設定を開く...

        Gui, Settings:Show, AutoSize xCenter yCenter
    }

    ; --- 詳細設定（サブウィンドウ）の表示 ---
    ShowDetailWindow() {
        Global
        Gui, SubSettings:Destroy
        ; メイン画面(Settings)を親に指定してモーダルっぽくする
        Gui, SubSettings:New, +OwnerSettings +AlwaysOnTop +ToolWindow, エディタ選択
        Gui, SubSettings:Font, s10, Meiryo UI
        Gui, SubSettings:Color, White

        fnEditor := ObjBindMethod(this, "OnEditorChange")

        Gui, SubSettings:Add, GroupBox, xm ym w250 h80, デフォルトエディタ

        Check1 := (this.EditorType = 1) ? "Checked" : ""
        Check2 := (this.EditorType = 2) ? "Checked" : ""

        Gui, SubSettings:Add, Radio, xs+10 ys+25 vRadioNotepads g%fnEditor% %Check1%, Notepads (UWP)
        Gui, SubSettings:Add, Radio, x+10 vRadioStandard g%fnEditor% %Check2%, notepad.exe (標準)

        Gui, SubSettings:Show, AutoSize Center
    }

    ; --- 保存イベント ---
    OnCheckSave() {
        Global
        Gui, Settings:Submit, NoHide
    }

    OnEditorChange() {
        Global
        Gui, SubSettings:Submit, NoHide
        if (RadioNotepads == 1)
            this.EditorType := 1
        else
            this.EditorType := 2
    }
}

; ==============================================================================
; スタートアップ切替関数
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