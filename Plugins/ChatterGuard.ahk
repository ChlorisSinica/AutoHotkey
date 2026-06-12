; ==============================================================================
; ChatterGuard — WH_MOUSE_LL 低レベルマウスフックによるチャタリング防止
;
; 使い方:
;   #Include %A_ScriptDir%\Plugins\ChatterGuard.ahk
;   CG_Init(["XButton1", "XButton2"])
;   OnExit("CG_Cleanup")
;
; DOWN/UP を独立かつクロスでデバウンス:
;   DOWN: 前回DOWN・前回UPの両方から閾値未満ならブロック
;   UP:   前回UP・前回DOWNの両方から閾値未満ならブロック
;   DOWN直後すぎるUPは偽解放としてブロックし、物理的に離れていれば遅延UPで復旧
; ==============================================================================

global CG_HookHandle            := 0
global CG_CallbackPtr           := 0
global CG_EnableXB1             := 0
global CG_EnableXB2             := 0
global CG_XB1_lastDown          := 0
global CG_XB1_lastUp            := 0
global CG_XB1_isDown            := 0
global CG_XB1_deferredUpTimer   := ""
global CG_XB1_deferredDownTick  := 0
global CG_XB2_lastDown          := 0
global CG_XB2_lastUp            := 0
global CG_XB2_isDown            := 0
global CG_XB2_deferredUpTimer   := ""
global CG_XB2_deferredDownTick  := 0
; デバッグ用
global CG_DebugBlockCount       := 0
; フック生存監視用
global CG_WatchdogTimer         := ""
global CG_HookEventCount        := 0
global CG_LastCheckCount        := 0
global CG_LastEventTick         := 0
global CG_WatchdogLastCursorX   := 0
global CG_WatchdogLastCursorY   := 0

; ==============================================================================
; 公開 API
; ==============================================================================

CG_Init(keys := "") {
    global CG_EnableXB1, CG_EnableXB2
    global CG_XB1_isDown, CG_XB2_isDown
    CG_EnableXB1 := 0
    CG_EnableXB2 := 0
    CG_XB1_isDown := 0
    CG_XB2_isDown := 0

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
    global CG_XB1_deferredUpTimer, CG_XB2_deferredUpTimer
    CG_CancelDeferredUp(CG_XB1_deferredUpTimer)
    CG_CancelDeferredUp(CG_XB2_deferredUpTimer)
    CG_StopWatchdog()
    CG_RemoveHook()
}

CG_ResetState() {
    global CG_XB1_lastDown, CG_XB1_lastUp, CG_XB1_isDown, CG_XB1_deferredUpTimer, CG_XB1_deferredDownTick
    global CG_XB2_lastDown, CG_XB2_lastUp, CG_XB2_isDown, CG_XB2_deferredUpTimer, CG_XB2_deferredDownTick

    CG_CancelDeferredUp(CG_XB1_deferredUpTimer)
    CG_CancelDeferredUp(CG_XB2_deferredUpTimer)
    CG_XB1_lastDown := 0
    CG_XB1_lastUp := 0
    CG_XB1_isDown := 0
    CG_XB1_deferredDownTick := 0
    CG_XB2_lastDown := 0
    CG_XB2_lastUp := 0
    CG_XB2_isDown := 0
    CG_XB2_deferredDownTick := 0
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
    global CG_XB1_lastDown, CG_XB1_lastUp, CG_XB1_isDown, CG_XB1_deferredUpTimer, CG_XB1_deferredDownTick
    global CG_XB2_lastDown, CG_XB2_lastUp, CG_XB2_isDown, CG_XB2_deferredUpTimer, CG_XB2_deferredDownTick
    global CG_HookEventCount, CG_LastEventTick

    if (nCode < 0)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    CG_HookEventCount += 1
    CG_LastEventTick := A_TickCount

    if (wParam != 0x20B && wParam != 0x20C)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    mouseData := NumGet(lParam + 0, 8, "UInt")
    xButton := (mouseData >> 16) & 0xFFFF

    if (xButton = 1 && !CG_EnableXB1)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    if (xButton = 2 && !CG_EnableXB2)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
    if (xButton != 1 && xButton != 2)
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)

    flags := NumGet(lParam + 0, 12, "UInt")
    eventTime := NumGet(lParam + 0, 16, "UInt")

    if (flags & 0x01)
        return CG_HandleInjectedXButton(xButton, eventTime, nCode, wParam, lParam)

    ; === XButton1 DOWN ===
    if (wParam = 0x20B && xButton = 1)
        return CG_HandleXButtonDown(CG_XB1_lastDown, CG_XB1_lastUp, CG_XB1_isDown
            , CG_XB1_deferredUpTimer, CG_XB1_deferredDownTick
            , 1, eventTime, nCode, wParam, lParam)

    ; === XButton1 UP ===
    if (wParam = 0x20C && xButton = 1)
        return CG_HandleXButtonUp(CG_XB1_lastDown, CG_XB1_lastUp, CG_XB1_isDown
            , CG_XB1_deferredUpTimer, CG_XB1_deferredDownTick
            , 1, eventTime, nCode, wParam, lParam)

    ; === XButton2 DOWN ===
    if (wParam = 0x20B && xButton = 2)
        return CG_HandleXButtonDown(CG_XB2_lastDown, CG_XB2_lastUp, CG_XB2_isDown
            , CG_XB2_deferredUpTimer, CG_XB2_deferredDownTick
            , 2, eventTime, nCode, wParam, lParam)

    ; === XButton2 UP ===
    if (wParam = 0x20C && xButton = 2)
        return CG_HandleXButtonUp(CG_XB2_lastDown, CG_XB2_lastUp, CG_XB2_isDown
            , CG_XB2_deferredUpTimer, CG_XB2_deferredDownTick
            , 2, eventTime, nCode, wParam, lParam)

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

CG_HandleInjectedXButton(button, eventTime, nCode, wParam, lParam) {
    global CG_XB1_isDown, CG_XB2_isDown

    if (button = 1 && CG_XB1_isDown)
        return CG_BlockEvent()
    if (button = 2 && CG_XB2_isDown)
        return CG_BlockEvent()

    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

CG_HandleXButtonDown(ByRef lastDown, ByRef lastUp, ByRef isDown, ByRef deferredUpTimer, ByRef deferredDownTick, button, eventTime, nCode, wParam, lParam) {
    global CG_SameEventThreshold, CG_CrossEventThreshold

    if (isDown)
        return CG_BlockEvent()

    elapsed := eventTime - lastDown
    if (elapsed >= 0 && elapsed < CG_SameEventThreshold)
        return CG_BlockEvent()

    sinceUp := eventTime - lastUp
    if (sinceUp >= 0 && sinceUp < CG_CrossEventThreshold)
        return CG_BlockEvent()

    CG_CancelDeferredUp(deferredUpTimer)
    deferredDownTick := 0
    isDown := 1
    lastDown := eventTime
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

CG_HandleXButtonUp(ByRef lastDown, ByRef lastUp, ByRef isDown, ByRef deferredUpTimer, ByRef deferredDownTick, button, eventTime, nCode, wParam, lParam) {
    global CG_SameEventThreshold

    if (!isDown) {
        if (!lastDown) {
            lastUp := eventTime
            return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
        }
        return CG_BlockEvent()
    }

    elapsed := eventTime - lastUp
    if (elapsed >= 0 && elapsed < CG_SameEventThreshold)
        return CG_BlockEvent()

    CG_CancelDeferredUp(deferredUpTimer)
    deferredDownTick := 0
    isDown := 0
    lastUp := eventTime
    return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "UInt", wParam, "Ptr", lParam)
}

CG_BlockEvent() {
    global CG_DebugBlockCount
    CG_DebugBlockCount += 1
    return 1
}

CG_ScheduleDeferredUp(ByRef deferredUpTimer, ByRef deferredDownTick, button, downTick) {
    global CG_MinPressThreshold

    CG_CancelDeferredUp(deferredUpTimer)
    deferredDownTick := downTick
    delay := CG_MinPressThreshold + 5
    deferredUpTimer := Func("CG_DeferredUp").Bind(button, downTick)
    SetTimer, % deferredUpTimer, % -delay
}

CG_CancelDeferredUp(ByRef deferredUpTimer) {
    if (deferredUpTimer) {
        SetTimer, % deferredUpTimer, Off
        deferredUpTimer := ""
    }
}

CG_DeferredUp(button, downTick) {
    global CG_XB1_lastDown, CG_XB1_lastUp, CG_XB1_isDown, CG_XB1_deferredUpTimer, CG_XB1_deferredDownTick
    global CG_XB2_lastDown, CG_XB2_lastUp, CG_XB2_isDown, CG_XB2_deferredUpTimer, CG_XB2_deferredDownTick

    if (button = 1) {
        CG_XB1_deferredUpTimer := ""
        if (CG_XB1_deferredDownTick != downTick || !CG_XB1_isDown || CG_XB1_lastDown != downTick)
            return
        CG_XB1_deferredDownTick := 0
        if (CG_IsXButtonPhysicallyDown(1))
            return
        CG_XB1_isDown := 0
        CG_XB1_lastUp := A_TickCount
        SendInput % "{XButton1 Up}"
        return
    }

    if (button = 2) {
        CG_XB2_deferredUpTimer := ""
        if (CG_XB2_deferredDownTick != downTick || !CG_XB2_isDown || CG_XB2_lastDown != downTick)
            return
        CG_XB2_deferredDownTick := 0
        if (CG_IsXButtonPhysicallyDown(2))
            return
        CG_XB2_isDown := 0
        CG_XB2_lastUp := A_TickCount
        SendInput % "{XButton2 Up}"
        return
    }
}

CG_IsXButtonPhysicallyDown(button) {
    vk := (button = 1) ? 0x05 : 0x06
    return (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000) ? 1 : 0
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
