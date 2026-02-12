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

OpenWithNotePad(withFile = 1, editorType = 1) {
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

    if (editorType = 1) {
        Run, Notepads %TargetArgs%
    } else {
        Run, notepad.exe %TargetArgs%
    }
}

; アプリケーション起動ヘルパー
OpenMoveExplorer(path, xr, yr, wr, hr) {
    Run, explorer.exe "%path%"
    WinWaitActive, ahk_class CabinetWClass, , 3
    MoveWindowRatio("A", xr, yr, wr, hr)
}

OpenVSCode() {
    TargetID := WinExist("ahk_exe Code.exe")
    if TargetID {
        WinActivate, ahk_id %TargetID%
    } else {
        try {
            Run, code "%A_ScriptDir%"
        } catch {
            Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" "%A_ScriptDir%"
        }
        WinWaitActive, ahk_exe Code.exe, , 5
        TargetID := WinExist("A")
    }
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
