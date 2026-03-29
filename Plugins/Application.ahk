; ==========================================================
; 1. グループ定義 (ShortcutMap.ahkで使用するグループ名と合わせる)
; ==========================================================
SetTitleMatchMode, 2
GroupAdd, OfficeGroup, ahk_exe POWERPNT.EXE
GroupAdd, OfficeGroup, ahk_exe EXCEL.EXE
GroupAdd, EditorGroup, Notepads
GroupAdd, EditorGroup, ahk_exe Code.exe
GroupAdd, EditorGroup, ahk_exe notepad.exe
GroupAdd, BrowserGroup, ahk_exe msedge.exe
GroupAdd, BrowserGroup, ahk_exe chrome.exe
GroupAdd, BrowserGroup, ahk_exe firefox.exe
GroupAdd, BrowserGroup, ahk_exe brave.exe
GroupAdd, ExplorerGroup, ahk_class CabinetWClass
GroupAdd, ExplorerGroup, ahk_class ExploreWClass
GroupAdd, JetBrainsGroup, ahk_class pycharm64.exe

global TextEditorProvider     := "Notepads"
global TextEditorCustomPath   := ""
global TextEditorArgsTemplate := ""

CloseToolTip() {
    ToolTip
}

CloseAltTabMenu() {
    if GetKeyState("Alt") {
        Send, {Alt Up}
    }
}

AltTabAction(Dir) {
    ; まだAltが押されていなければ（メニューが出ていなければ）Altを押す
    if !GetKeyState("Alt") {
        Send, {Alt Down}
    }

    ; タブ移動信号を送る
    if (Dir = "Next") {
        Send, {Tab}
    } else {
        Send, +{Tab}
    }
}

ReplaceEscapeToSlash() {
    KeyWait, Ctrl
    KeyWait, Alt
    Clipboard := ""
    Send, +^c
    ClipWait, 2
    text := Clipboard
    StringReplace, text, text, \, /, All
    Clipboard := text
}

OpenWithMspaint(withFile = 1) {
    TargetArgs := ""
    if (withFile = 1) {
        KeyWait, Ctrl
        KeyWait, Alt
        Clipboard := ""
        Send, +^c
        ClipWait, 2
        if (ErrorLevel = 0) {
            TargetArgs := Clipboard
        }
    }

    Run, mspaint.exe "%TargetArgs%"
}

IsNotepadsAvailable() {
    EnvGet, localAppData, LOCALAPPDATA
    return FileExist(localAppData . "\Microsoft\WindowsApps\Notepads.exe") ? 1 : 0
}

TextEditor_CollectTargetArgs(withFile := 1) {
    TargetArgs := ""
    if (withFile = 1) {
        KeyWait, Ctrl
        KeyWait, Alt
        Clipboard := ""
        Send, +^c
        ClipWait, 2
        if (ErrorLevel = 0) {
            TargetArgs := Clipboard
        }
    }
    return TargetArgs
}

TextEditor_RunProvider(provider, targetArgs := "", customPath := "", argsTemplate := "") {
    provider := Trim(provider)
    if (provider = "")
        provider := "Notepads"

    if (provider = "Notepads" && !IsNotepadsAvailable())
        provider := "Notepad"

    if (provider = "VSCode") {
        if (targetArgs != "") {
            launchCmd := "code -n """ . targetArgs . """"
            try {
                Run, %launchCmd%
            } catch {
                Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" -n "%targetArgs%"
            }
            return
        }

        OpenVSCode()
        return
    }

    if (provider = "Custom") {
        customPath := Trim(customPath)
        if (customPath = "") {
            MsgBox, 48, Text Editor, Custom editor path is empty.
            return
        }

        resolvedArgs := Trim(argsTemplate)
        quotedTarget := (targetArgs != "") ? """" . targetArgs . """" : ""
        resolvedArgs := StrReplace(resolvedArgs, "{path}", quotedTarget)
        resolvedArgs := StrReplace(resolvedArgs, "{script_dir}", """" . A_ScriptDir . """")
        resolvedArgs := Trim(resolvedArgs)

        if (resolvedArgs = "" && quotedTarget != "")
            resolvedArgs := quotedTarget

        if (resolvedArgs != "")
            Run, "%customPath%" %resolvedArgs%
        else
            Run, "%customPath%"
        return
    }

    if (provider = "Notepad") {
        if (targetArgs != "")
            Run, notepad.exe "%targetArgs%"
        else
            Run, notepad.exe
        return
    }

    if (targetArgs != "")
        Run, Notepads "%targetArgs%"
    else
        Run, Notepads
}

OpenTextEditor(withFile = 1) {
    global TextEditorProvider, TextEditorCustomPath, TextEditorArgsTemplate

    targetArgs := TextEditor_CollectTargetArgs(withFile)
    TextEditor_RunProvider(TextEditorProvider, targetArgs, TextEditorCustomPath, TextEditorArgsTemplate)
}

OpenWithNotePad(withFile = 1, editorType = 1) {
    global TextEditorProvider

    if (TextEditorProvider = "") {
        if (editorType = 1 && IsNotepadsAvailable())
            TextEditorProvider := "Notepads"
        else
            TextEditorProvider := "Notepad"
    }

    OpenTextEditor(withFile)
}

; アプリケーション起動ヘルパー
OpenMoveExplorer(path, xr, yr, wr, hr) {
    Run, explorer.exe "%path%"
    WinWaitActive, ahk_class CabinetWClass, , 3
    MoveWindowRatio("A", xr, yr, wr, hr)
}

FindVSCodeWindowForPath(targetPath) {
    WinGet, windowList, List, ahk_exe Code.exe
    SplitPath, targetPath, folderName
    titleNeedle := folderName . " - Visual Studio Code"

    Loop, %windowList% {
        thisID := windowList%A_Index%
        WinGetTitle, title, ahk_id %thisID%
        if (InStr(title, titleNeedle))
            return thisID
    }

    return 0
}

WaitForVSCodeWindowForPath(targetPath, timeoutMs := 8000) {
    deadline := A_TickCount + timeoutMs

    while (A_TickCount <= deadline) {
        targetID := FindVSCodeWindowForPath(targetPath)
        if (targetID)
            return targetID
        Sleep, 100
    }

    return 0
}

OpenVSCode() {
    targetPath := A_ScriptDir
    TargetID := FindVSCodeWindowForPath(targetPath)

    if (TargetID) {
        WinActivate, ahk_id %TargetID%
    } else {
        launchCmd := "code -n """ . targetPath . """"
        try {
            Run, %launchCmd%
        } catch {
            Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" -n "%targetPath%"
        }
        TargetID := WaitForVSCodeWindowForPath(targetPath, 8000)
        if (TargetID)
            WinActivate, ahk_id %TargetID%
    }

    if (!TargetID)
        return

    ; VSCodeも正規化比率で配置 (例: 右側メイン配置に近い設定)
    MoveWindowRatio("ahk_id " . TargetID, 0.503, 0.216, 0.404, 0.766)
}

; --- メディア操作の実行サブルーチン ---
ExecuteMediaAction() {
    global MediaTapCount
    if (MediaTapCount = 1) {
        Send, {Media_Play_Pause}
    } else if (MediaTapCount = 2) {
        Send, {Media_Next}
    } else if (MediaTapCount >= 3) {
        Send, {Media_Prev}
    }
    MediaTapCount := 0
}
