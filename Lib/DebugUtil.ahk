; ==========================================================
; --- 共通デバッグユーティリティ ---
; チャンネルベースのログ出力 + AI ワークフロー向け状態ダンプ
; ==========================================================
global _Debug_Channels       := {}
global _Debug_ErrorRing      := []
global _Debug_ErrorRingPos   := 0
global _Debug_ErrorRingMax   := 50

; ==========================================================
; --- チャンネル管理 ---
; ==========================================================
Debug_CreateChannel(name, logPath, maxBytes, enabled) {
    global _Debug_Channels

    SplitPath, logPath,, logDir
    _Debug_Channels[name] := {LogDir: logDir
        , LogPath: logPath
        , MaxBytes: maxBytes
        , Enabled: enabled
        , StateCallback: ""}
}

Debug_SetStateCallback(channel, funcName) {
    global _Debug_Channels

    if _Debug_Channels.HasKey(channel)
        _Debug_Channels[channel].StateCallback := funcName
}

Debug_SetEnabled(channel, flag) {
    global _Debug_Channels

    if _Debug_Channels.HasKey(channel)
        _Debug_Channels[channel].Enabled := flag
}

Debug_IsEnabled(channel) {
    global _Debug_Channels

    return _Debug_Channels.HasKey(channel) && _Debug_Channels[channel].Enabled
}

; ==========================================================
; --- ログ出力 ---
; ==========================================================
Debug_Log(channel, event, extra := "") {
    global _Debug_Channels

    if !_Debug_Channels.HasKey(channel)
        return
    ch := _Debug_Channels[channel]
    if (!ch.Enabled)
        return

    Debug_EnsureDir(ch.LogDir)
    Debug_Rotate(ch)

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event

    if (extra != "")
        line .= " extra=" . Debug_Sanitize(extra)

    cb := ch.StateCallback
    if (cb != "" && IsFunc(cb)) {
        stateText := %cb%()
        if (stateText != "")
            line .= " " . stateText
    }

    FileAppend, % line . "`n", % ch.LogPath, UTF-8
    OutputDebug, % "[" . channel . "] " . line
}

Debug_LogCatch(channel, event, exception) {
    msg := ""
    if IsObject(exception) {
        msg := exception.Message
        if (exception.What != "")
            msg .= " what=" . exception.What
        if (exception.File != "")
            msg .= " file=" . exception.File
        if (exception.Line != "")
            msg .= " line=" . exception.Line
    } else {
        msg := exception . ""
    }

    Debug_PushError(event, exception)
    Debug_Log(channel, event, msg)
}

; ==========================================================
; --- サニタイズ ---
; ==========================================================
Debug_Sanitize(text) {
    if IsObject(text) {
        if (text.Message != "")
            text := text.Message
        else if (text.What != "")
            text := text.What
        else
            text := "[object]"
    }

    text := text . ""
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

; ==========================================================
; --- ローテーション ---
; ==========================================================
Debug_Rotate(ByRef ch) {
    path := ch.LogPath
    if !FileExist(path)
        return

    FileGetSize, logSize, %path%
    if (logSize < ch.MaxBytes)
        return

    backupPath := RegExReplace(path, "\.log$", ".old.log")
    FileDelete, %backupPath%
    FileMove, %path%, %backupPath%, 1
}

; ==========================================================
; --- ログファイルを開く ---
; ==========================================================
Debug_OpenLog(channel) {
    global _Debug_Channels

    if !_Debug_Channels.HasKey(channel)
        return
    ch := _Debug_Channels[channel]

    Debug_EnsureDir(ch.LogDir)
    logPath := ch.LogPath
    if !FileExist(logPath)
        FileAppend,, %logPath%, UTF-8

    Run, notepad.exe "%logPath%"
}

; ==========================================================
; --- エラーリングバッファ ---
; ==========================================================
Debug_PushError(event, exception) {
    global _Debug_ErrorRing, _Debug_ErrorRingPos, _Debug_ErrorRingMax

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    entry := {Time: stamp . "." . A_MSec, Event: event}
    if IsObject(exception) {
        entry.Message := exception.Message
        entry.What := exception.What
    } else {
        entry.Message := exception . ""
        entry.What := ""
    }

    _Debug_ErrorRingPos := Mod(_Debug_ErrorRingPos, _Debug_ErrorRingMax) + 1
    _Debug_ErrorRing[_Debug_ErrorRingPos] := entry
}

Debug_GetRecentErrors(count := 20) {
    global _Debug_ErrorRing, _Debug_ErrorRingPos, _Debug_ErrorRingMax

    results := []
    pos := _Debug_ErrorRingPos
    Loop, %count% {
        if (pos < 1)
            break
        if !_Debug_ErrorRing.HasKey(pos)
            break
        results.Push(_Debug_ErrorRing[pos])
        pos -= 1
        if (pos < 1)
            pos := _Debug_ErrorRingMax
        if (pos = _Debug_ErrorRingPos && A_Index > 1)
            break
    }
    return results
}

; ==========================================================
; --- 状態ダンプ (AI ワークフロー向け) ---
; ==========================================================
Debug_DumpState(outputPath := "") {
    global _Debug_Channels, EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    global EnableMouseCursorMode

    if (outputPath = "")
        outputPath := A_ScriptDir . "\.claude\debug_dump.txt"

    SplitPath, outputPath,, outDir
    if !InStr(FileExist(outDir), "D")
        FileCreateDir, %outDir%

    out := ""

    ; --- ヘッダー ---
    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    out .= "=== Debug State Dump ===`n"
    out .= "Time: " . stamp . "." . A_MSec . "`n"
    out .= "Script: " . A_ScriptFullPath . "`n"
    out .= "AHK: " . A_AhkVersion . "`n`n"

    ; --- アクティブウィンドウ ---
    activeHwnd := WinExist("A")
    WinGetTitle, winTitle, ahk_id %activeHwnd%
    WinGetClass, winClass, ahk_id %activeHwnd%
    WinGet, winExe, ProcessName, ahk_id %activeHwnd%
    WinGetPos, winX, winY, winW, winH, ahk_id %activeHwnd%
    dpi := 0
    try dpi := DllCall("GetDpiForWindow", "ptr", activeHwnd)

    out .= "--- Active Window ---`n"
    out .= "HWND: " . activeHwnd . "`n"
    out .= "Title: " . winTitle . "`n"
    out .= "Class: " . winClass . "`n"
    out .= "Process: " . winExe . "`n"
    out .= "Position: " . winX . "," . winY . " " . winW . "x" . winH . "`n"
    out .= "DPI: " . dpi . "`n`n"

    ; --- マウス ---
    CoordMode, Mouse, Screen
    MouseGetPos, mx, my, mouseHwnd, mouseCtrl
    mouseTitle := ""
    mouseExe := ""
    if (mouseHwnd) {
        WinGetTitle, mouseTitle, ahk_id %mouseHwnd%
        WinGet, mouseExe, ProcessName, ahk_id %mouseHwnd%
    }

    out .= "--- Mouse ---`n"
    out .= "Position: " . mx . "," . my . "`n"
    out .= "Window: " . mouseHwnd . " (" . mouseExe . ")`n"
    out .= "Control: " . mouseCtrl . "`n`n"

    ; --- Enable フラグ ---
    out .= "--- Feature Flags ---`n"
    out .= "NavLayer=" . EnableNavLayer
        . " WinPlace=" . EnableWinPlace
        . " WinIsland=" . EnableWinIsland
        . " VDesk=" . EnableVDesk . "`n"
    out .= "MouseEmu=" . EnableMouseEmu
        . " MouseBtn=" . EnableMouseBtn
        . " Gestures=" . EnableGestures
        . " CursorMode=" . EnableMouseCursorMode . "`n"
    out .= "Alt=" . EnableAlt
        . " Others=" . EnableOthers
        . " Browser=" . EnableBrowser
        . " PPT=" . EnablePPT
        . " Excel=" . EnableExcel . "`n`n"

    ; --- UIA フォーカス要素 ---
    out .= "--- UIA Focused Element ---`n"
    try {
        uia := UIA_Interface()
        focused := uia.GetFocusedElement()
        out .= "Name: " . focused.CurrentName . "`n"
        out .= "Type: " . focused.CurrentLocalizedControlType . "`n"
        out .= "AutomationId: " . focused.CurrentAutomationId . "`n"
        out .= "ClassName: " . focused.CurrentClassName . "`n"
    } catch e {
        out .= "Error: " . Debug_Sanitize(e) . "`n"
    }
    out .= "`n"

    ; --- 各チャンネルのログ末尾 ---
    out .= "--- Recent Logs ---`n"
    for name, ch in _Debug_Channels {
        out .= "[" . name . "] " . ch.LogPath
        if (!ch.Enabled)
            out .= " (disabled)"
        out .= "`n"

        if FileExist(ch.LogPath) {
            FileRead, logContent, % ch.LogPath
            lines := StrSplit(logContent, "`n", "`r")
            total := lines.MaxIndex()
            startLine := total - 14
            if (startLine < 1)
                startLine := 1
            Loop {
                idx := startLine + A_Index - 1
                if (idx > total)
                    break
                lineText := lines[idx]
                if (lineText != "")
                    out .= "  " . lineText . "`n"
            }
        } else {
            out .= "  (no log file)`n"
        }
        out .= "`n"
    }

    ; --- ListVars キャプチャ ---
    out .= "--- ListVars ---`n"
    try {
        ListVars
        WinWait, ahk_class AutoHotkey ahk_pid %A_PID%,, 2
        if !ErrorLevel {
            ControlGetText, varsText, Edit1, ahk_class AutoHotkey ahk_pid %A_PID%
            WinClose, ahk_class AutoHotkey ahk_pid %A_PID%
            out .= varsText . "`n"
        } else {
            out .= "(timeout)`n"
        }
    } catch e {
        out .= "Error: " . Debug_Sanitize(e) . "`n"
    }
    out .= "`n"

    ; --- エラーリングバッファ ---
    out .= "--- Recent Errors ---`n"
    errors := Debug_GetRecentErrors(20)
    if (errors.MaxIndex() = "") {
        out .= "(none)`n"
    } else {
        for _, entry in errors {
            out .= entry.Time . " " . entry.Event
            if (entry.Message != "")
                out .= " msg=" . entry.Message
            if (entry.What != "")
                out .= " what=" . entry.What
            out .= "`n"
        }
    }

    ; --- ファイル出力 ---
    FileDelete, %outputPath%
    FileAppend, %out%, %outputPath%, UTF-8
    OutputDebug, % "[DebugDump] written to " . outputPath
    return outputPath
}

Debug_DumpToClipboard() {
    path := Debug_DumpState()
    FileRead, content, %path%
    Clipboard := content
    ToolTip, Debug dump copied to clipboard
    SetTimer, CloseToolTip, -2000
}

; ==========================================================
; --- 内部ヘルパー ---
; ==========================================================
Debug_EnsureDir(dirPath) {
    if !InStr(FileExist(dirPath), "D")
        FileCreateDir, %dirPath%
}
