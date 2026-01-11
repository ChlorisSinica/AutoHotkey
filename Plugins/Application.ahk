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

; ==============================================================================
; 関数: 現在のモニターを基準に比率で移動
; ==============================================================================
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

MoveWindowRatio(targetTitle, xRatio, yRatio, wRatio, hRatio) {
    ; 対象ウィンドウのハンドルを取得
    WinGet, hwnd, ID, %targetTitle%
    if (!hwnd)
        return

    ; ウィンドウが最小化されていたら戻す
    WinRestore, ahk_id %hwnd%

    ; ウィンドウが現在あるモニターの情報を取得
    hMon := GetMonitorHandleFromWindow(hwnd)

    ; モニターの「作業領域（タスクバーを除いた範囲）」を取得
    ; VarSetCapacity等を使わず、AHKの標準コマンド SysGet を使用するための準備
    SysGet, monCount, MonitorCount

    ; モニターハンドルからモニター番号を特定する（AHK v1だと少し泥臭いループが必要）
    targetMon := 1
    Loop, %monCount% {
        SysGet, hTemp, MonitorName, %A_Index%
        ; ハンドル比較が厳密には難しいので、ここでは
        ; 「ウィンドウの中心点がどのモニターの範囲内にあるか」で判定するロジックを採用
        SysGet, m, Monitor, %A_Index%

        WinGetPos, wx, wy, ww, wh, ahk_id %hwnd%
        cx := wx + (ww / 2)
        cy := wy + (wh / 2)

        if (cx >= mLeft && cx <= mRight && cy >= mTop && cy <= mBottom) {
            targetMon := A_Index
            break
        }
    }

    ; 特定したモニターの作業領域(WorkArea)を取得
    ; mLeft, mTop, mRight, mBottom という変数が作成される
    SysGet, m, MonitorWorkArea, %targetMon%

    monWidth  := mRight - mLeft
    monHeight := mBottom - mTop

    ; 比率からピクセルを計算
    newW := monWidth  * wRatio
    newH := monHeight * hRatio
    newX := mLeft + (monWidth  * xRatio)
    newY := mTop  + (monHeight * yRatio)

    ; 移動実行
    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %newW%, %newH%
}

; 補助関数: ウィンドウハンドルからモニターハンドルを取得（今回は簡易ロジックで代用したので未使用でも可）
GetMonitorHandleFromWindow(hwnd) {
    ; Windows API: MonitorFromWindow
    return DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2) ; 2=MONITOR_DEFAULTTONEAREST
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
