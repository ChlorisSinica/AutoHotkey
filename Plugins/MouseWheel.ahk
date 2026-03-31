; ==============================================================================
; Mouse wheel helpers
; - XButton1 + Wheel: horizontal scroll
; - XButton2 + Wheel: zoom routing
; ==============================================================================

global MouseWheel_ExplorerScrollBarRepeat  := 3
global MouseWheel_ZoomRules                := {}
global MouseWheel_DebugEnabled             := false
global MouseWheel_DebugLogDir              := A_ScriptDir . "\.claude"
global MouseWheel_DebugLogPath             := MouseWheel_DebugLogDir . "\mouse_wheel_debug.log"
global MouseWheel_DefaultZoomMode          := "CtrlNumpad"
global MouseWheel_CtrlWheelApps            := "explorer.exe,pycharm64.exe,WINWORD.EXE,EXCEL.EXE,POWERPNT.EXE"

MouseWheel_RebuildZoomRules() {
    global MouseWheel_ZoomRules, MouseWheel_DefaultZoomMode, MouseWheel_CtrlWheelApps

    MouseWheel_ZoomRules := {}
    MouseWheel_ZoomRules["default"] := {Mode: MouseWheel_DefaultZoomMode}

    Loop, Parse, MouseWheel_CtrlWheelApps, `,, %A_Space%
    {
        if (A_LoopField != "")
            MouseWheel_ZoomRules[A_LoopField] := {Mode: "CtrlWheel"}
    }
}

MouseWheel_RebuildZoomRules()

MouseWheel_HScroll(direction) {
    if (WinActive("ahk_group ExplorerGroup")) {
        if (MouseWheel_ExplorerHScroll(direction))
            return
    }

    MouseWheel_SendHorizontalWheel(direction)
}

MouseWheel_Zoom(action) {
    rule := MouseWheel_GetZoomRule()

    if (rule.Mode = "CtrlWheel") {
        MouseWheel_SendCtrlWheel(action)
        return
    }

    MouseWheel_SendCtrlNumpad(action)
}

MouseWheel_GetZoomRule() {
    global MouseWheel_ZoomRules

    WinGet, exeName, ProcessName, A
    if (MouseWheel_ZoomRules.HasKey(exeName))
        return MouseWheel_ZoomRules[exeName]

    return MouseWheel_ZoomRules["default"]
}

MouseWheel_SendHorizontalWheel(direction) {
    if (direction = "Left")
        Send, {WheelLeft}
    else
        Send, {WheelRight}
}

MouseWheel_SendCtrlWheel(action) {
    ; SendInput は Ctrl down + Wheel + Ctrl up をアトミックに注入するため
    ; PyCharm の「Ctrl 二度押し = Run Anything」が誤発火しない
    if (action = "In")
        SendInput, ^{WheelUp}
    else
        SendInput, ^{WheelDown}
}

MouseWheel_SendCtrlNumpad(action) {
    if (action = "In")
        Send, ^{NumpadAdd}
    else
        Send, ^{NumpadSub}
}

MouseWheel_ExplorerHScroll(direction) {
    global MouseWheel_ExplorerScrollBarRepeat

    explorerHwnd := WinExist("A")
    if !explorerHwnd
        return false

    MouseWheel_DebugLog("explorer_hscroll_start"
        , "direction=" . direction
        . " explorer=" . MouseWheel_DebugDescribeWindow(explorerHwnd))

    ControlGet, sbHwnd, Hwnd,, ScrollBar1, ahk_id %explorerHwnd%
    if !sbHwnd {
        MouseWheel_DebugLog("explorer_hscroll_no_scrollbar"
            , "direction=" . direction
            . " explorer=" . MouseWheel_DebugDescribeWindow(explorerHwnd))
        return false
    }

    Loop, %MouseWheel_ExplorerScrollBarRepeat%
        MouseWheel_SendHScrollMessage(sbHwnd, direction)

    MouseWheel_DebugLog("explorer_hscroll_primary_sent"
        , "strategy=scrollbar1-hscroll"
        . " direction=" . direction
        . " repeat=" . MouseWheel_ExplorerScrollBarRepeat
        . " target=" . MouseWheel_DebugDescribeWindow(sbHwnd))
    return true
}

MouseWheel_SendHScrollMessage(targetHwnd, direction) {
    static WM_HSCROLL := 0x114
    static SB_LINELEFT := 0
    static SB_LINERIGHT := 1

    scrollCmd := (direction = "Left") ? SB_LINELEFT : SB_LINERIGHT
    PostMessage, %WM_HSCROLL%, %scrollCmd%, 0,, ahk_id %targetHwnd%
}

MouseWheel_DebugEnsureLogDir() {
    global MouseWheel_DebugLogDir

    if !InStr(FileExist(MouseWheel_DebugLogDir), "D")
        FileCreateDir, %MouseWheel_DebugLogDir%
}

MouseWheel_DebugSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

MouseWheel_DebugDescribeWindow(hwnd) {
    if !hwnd
        return "hwnd=0"

    WinGetClass, className, ahk_id %hwnd%
    WinGetTitle, title, ahk_id %hwnd%
    WinGet, exeName, ProcessName, ahk_id %hwnd%
    return "hwnd=" . hwnd
        . " class=" . className
        . " exe=" . exeName
        . " title=" . MouseWheel_DebugSanitize(title)
}

MouseWheel_DebugLog(event, extra := "") {
    global MouseWheel_DebugEnabled, MouseWheel_DebugLogPath

    if (!MouseWheel_DebugEnabled)
        return

    MouseWheel_DebugEnsureLogDir()
    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " extra=" . MouseWheel_DebugSanitize(extra)
    FileAppend, % line . "`n", %MouseWheel_DebugLogPath%, UTF-8
}
