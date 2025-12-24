; ==========================================================
; 1. グループ定義 (ShortcutMap.ahkで使用するグループ名と合わせる)
; ==========================================================
SetTitleMatchMode, 2
GroupAdd, EditorGroup, Notepads
GroupAdd, EditorGroup, ahk_exe Code.exe
GroupAdd, EditorGroup, ahk_exe notepad.exe
GroupAdd, BrowserGroup, ahk_exe msedge.exe
GroupAdd, BrowserGroup, ahk_exe chrome.exe
GroupAdd, BrowserGroup, ahk_exe firefox.exe
GroupAdd, BrowserGroup, ahk_exe brave.exe
GroupAdd, ExplorerGroup, ahk_class CabinetWClass
GroupAdd, ExplorerGroup, ahk_class ExploreWClass

; ==========================================================
; 関数
; ==========================================================
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

OpenWithMspaint() {
    KeyWait, Ctrl
    KeyWait, Alt
    Clipboard := ""
    Send, +^c
    ClipWait, 2
    Run, mspaint.exe %Clipboard%
}

OpenWithNotePad() {
    KeyWait, Ctrl
    KeyWait, Alt
    Clipboard := ""
    Send, +^c
    ClipWait, 2
    ;Run, %LOCALAPPDATA%\Microsoft\WindowsApps\Notepads.exe %Clipboard%
    ;Run, Notepads.exe %Clipboard%
    Run, Notepads %Clipboard%
    ;Run, notepad.exe %Clipboard%
    ;Run, shell:AppsFolder\9nhl4nsc67wm!App "%Clipboard%"
}

MoveWindow(targetTitle, x, y, w, h) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel) {
            return
        }
    }
    WinMove, %targetTitle%,, x, y, w, h
}

OpenMoveExplorer(path, x, y, w, h) {
    Run, explorer.exe "%path%"
    MoveWindow("ahk_class CabinetWClass", x, y, w, h)
}

GetActiveWindowPos() {
    WinGetPos, x, y, w, h, A
    WinGetTitle, title, A
    MsgBox, タイトル: %title%`nX=%x% Y=%y% W=%w% H=%h%
    ;Clipboard := "title:" . title . "X=" . x . " Y=" . y . " W=" . w . " H=" . h
}

OpenVSCode() {
    if WinExist("ahk_exe Code.exe")
        WinActivate, %TargetID%
    else
    {
        ; 開いていない場合、現在のスクリプトの場所(%A_ScriptDir%)をVSCodeで開く
        ; ※ インストール時にPATHを通していれば "code" だけで起動
        try {
            Run, code "%A_ScriptDir%"
        } catch {
            ; PATHが通っていない場合のフォールバック（一般的なインストールパス）
            Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" "%A_ScriptDir%"
        }
    }
    MoveWindow(TargetID, 1930, 450, 1550, 1600)
}

GetApplicationName() {
    WinGet, processName, ProcessName, A
    MsgBox, このアプリのexe名は: %processName%`n(クリップボードにコピーしました)
    ;Clipboard := processName
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