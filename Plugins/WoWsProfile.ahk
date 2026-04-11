; ==============================================================================
; World of Warships profile helpers
; - Keep hotkey declarations in main.ahk
; - Keep app-specific matching and behavior here
; ==============================================================================

global WoWs_ManageNHoldMaxMinutes   := 20
global WoWs_WindowTitleHints        := ["World of Warships"]
global WoWs_ProcessNameHints        := []
global WoWs_WindowClassHints        := []

WoWs_CanUseManageNHold() {
    global EnableOthers
    return EnableOthers && WoWs_IsManageNHoldTarget()
}

WoWs_IsManageNHoldTarget() {
    global WoWs_WindowTitleHints, WoWs_ProcessNameHints, WoWs_WindowClassHints

    WinGetTitle, activeTitle, A
    WinGet, activeExe, ProcessName, A
    WinGetClass, activeClass, A

    if WoWs_TextContainsAny(activeTitle, WoWs_WindowTitleHints)
        return true
    if WoWs_TextEqualsAny(activeExe, WoWs_ProcessNameHints)
        return true
    if WoWs_TextEqualsAny(activeClass, WoWs_WindowClassHints)
        return true
    return false
}

WoWs_ToggleNHold() {
    global WoWs_ManageNHoldMaxMinutes
    return Manage_N_Hold("Toggle", WoWs_ManageNHoldMaxMinutes * 60000, "World of Warships")
}

WoWs_StopNHold() {
    return Manage_N_Hold("Off", 0, "World of Warships")
}

WoWs_TextContainsAny(text, patterns) {
    text := text . ""
    for _, pattern in patterns {
        if (pattern != "" && InStr(text, pattern))
            return true
    }
    return false
}

WoWs_TextEqualsAny(text, patterns) {
    text := WoWs_ToLower(Trim(text . ""))
    for _, pattern in patterns {
        candidate := WoWs_ToLower(Trim(pattern . ""))
        if (candidate != "" && text = candidate)
            return true
    }
    return false
}

WoWs_ToLower(text) {
    StringLower, lowered, text
    return lowered
}
