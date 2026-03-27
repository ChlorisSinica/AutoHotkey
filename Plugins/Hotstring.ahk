global g_HoldN_Active := 0

IME_SetOpenStatus(isOpen, showTip := true) {
    WinGet, activeHwnd, ID, A
    if !activeHwnd
        return false

    imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", activeHwnd, "Ptr")
    if !imeHwnd
        return false

    prevDetectHiddenWindows := A_DetectHiddenWindows
    DetectHiddenWindows, On
    SendMessage, 0x0283, 0x0006, % isOpen ? 1 : 0,, ahk_id %imeHwnd%
    DetectHiddenWindows, %prevDetectHiddenWindows%

    if (showTip) {
        ToolTip, % isOpen ? "[IME] JP" : "[IME] ENG"
        SetTimer, CloseToolTip, -1000
    }
    return true
}

IME_ToEnglish() {
    return IME_SetOpenStatus(false)
}

IME_ToJapanese() {
    return IME_SetOpenStatus(true)
}

InsertDateTime(fmt) {
    FormatTime, TimeString,, %fmt%
    SendInput, {Text}%TimeString%
}

Manage_N_Hold(Command) {
    ; グローバル変数を参照・変更することを宣言
    global g_HoldN_Active

    ; --- 強制停止 (Off) の処理 ---
    if (Command = "Off") {
        if (g_HoldN_Active) {
            Send, {n up}
            g_HoldN_Active := 0
            ToolTip, [停止] N長押し解除
            SetTimer, CloseToolTip, -1000
        }
        return
    }

    ; --- トグル切り替え (Toggle) の処理 ---
    if (Command = "Toggle") {
        g_HoldN_Active := !g_HoldN_Active ; 反転

        if (g_HoldN_Active) {
            Send, {n down}
            ToolTip, [自動] N長押し中... (vk1C+n+F2で停止)
            SetTimer, CloseToolTip, -1000
        } else {
            Send, {n up}
            ToolTip, [解除] Nキーを離しました
            SetTimer, CloseToolTip, -1000
        }
    }
}