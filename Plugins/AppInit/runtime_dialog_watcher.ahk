#NoEnv
#Persistent
#NoTrayIcon
#SingleInstance, Ignore
SetBatchLines, -1
DetectHiddenWindows, Off

global RDW_ParentPid := 0
global RDW_ParentScriptPath := ""
global RDW_OutputDir := A_Temp . "\AutoHotkeyRuntimeDialog"
global RDW_SeenDialogs := {}

RDW_ParentPid = %1%
RDW_ParentScriptPath = %2%
if (RDW_ParentPid = "")
    ExitApp

SetTimer, % Func("RDW_Poll"), 400
return

RDW_Poll() {
    global RDW_ParentPid, RDW_SeenDialogs

    if !RDW_IsProcessAlive(RDW_ParentPid)
        ExitApp

    currentWindows := {}
    WinGet, winList, List, ahk_class #32770 ahk_pid %RDW_ParentPid%
    Loop, %winList% {
        hwnd := winList%A_Index%
        if !hwnd
            continue

        currentWindows[hwnd] := 1
        if RDW_SeenDialogs.HasKey(hwnd)
            continue

        WinGetTitle, title, ahk_id %hwnd%
        WinGetText, winText, ahk_id %hwnd%
        if !RDW_IsRuntimeDialog(title, winText)
            continue

        payload := RDW_BuildPayload(hwnd, title, winText)
        capturePath := RDW_WriteCapture(hwnd, payload)
        RDW_TrySetClipboard(payload)
        RDW_SeenDialogs[hwnd] := capturePath
    }

    staleHwnds := []
    for hwnd, _ in RDW_SeenDialogs {
        if !currentWindows.HasKey(hwnd)
            staleHwnds.Push(hwnd)
    }
    for _, hwnd in staleHwnds
        RDW_SeenDialogs.Delete(hwnd)
}

RDW_IsProcessAlive(pid) {
    Process, Exist, %pid%
    return ErrorLevel = pid
}

RDW_IsRuntimeDialog(title, winText) {
    global RDW_ParentScriptPath

    haystack := title . "`n" . winText
    if (RDW_ParentScriptPath != "" && InStr(haystack, RDW_ParentScriptPath))
        return true
    if InStr(haystack, "Error at line")
        return true
    if InStr(haystack, "Error in")
        return true
    if InStr(haystack, "Specifically:")
        return true
    if InStr(haystack, "Line#")
        return true
    if InStr(haystack, "Call stack:")
        return true
    if InStr(haystack, "The current thread will exit")
        return true
    if InStr(haystack, "Program will exit")
        return true
    if InStr(haystack, "AutoHotkey") && InStr(haystack, "Error")
        return true
    return false
}

RDW_BuildPayload(hwnd, title, winText) {
    global RDW_ParentPid, RDW_ParentScriptPath

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    WinGetClass, className, ahk_id %hwnd%
    WinGet, processName, ProcessName, ahk_id %hwnd%
    controlDump := RDW_GetControlDump(hwnd)

    out := "=== AutoHotkey Runtime Dialog Capture ===`r`n"
    out .= "CapturedAt: " . stamp . "." . A_MSec . "`r`n"
    out .= "ParentPid: " . RDW_ParentPid . "`r`n"
    out .= "DialogHwnd: " . hwnd . "`r`n"
    out .= "Process: " . processName . "`r`n"
    out .= "Class: " . className . "`r`n"
    if (RDW_ParentScriptPath != "")
        out .= "Script: " . RDW_ParentScriptPath . "`r`n"
    out .= "`r`n--- Title ---`r`n" . title . "`r`n"
    out .= "`r`n--- WindowText ---`r`n" . winText . "`r`n"
    if (controlDump != "")
        out .= "`r`n--- Controls ---`r`n" . controlDump
    return out
}

RDW_GetControlDump(hwnd) {
    out := ""
    WinGet, controlList, ControlList, ahk_id %hwnd%
    Loop, Parse, controlList, `n, `r
    {
        ctrl := A_LoopField
        if (ctrl = "")
            continue

        ControlGetText, ctrlText, %ctrl%, ahk_id %hwnd%
        ctrlText := Trim(ctrlText, "`r`n`t ")
        if (ctrlText = "")
            continue

        out .= "[" . ctrl . "]`r`n" . ctrlText . "`r`n`r`n"
    }
    return out
}

RDW_WriteCapture(hwnd, payload) {
    global RDW_OutputDir, RDW_ParentPid

    historyDir := RDW_OutputDir . "\history"
    if !InStr(FileExist(historyDir), "D")
        FileCreateDir, %historyDir%

    FormatTime, stamp,, yyyyMMdd-HHmmss
    capturePath := historyDir . "\" . stamp . "-pid" . RDW_ParentPid . "-hwnd" . hwnd . ".txt"
    latestPath := RDW_OutputDir . "\latest.txt"

    RDW_WriteTextFile(capturePath, payload)
    RDW_WriteTextFile(latestPath, payload)
    return capturePath
}

RDW_WriteTextFile(path, text) {
    SplitPath, path,, dirPath
    if !InStr(FileExist(dirPath), "D")
        FileCreateDir, %dirPath%
    FileDelete, %path%
    FileAppend, %text%, %path%, UTF-8
}

RDW_TrySetClipboard(ByRef text, retries := 5) {
    Loop, %retries% {
        try {
            Clipboard := text
            return true
        } catch {
            if (A_Index < retries)
                Sleep, 40
        }
    }
    return false
}
