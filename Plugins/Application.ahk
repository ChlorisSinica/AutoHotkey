; ==========================================================
; 1. グループ定義 (ShortcutMap.ahkで使用するグループ名と合わせる)
; ==========================================================
SetTitleMatchMode, 2
GroupAdd, OfficeGroup, ahk_exe POWERPNT.EXE
GroupAdd, OfficeGroup, ahk_exe EXCEL.EXE
GroupAdd, EditorGroup, Notepads
GroupAdd, EditorGroup, ahk_exe devenv.exe
GroupAdd, EditorGroup, ahk_exe Code.exe
GroupAdd, EditorGroup, ahk_exe notepad.exe
GroupAdd, BrowserGroup, ahk_exe msedge.exe
GroupAdd, BrowserGroup, ahk_exe chrome.exe
GroupAdd, BrowserGroup, ahk_exe firefox.exe
GroupAdd, BrowserGroup, ahk_exe brave.exe
GroupAdd, ExplorerGroup, ahk_class CabinetWClass
GroupAdd, ExplorerGroup, ahk_class ExploreWClass
GroupAdd, JetBrainsGroup, ahk_class pycharm64.exe

global TextEditorProvider     := "VSCode"
; global TextEditorProvider     := "Notepad"
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

Emergency_ReleaseAllInputs() {
    Critical

    beforePressed := Emergency_GetPressedInputNames()
    actions := []

    if IsFunc("MouseBtn_ResetState") {
        MouseBtn_ResetState()
        actions.Push("MouseBtn")
    }
    if IsFunc("Cursor_StopContinuous") {
        Cursor_StopContinuous()
        actions.Push("CursorMove")
    }
    if IsFunc("Cursor_ScrollStop") {
        Cursor_ScrollStop()
        actions.Push("CursorScroll")
    }
    if IsFunc("Cursor_ReleaseHeldClicks") {
        Cursor_ReleaseHeldClicks()
        actions.Push("HeldClicks")
    }
    if IsFunc("PPT_SpacingRepeatStop") {
        PPT_SpacingRepeatStop()
        actions.Push("PPTSpacing")
    }
    if IsFunc("PPT_GridRepeatStop") {
        PPT_GridRepeatStop()
        actions.Push("PPTGrid")
    }
    if IsFunc("Manage_N_Hold") {
        Manage_N_Hold("Off", 0, "Emergency")
        actions.Push("NHold")
    }

    CloseAltTabMenu()
    upCount := Emergency_SendAllInputUps()
    Sleep, 50
    afterPressed := Emergency_GetPressedInputNames()

    msg := "全入力解除`n"
        . "処理: " . Emergency_Join(actions, ", ") . "`n"
        . "Up送信: " . upCount . " keys`n"
        . "解除前: " . Emergency_Join(beforePressed, ", ", "なし") . "`n"
        . "解除後: " . Emergency_Join(afterPressed, ", ", "なし")
    ToolTip, %msg%
    SetTimer, CloseToolTip, -4000
}

Emergency_SendAllInputUps() {
    keys := []

    for _, keyName in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        keys.Push(keyName)
    for _, keyName in ["Shift", "LShift", "RShift", "Ctrl", "LCtrl", "RCtrl", "Alt", "LAlt", "RAlt", "LWin", "RWin"]
        keys.Push(keyName)
    for _, keyName in ["vk1C", "AppsKey", "Space", "Tab", "Enter", "Esc", "Backspace", "Delete", "Insert"]
        keys.Push(keyName)
    for _, keyName in ["Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn"]
        keys.Push(keyName)

    Loop, 26 {
        keyName := Chr(Asc("A") + A_Index - 1)
        keys.Push(keyName)
    }
    Loop, 10
        keys.Push(A_Index - 1)
    Loop, 24
        keys.Push("F" . A_Index)

    for _, keyName in keys
        SendInput % "{" . keyName . " Up}"
    return keys.Length()
}

Emergency_GetPressedInputNames() {
    keys := []
    pressed := []

    for _, keyName in ["LButton", "RButton", "MButton", "XButton1", "XButton2"]
        keys.Push(keyName)
    for _, keyName in ["Shift", "LShift", "RShift", "Ctrl", "LCtrl", "RCtrl", "Alt", "LAlt", "RAlt", "LWin", "RWin"]
        keys.Push(keyName)
    for _, keyName in ["vk1C", "AppsKey", "Space", "Tab", "Enter", "Esc", "Backspace", "Delete", "Insert"]
        keys.Push(keyName)
    for _, keyName in ["Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn"]
        keys.Push(keyName)

    for _, keyName in keys {
        if GetKeyState(keyName)
            pressed.Push(keyName)
    }
    return pressed
}

Emergency_Join(items, separator := ", ", emptyText := "") {
    if (!IsObject(items) || items.Length() = 0)
        return emptyText

    text := ""
    for _, item in items {
        if (text != "")
            text .= separator
        text .= item
    }
    return text
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
    if (ErrorLevel)
        return
    text := Clipboard
    StringReplace, text, text, \, /, All
    ClipboardWrite(text)
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

TextEditor_GetProviderCycle() {
    global TextEditorCustomPath

    providers := []
    ; providers.Push("Notepad")
    if IsNotepadsAvailable()
        providers.Push("Notepads")
    providers.Push("VSCode")
    if (Trim(TextEditorCustomPath) != "")
        providers.Push("Custom")
    return providers
}

TextEditor_GetProviderDisplayName(provider) {
    if (provider = "Notepads")
        return "Notepads"
    if (provider = "VSCode")
        return "VSCode"
    if (provider = "Custom")
        return "Custom"
    return "Notepad"
}

TextEditor_ToggleProvider() {
    global TextEditorProvider

    providers := TextEditor_GetProviderCycle()
    current := Trim(TextEditorProvider)
    nextIndex := 1

    for index, provider in providers {
        if (provider = current) {
            nextIndex := (index >= providers.Length()) ? 1 : index + 1
            break
        }
    }

    TextEditorProvider := providers[nextIndex]
    if IsFunc("SUI_SaveConfig")
        SUI_SaveConfig()

    ToolTip, % "Text Editor: " . TextEditor_GetProviderDisplayName(TextEditorProvider)
    SetTimer, CloseToolTip, -1500
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
        provider := "VSCode"

    if (provider = "Notepads" && !IsNotepadsAvailable())
        provider := "VSCode"

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

        OpenVSCodeNewWindow()
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

OpenWithNotePad(withFile = 1, editorType = 2) {
    global TextEditorProvider

    if (TextEditorProvider = "") {
        if (editorType = 1 && IsNotepadsAvailable())
            TextEditorProvider := "Notepads"
        else
            TextEditorProvider := "VSCode"
    }

    if (TextEditorProvider = "Notepads" && !IsNotepadsAvailable())
        TextEditorProvider := "VSCode"

    OpenTextEditor(withFile)
}

OpenVSCodeNewWindow() {
    launchCmd := "code -n"
    try {
        Run, %launchCmd%
    } catch {
        Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" -n
    }
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

    ; main.ahk の ^#9 と同じ全面配置へ揃える
    MoveWindowRatio("ahk_id " . TargetID, 0.000, 0.030, 1.000, 0.970)
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
