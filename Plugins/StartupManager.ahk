; ==============================================================================
; 初期化関数
; ==============================================================================
Startup_Init() {
    Global StartupShortcutPath, TargetScriptPath

    TargetScriptPath := A_ScriptDir . "\main.ahk"
    StartupShortcutPath := A_Startup . "\ahk_main_shorcut.lnk"

    ; 【修正】ラベルではなく、関数名 "Startup_Toggle" を直接指定します。
    ; これにより、スクリプト起動時に勝手に実行される事故（フォールスルー）を防げます。
    Menu, Tray, Add, スタートアップで実行する, Startup_Toggle

    ; 既に存在すればチェックを入れる
    IfExist, %StartupShortcutPath%
    {
        Menu, Tray, Check, スタートアップで実行する
    }
}

; ==============================================================================
; 実処理関数
; ==============================================================================
Startup_Toggle(ItemName, ItemPos="", MenuName="") {
    Global StartupShortcutPath, TargetScriptPath

    ; 【安全策】もし空の引数で呼ばれてしまった場合は何もせず終了（エラー回避）
    if (ItemName = "")
        return

    ; main.ahk が存在するか念の為チェック
    IfNotExist, %TargetScriptPath%
    {
        MsgBox, 16, エラー, 同一フォルダに main.ahk が見つかりません。`n%TargetScriptPath%
        return
    }

    IfExist, %StartupShortcutPath%
    {
        ; --- 削除（解除） ---
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
        ; --- 作成（登録） ---
        FileCreateShortcut, %TargetScriptPath%, %StartupShortcutPath%, %A_ScriptDir%

        if (ErrorLevel = 0) {
            Menu, Tray, Check, %ItemName%
            MsgBox, 64, 設定変更, スタートアップに登録しました。
        } else {
            MsgBox, 16, エラー, 作成に失敗しました。
        }
    }
}