; ==========================================================
; --- アプリケーション初期化 + ユーティリティ ---
; ==========================================================

; ── 初期化 ─────────────────────────────────────────────────

App_Init() {
    global profilePath
    DllCall("SetThreadDpiAwarenessContext", "ptr", -4)
    EnvGet, profilePath, USERPROFILE

    OnError(Func("App_HandleClipError"))

    Indicator_Init()
    TrayTip, AutoHotkey, Script Reloaded, 2

    SUI_LoadConfig()
    if (EnableChatterGuard)
        CG_Init(["XButton1", "XButton2"])
    OnExit("CG_Cleanup")

    MG_DebugInit()
    Cursor_RegisterHotkeys(Cursor_GetHotkeyConfig())
    PPT_SpacingLog("startup", "script=" . A_ScriptFullPath)
    PPT_CaptionInit()
}

; ── クリップボード安全書き込み ──────────────────────────────────
; SetClipboardData 競合時にリトライ。ClipboardAll バイナリ対応。

ClipboardWrite(ByRef data, retries := 5) {
    Loop, %retries% {
        try {
            Clipboard := data
            return true
        } catch {
            if (A_Index < retries)
                Sleep, 30
        }
    }
    return false
}

; ── OnError 安全ネット ─────────────────────────────────────────

App_HandleClipError(exception) {
    if InStr(exception.Message, "SetClipboardData")
        return true
    return false
}

; ── デバッグ ───────────────────────────────────────────────────

App_DebugStatus() {
    hTarget := IME_GetTargetHwnd(activeHwnd)
    imeOn := IME_GetVerifiedOpenStatus(hTarget, activeHwnd)
    WinGet, procName, ProcessName, A
    debugMsg := "ChatterGuard: Blocks=" . CG_DebugBlockCount
        . " DD/UU=50ms UD=30ms DU=removed"
        . "`nIME=" . imeOn . " hTarget=" . hTarget
        . " activeHwnd=" . activeHwnd
        . "`nproc=" . procName
    FileAppend, % A_Now . " " . debugMsg . "`n", %A_ScriptDir%\.claude\debug_f4.log
    ToolTip, %debugMsg%
    SetTimer, CloseToolTip, -5000
}
