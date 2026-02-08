; ==========================================================
; 1. グループ定義 (ShortcutMap.ahkで使用するグループ名と合わせる)
; ==========================================================
SetTitleMatchMode, 2
GroupAdd, OfficeGroup, ahk_exe POWERPNT.EXE
GroupAdd, OfficeGroup, ahk_exe EXCEL.EXE
GroupAdd, EditorGroup, Notepads
GroupAdd, EditorGroup, ahk_exe Code.exe
GroupAdd, EditorGroup, ahk_exe notepad.exe
GroupAdd, EditorGroup, ahk_exe pycharm64.exe
GroupAdd, BrowserGroup, ahk_exe msedge.exe
GroupAdd, BrowserGroup, ahk_exe chrome.exe
GroupAdd, BrowserGroup, ahk_exe firefox.exe
GroupAdd, BrowserGroup, ahk_exe brave.exe
GroupAdd, ExplorerGroup, ahk_class CabinetWClass
GroupAdd, ExplorerGroup, ahk_class ExploreWClass

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

MoveWindow(targetTitle, x, y, w, h) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel) {
            return
        }
    }
    WinMove, %targetTitle%,, x, y, w, h
}

ShowMonitorInfo() {
    Output := ""

    ; モニターの総数を取得
    SysGet, MonCount, MonitorCount
    ; メインモニターの番号を取得
    SysGet, PrimMon, MonitorPrimary

    Output .= "検出されたモニター数: " . MonCount . "`n`n"

    Loop, %MonCount% {
        ; --- 1. モニター全体の解像度を取得 (Monitor) ---
        SysGet, Mon, Monitor, %A_Index%
        MonWidth  := MonRight - MonLeft
        MonHeight := MonBottom - MonTop

        ; --- 2. 作業領域を取得 (MonitorWorkArea) ---
        ; タスクバーを除いた、ウィンドウを最大化したときのサイズ
        SysGet, Work, MonitorWorkArea, %A_Index%
        WorkWidth  := WorkRight - WorkLeft
        WorkHeight := WorkBottom - WorkTop

        ; メインモニターかどうかの判定
        IsPrimary := (A_Index = PrimMon) ? " ★メインモニター" : ""

        ; --- 出力テキストの作成 ---
        Output .= "---------------------------------------`n"
        Output .= "モニター番号: " . A_Index . IsPrimary . "`n"
        Output .= "---------------------------------------`n"

        Output .= "[全体解像度]`n"
        Output .= "  サイズ: " . MonWidth . " x " . MonHeight . "`n"
        Output .= "  座標  : Left=" . MonLeft . ", Top=" . MonTop . ", Right=" . MonRight . ", Bottom=" . MonBottom . "`n`n"

        Output .= "[作業領域 (WorkArea)]`n"
        Output .= "  サイズ: " . WorkWidth . " x " . WorkHeight . "`n"
        Output .= "  座標  : Left=" . WorkLeft . ", Top=" . WorkTop . ", Right=" . WorkRight . ", Bottom=" . WorkBottom . "`n`n"
    }

    MsgBox, 0, モニター情報一覧, %Output%
}

; 補助関数: ウィンドウハンドルからモニターハンドルを取得（今回は簡易ロジックで代用したので未使用でも可）
GetMonitorHandleFromWindow(hwnd) {
    ; Windows API: MonitorFromWindow
    return DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2) ; 2=MONITOR_DEFAULTTONEAREST
}

; OpenMoveExplorer(path, x, y, w, h) {
;     Run, explorer.exe "%path%"
;     MoveWindow("ahk_class CabinetWClass", x, y, w, h)
; }

GetActiveWindowPos() {
    ; WinGetPos, x, y, w, h, A
    GetVisibleWindowPos(x,y, w, h, "A") ; "A"はアクティブウィンドウ

    WinGetTitle, title, A
    MsgBox, タイトル: %title%`nX=%x% Y=%y% W=%w% H=%h%
    ;Clipboard := "title:" . title . "X=" . x . " Y=" . y . " W=" . w . " H=" . h
}

GetVisibleWindowPos(ByRef X, ByRef Y, ByRef Width, ByRef Height, WinTitle := "A") {
    ; 対象ウィンドウのハンドル(ID)を取得
    WinGet, hwnd, ID, %WinTitle%
    if !hwnd
        return

    ; RECT構造体のためのメモリ確保 (4バイト整数 x 4 = 16バイト)
    VarSetCapacity(rect, 16, 0)

    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    ; 成功すると 0 (S_OK) が返る
    hr := DllCall("dwmapi\DwmGetWindowAttribute"
        , "Ptr",  hwnd
        , "UInt", 9
        , "Ptr",  &rect
        , "UInt", 16)

    if (hr = 0) {
        ; --- 成功時: DWMから取得した「見た目の座標」を使用 ---
        X := NumGet(rect, 0, "Int")      ; Left
        Y := NumGet(rect, 4, "Int")      ; Top
        R := NumGet(rect, 8, "Int")      ; Right
        B := NumGet(rect, 12, "Int")     ; Bottom

        Width  := R - X
        Height := B - Y
    } else {
        ; --- 失敗時（DWM非対応など）: 通常のWinGetPosで代用 ---
        WinGetPos, X, Y, Width, Height, ahk_id %hwnd%
    }
}

; OpenVSCode() {
;     if WinExist("ahk_exe Code.exe")
;         WinActivate, %TargetID%
;     else
;     {
;         ; 開いていない場合、現在のスクリプトの場所(%A_ScriptDir%)をVSCodeで開く
;         ; ※ インストール時にPATHを通していれば "code" だけで起動
;         try {
;             Run, code "%A_ScriptDir%"
;         } catch {
;             ; PATHが通っていない場合のフォールバック（一般的なインストールパス）
;             Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" "%A_ScriptDir%"
;         }
;     }
;     MoveWindow(TargetID, 1930, 450, 1550, 1600)
; }

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
