; ==========================================================
; --- アプリケーション初期化 + ユーティリティ ---
; ==========================================================

; ==========================================================
; --- 初期化 ---
; ==========================================================
App_Init() {
    global profilePath
    ; DPI スケーリング環境でも座標系を安定させる。
    DllCall("SetThreadDpiAwarenessContext", "ptr", -4)
    ; 外部アプリ起動やパス組み立てで使うユーザープロファイルを保持する。
    EnvGet, profilePath, USERPROFILE

    ; ランタイム例外は共通ハンドラで記録する。
    OnError(Func("App_OnError"))

    ; インジケータと基本通知を先に立ち上げる。
    Indicator_Init()
    TrayTip, AutoHotkey, Script Reloaded, 2

    ; 設定値を読み込んでから feature 依存の初期化へ進む。
    SUI_LoadConfig()
    ; ChatterGuard はホットキーではなく低レベルマウスフック。
    ; 設定で ON の場合のみ起動時に XButton1/XButton2 監視を開始する。
    if (EnableChatterGuard)
        CG_Init(["XButton1", "XButton2"])
    ; 終了時は設定状態にかかわらずフック解放を保証する。
    OnExit("CG_Cleanup")

    ; デバッグ出力先と各 feature の補助状態を初期化する。
    Debug_CreateChannel("_Runtime", A_ScriptDir . "\.claude\runtime_error.log", 262144, true)
    MG_DebugInit()
    MouseWheel_DebugInit()
    Browser_DebugInit()
    PPT_DebugInit()
    ; MouseCursor 側の hotkey メタデータを構築して help/state 参照に使う。
    Cursor_RegisterHotkeys(Cursor_GetHotkeyConfig())
    ; PowerPoint のキャプション監視を開始する。
    PPT_CaptionInit()
}

; ==========================================================
; --- クリップボード安全書き込み ---
; --- SetClipboardData 競合時にリトライ。ClipboardAll バイナリ対応。
; ==========================================================
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

; ==========================================================
; --- OnError 安全ネット ---
; --- 全ランタイムエラーをログに記録してからデフォルト処理に渡す。
; --- クリップボード競合エラーは既知のため抑制する。
; ==========================================================
App_OnError(exception) {
    ; エラーリングバッファに記録（Debug_DumpState で参照可能）
    Debug_PushError("runtime_error", exception)

    ; ファイルにも記録
    Debug_Log("_Runtime", "runtime_error"
        , "msg=" . Debug_Sanitize(exception.Message)
        . " what=" . Debug_Sanitize(exception.What)
        . " file=" . exception.File
        . " line=" . exception.Line)

    ; クリップボード競合は既知 → ダイアログ抑制
    if InStr(exception.Message, "SetClipboardData")
        return true

    ; その他のエラーはデフォルト動作（ダイアログ表示）
    return false
}

; ==========================================================
; --- デバッグ ---
; --- F4キーでIME状態やプロセス名などをツールチップ表示 + ログ記録
; ==========================================================
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
