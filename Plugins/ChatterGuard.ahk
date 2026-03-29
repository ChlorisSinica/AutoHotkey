; ==============================================================================
; ChatterGuard — WH_MOUSE_LL 低レベルマウスフックによるチャタリング防止
;
; 使い方:
;   #Include %A_ScriptDir%\Plugins\ChatterGuard.ahk
;   CG_Init(70, ["XButton1", "XButton2"])
;   OnExit("CG_Cleanup")
;
; DOWN/UP を独立かつクロスでデバウンス:
;   DOWN: 前回DOWN・前回UPの両方から閾値未満ならブロック
;   UP:   前回UP・前回DOWNの両方から閾値未満ならブロック
; ==============================================================================

global CG_HookHandle   := 0
global CG_CallbackPtr  := 0
global CG_Threshold    := 70

global CG_EnableXB1    := 0
global CG_EnableXB2    := 0

global CG_XB1_lastDown := 0
global CG_XB1_lastUp   := 0
global CG_XB2_lastDown := 0
global CG_XB2_lastUp   := 0

; フック生存監視用
global CG_WatchdogTimer       := ""
global CG_HookEventCount      := 0
global CG_LastCheckCount       := 0
global CG_LastEventTick        := 0
global CG_WatchdogLastCursorX  := 0
global CG_WatchdogLastCursorY  := 0

; ==============================================================================
; 公開 API
; ==============================================================================

CG_Init(threshold := 70, keys := "") {
    global CG_Threshold, CG_EnableXB1, CG_EnableXB2
    CG_Threshold := threshold
    CG_EnableXB1 := 0
    CG_EnableXB2 := 0

    if !IsObject(keys)
        return

    for _, keyName in keys {
        if (keyName = "XButton1")
            CG_EnableXB1 := 1
        else if (keyName = "XButton2")
            CG_EnableXB2 := 1
    }

    if (CG_EnableXB1 || CG_EnableXB2) {
        CG_InstallHook()
        CG_StartWatchdog()
    }
}

CG_Cleanup(ExitReason := "", ExitCode := 0) {
    CG_StopWatchdog()
    CG_RemoveHook()
}

; ==============================================================================
; フックのインストール / 削除
; ==============================================================================

CG_InstallHook() {
    global CG_HookHandle, CG_CallbackPtr

    if (CG_HookHandle)
        return

    CG_CallbackPtr := RegisterCallback("CG_LowLevelMouseProc")
    CG_HookHandle := DllCall("SetWindowsHookEx"
        , "Int",  14
        , "Ptr",  CG_CallbackPtr
        , "Ptr",  DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        , "UInt", 0
        , "Ptr")
}

CG_RemoveHook() {
    global CG_HookHandle, CG_CallbackPtr

    if (CG_HookHandle) {
        DllCall("UnhookWindowsHookEx", "Ptr", CG_HookHandle)
        CG_HookHandle := 0
    }
    CG_CallbackPtr := 0
}

; ==============================================================================
; 低レベルマウスフック コールバック
; ==============================================================================

CG_LowLevelMouseProc(nCode, wParam, lParam) {
    Critical

    global CG_EnableXB1, CG_EnableXB2
    global CG_XB1_lastDown, CG_XB1_lastUp, CG_XB2_lastDown, CG_XB2_lastUp
    global CG_HookEventCount, CG_LastEventTick

    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    CG_HookEventCount += 1
    CG_LastEventTick := A_TickCount

    if (wParam != 0x20B && wParam != 0x20C)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    flags := NumGet(lParam + 0, 12, "UInt")
    if (flags & 0x01)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    mouseData := NumGet(lParam + 0, 8, "UInt")
    xButton := (mouseData >> 16) & 0xFFFF

    if (xButton = 1 && !CG_EnableXB1)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    if (xButton = 2 && !CG_EnableXB2)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    if (xButton != 1 && xButton != 2)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    eventTime := NumGet(lParam + 0, 16, "UInt")

    ; === XButton1 DOWN ===
    if (wParam = 0x20B && xButton = 1) {
        elapsed := eventTime - CG_XB1_lastDown
        if (elapsed >= 0 && elapsed < 70)
            return 1
        sinceUp := eventTime - CG_XB1_lastUp
        if (sinceUp >= 0 && sinceUp < 70)
            return 1
        CG_XB1_lastDown := eventTime
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }

    ; === XButton1 UP ===
    if (wParam = 0x20C && xButton = 1) {
        elapsed := eventTime - CG_XB1_lastUp
        if (elapsed >= 0 && elapsed < 70)
            return 1
        sinceDown := eventTime - CG_XB1_lastDown
        if (sinceDown >= 0 && sinceDown < 70)
            return 1
        CG_XB1_lastUp := eventTime
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }

    ; === XButton2 DOWN ===
    if (wParam = 0x20B && xButton = 2) {
        elapsed := eventTime - CG_XB2_lastDown
        if (elapsed >= 0 && elapsed < 70)
            return 1
        sinceUp := eventTime - CG_XB2_lastUp
        if (sinceUp >= 0 && sinceUp < 70)
            return 1
        CG_XB2_lastDown := eventTime
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }

    ; === XButton2 UP ===
    if (wParam = 0x20C && xButton = 2) {
        elapsed := eventTime - CG_XB2_lastUp
        if (elapsed >= 0 && elapsed < 70)
            return 1
        sinceDown := eventTime - CG_XB2_lastDown
        if (sinceDown >= 0 && sinceDown < 70)
            return 1
        CG_XB2_lastUp := eventTime
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    }

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

; ==============================================================================
; フック生存監視 (Watchdog)
; ==============================================================================

CG_StartWatchdog() {
    global CG_WatchdogTimer, CG_WatchdogLastCursorX, CG_WatchdogLastCursorY
    VarSetCapacity(pt, 8, 0)
    DllCall("GetCursorPos", "Ptr", &pt)
    CG_WatchdogLastCursorX := NumGet(pt, 0, "Int")
    CG_WatchdogLastCursorY := NumGet(pt, 4, "Int")
    CG_WatchdogTimer := Func("CG_CheckHookHealth")
    SetTimer, % CG_WatchdogTimer, 30000
}

CG_StopWatchdog() {
    global CG_WatchdogTimer
    if (CG_WatchdogTimer) {
        SetTimer, % CG_WatchdogTimer, Off
        CG_WatchdogTimer := ""
    }
}

CG_CheckHookHealth() {
    global CG_HookHandle, CG_HookEventCount, CG_LastCheckCount, CG_LastEventTick
    global CG_WatchdogLastCursorX, CG_WatchdogLastCursorY

    if (!CG_HookHandle) {
        CG_InstallHook()
        return
    }

    VarSetCapacity(pt, 8, 0)
    DllCall("GetCursorPos", "Ptr", &pt)
    curX := NumGet(pt, 0, "Int")
    curY := NumGet(pt, 4, "Int")
    cursorMoved := (curX != CG_WatchdogLastCursorX || curY != CG_WatchdogLastCursorY)
    CG_WatchdogLastCursorX := curX
    CG_WatchdogLastCursorY := curY

    if (CG_HookEventCount = CG_LastCheckCount) {
        if (cursorMoved || (CG_LastEventTick && (A_TickCount - CG_LastEventTick > 60000))) {
            CG_RemoveHook()
            CG_InstallHook()
        }
    }
    CG_LastCheckCount := CG_HookEventCount
}
