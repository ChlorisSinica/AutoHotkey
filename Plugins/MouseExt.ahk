; ==============================================================================
; Mouse extension helpers
; - XButton1 + Wheel: horizontal scroll
; - XButton2 + Wheel: zoom routing
; ==============================================================================

global MouseExt_ExplorerScrollBarRepeat := 3
global MouseExt_ZoomRules := {}
global MouseExt_DebugEnabled := false
global MouseExt_DebugLogDir := A_ScriptDir . "\.claude"
global MouseExt_DebugLogPath := MouseExt_DebugLogDir . "\mouse_ext_debug.log"

MouseExt_ZoomRules["default"]       := {Mode: "CtrlNumpad"}
MouseExt_ZoomRules["explorer.exe"]  := {Mode: "CtrlWheel"}
MouseExt_ZoomRules["pycharm64.exe"] := {Mode: "CtrlWheel"}
MouseExt_ZoomRules["WINWORD.EXE"]   := {Mode: "CtrlWheel"}
MouseExt_ZoomRules["EXCEL.EXE"]     := {Mode: "CtrlWheel"}
MouseExt_ZoomRules["POWERPNT.EXE"]  := {Mode: "CtrlWheel"}

MouseExt_HScroll(direction) {
    if (WinActive("ahk_group ExplorerGroup")) {
        if (MouseExt_ExplorerHScroll(direction))
            return
    }

    MouseExt_SendHorizontalWheel(direction)
}

MouseExt_Zoom(action) {
    rule := MouseExt_GetZoomRule()

    if (rule.Mode = "CtrlWheel") {
        MouseExt_SendCtrlWheel(action)
        return
    }

    MouseExt_SendCtrlNumpad(action)
}

MouseExt_GetZoomRule() {
    global MouseExt_ZoomRules

    WinGet, exeName, ProcessName, A
    if (MouseExt_ZoomRules.HasKey(exeName))
        return MouseExt_ZoomRules[exeName]

    return MouseExt_ZoomRules["default"]
}

MouseExt_SendHorizontalWheel(direction) {
    if (direction = "Left")
        Send, {WheelLeft}
    else
        Send, {WheelRight}
}

MouseExt_SendCtrlWheel(action) {
    if (action = "In")
        Send, ^{WheelUp}
    else
        Send, ^{WheelDown}
}

MouseExt_SendCtrlNumpad(action) {
    if (action = "In")
        Send, ^{NumpadAdd}
    else
        Send, ^{NumpadSub}
}

MouseExt_ExplorerHScroll(direction) {
    global MouseExt_ExplorerScrollBarRepeat

    explorerHwnd := WinExist("A")
    if !explorerHwnd
        return false

    MouseExt_DebugLog("explorer_hscroll_start"
        , "direction=" . direction
        . " explorer=" . MouseExt_DebugDescribeWindow(explorerHwnd))

    ControlGet, sbHwnd, Hwnd,, ScrollBar1, ahk_id %explorerHwnd%
    if !sbHwnd {
        MouseExt_DebugLog("explorer_hscroll_no_scrollbar"
            , "direction=" . direction
            . " explorer=" . MouseExt_DebugDescribeWindow(explorerHwnd))
        return false
    }

    Loop, %MouseExt_ExplorerScrollBarRepeat%
        MouseExt_SendHScrollMessage(sbHwnd, direction)

    MouseExt_DebugLog("explorer_hscroll_primary_sent"
        , "strategy=scrollbar1-hscroll"
        . " direction=" . direction
        . " repeat=" . MouseExt_ExplorerScrollBarRepeat
        . " target=" . MouseExt_DebugDescribeWindow(sbHwnd))
    return true
}

MouseExt_SendHScrollMessage(targetHwnd, direction) {
    static WM_HSCROLL := 0x114
    static SB_LINELEFT := 0
    static SB_LINERIGHT := 1

    scrollCmd := (direction = "Left") ? SB_LINELEFT : SB_LINERIGHT
    PostMessage, %WM_HSCROLL%, %scrollCmd%, 0,, ahk_id %targetHwnd%
}

MouseExt_DebugEnsureLogDir() {
    global MouseExt_DebugLogDir

    if !InStr(FileExist(MouseExt_DebugLogDir), "D")
        FileCreateDir, %MouseExt_DebugLogDir%
}

MouseExt_DebugSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

MouseExt_DebugDescribeWindow(hwnd) {
    if !hwnd
        return "hwnd=0"

    WinGetClass, className, ahk_id %hwnd%
    WinGetTitle, title, ahk_id %hwnd%
    WinGet, exeName, ProcessName, ahk_id %hwnd%
    return "hwnd=" . hwnd
        . " class=" . className
        . " exe=" . exeName
        . " title=" . MouseExt_DebugSanitize(title)
}

MouseExt_DebugLog(event, extra := "") {
    global MouseExt_DebugEnabled, MouseExt_DebugLogPath

    if (!MouseExt_DebugEnabled)
        return

    MouseExt_DebugEnsureLogDir()
    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " extra=" . MouseExt_DebugSanitize(extra)
    FileAppend, % line . "`n", %MouseExt_DebugLogPath%, UTF-8
}
