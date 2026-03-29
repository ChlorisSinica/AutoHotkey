global g_HoldN_Active := 0

IME_GetTargetHwnd(ByRef activeHwnd := 0) {
    WinGet, activeHwnd, ID, A
    if !activeHwnd
        return 0

    focusHwnd := 0
    threadId := DllCall("GetWindowThreadProcessId", "Ptr", activeHwnd, "UInt*", 0, "UInt")
    if (threadId) {
        guiInfoSize := 8 + (A_PtrSize * 6) + 16
        VarSetCapacity(guiInfo, guiInfoSize, 0)
        NumPut(guiInfoSize, guiInfo, 0, "UInt")
        if DllCall("GetGUIThreadInfo", "UInt", threadId, "Ptr", &guiInfo)
            focusHwnd := NumGet(guiInfo, 8 + A_PtrSize, "Ptr")
    }

    if !focusHwnd {
        ControlGetFocus, focusedControl, ahk_id %activeHwnd%
        if (focusedControl != "")
            ControlGet, focusHwnd, Hwnd,, %focusedControl%, ahk_id %activeHwnd%
    }

    return focusHwnd ? focusHwnd : activeHwnd
}

IME_GetOpenStatusForHwnd(hwnd) {
    if !hwnd
        return ""

    hImc := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if !hImc
        return ""

    isOpen := DllCall("imm32\ImmGetOpenStatus", "Ptr", hImc, "Int")
    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hImc)
    return isOpen ? 1 : 0
}

IME_GetVerifiedOpenStatus(targetHwnd, activeHwnd := 0) {
    status := IME_GetOpenStatusForHwnd(targetHwnd)
    if (status != "")
        return status
    if (activeHwnd && activeHwnd != targetHwnd)
        return IME_GetOpenStatusForHwnd(activeHwnd)
    return ""
}

IME_TrySetOpenStatusForHwnd(hwnd, isOpen) {
    if !hwnd
        return false

    hImc := DllCall("imm32\ImmGetContext", "Ptr", hwnd, "Ptr")
    if !hImc
        return false

    DllCall("imm32\ImmSetOpenStatus", "Ptr", hImc, "Int", isOpen ? 1 : 0)
    DllCall("imm32\ImmReleaseContext", "Ptr", hwnd, "Ptr", hImc)
    Sleep, 10
    status := IME_GetOpenStatusForHwnd(hwnd)
    return (status != "" && status = (isOpen ? 1 : 0))
}

IME_TrySetOpenStatusViaDefaultImeWindow(hwnd, isOpen) {
    if !hwnd
        return false

    imeHwnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if !imeHwnd
        return false

    prevDetectHiddenWindows := A_DetectHiddenWindows
    DetectHiddenWindows, On
    SendMessage, 0x0283, 0x0006, % isOpen ? 1 : 0,, ahk_id %imeHwnd%
    DetectHiddenWindows, %prevDetectHiddenWindows%
    Sleep, 10
    status := IME_GetOpenStatusForHwnd(hwnd)
    return (status != "" && status = (isOpen ? 1 : 0))
}

IME_SendKeyAndRestoreCapsState(keySpec) {
    capsWasOn := GetKeyState("CapsLock", "T")
    usesCapsLock := InStr(keySpec, "CapsLock") ? true : false

    SendInput, %keySpec%
    if (usesCapsLock && GetKeyState("CapsLock", "T") != capsWasOn)
        SetCapsLockState, % capsWasOn ? "On" : "Off"
}

IME_TrySendOpenCloseKey(isOpen, targetHwnd, activeHwnd := 0) {
    keySpecs := isOpen ? ["{vk16}", "{vk15}"] : ["{vk1A}", "{vk15}"]
    desiredStatus := isOpen ? 1 : 0
    sawUnverified := false

    for _, keySpec in keySpecs {
        IME_SendKeyAndRestoreCapsState(keySpec)
        Sleep, 25
        status := IME_GetVerifiedOpenStatus(targetHwnd, activeHwnd)
        if (status = "") {
            sawUnverified := true
            continue
        }
        if (status != "" && status = desiredStatus)
            return true
    }
    return sawUnverified ? -1 : false
}

CapsLock_SetState(isOn, showTip := true) {
    desiredState := isOn ? 1 : 0
    currentState := GetKeyState("CapsLock", "T") ? 1 : 0

    if (currentState != desiredState) {
        DllCall("user32\keybd_event", "UChar", 0x14, "UChar", 0x45, "UInt", 0, "UPtr", 0)
        Sleep, 30
        DllCall("user32\keybd_event", "UChar", 0x14, "UChar", 0x45, "UInt", 2, "UPtr", 0)
        Sleep, 30
    }

    finalState := GetKeyState("CapsLock", "T") ? 1 : 0
    success := (finalState = desiredState)

    if (showTip) {
        if (success)
            ToolTip, % finalState ? "[CapsLock] ON" : "[CapsLock] OFF"
        else
            ToolTip, % "[CapsLock] 変更失敗"
        SetTimer, CloseToolTip, -1000
    }
    return success
}

CapsLock_ToggleState(showTip := true) {
    currentState := GetKeyState("CapsLock", "T") ? 1 : 0
    return CapsLock_SetState(!currentState, showTip)
}

IME_SetOpenStatus(isOpen, showTip := true) {
    desiredStatus := isOpen ? 1 : 0
    activeHwnd := 0
    targetHwnd := IME_GetTargetHwnd(activeHwnd)
    if !targetHwnd
        return false

    currentStatus := IME_GetVerifiedOpenStatus(targetHwnd, activeHwnd)
    success := (currentStatus != "" && currentStatus = desiredStatus)

    if (!success && currentStatus = "")
        success := IME_TrySendOpenCloseKey(isOpen, targetHwnd, activeHwnd)
    if !success
        success := IME_TrySetOpenStatusForHwnd(targetHwnd, isOpen)
    if (!success && activeHwnd && activeHwnd != targetHwnd)
        success := IME_TrySetOpenStatusForHwnd(activeHwnd, isOpen)
    if !success
        success := IME_TrySetOpenStatusViaDefaultImeWindow(targetHwnd, isOpen)
    if (!success && activeHwnd && activeHwnd != targetHwnd)
        success := IME_TrySetOpenStatusViaDefaultImeWindow(activeHwnd, isOpen)
    if !success
        success := IME_TrySendOpenCloseKey(isOpen, targetHwnd, activeHwnd)

    if (showTip) {
        if (success = true)
            ToolTip, % isOpen ? "[IME] かな" : "[IME] 英"
        else if (success = -1)
            ToolTip, % isOpen ? "[IME] かな切替要求" : "[IME] 英切替要求"
        else
            ToolTip, % isOpen ? "[IME] かな切替失敗" : "[IME] 英切替失敗"
        SetTimer, CloseToolTip, -1000
    }
    return success ? true : false
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
