; ==========================================================
; ジェスチャ有効化アプリ
; ==========================================================
GroupAdd, GestureTargetGroup, ahk_group BrowserGroup
GroupAdd, GestureTargetGroup, ahk_group ExplorerGroup
GroupAdd, GestureTargetGroup, ahk_group EditorGroup
GroupAdd, GestureTargetGroup, ahk_group OfficeGroup
GroupAdd, GestureTargetGroup, ahk_exe pycharm64.exe

global MG_IsActive       := false    ; ジェスチャ認識中フラグ
global MG_CancelMenu     := false    ; 右クリックメニュー無効化フラグ
global MG_WheelUsed      := false    ; 右クリック中にホイール入力されたフラグ
global MG_DebugEnabled   := true
global MG_DebugLogDir    := A_ScriptDir . "\.claude"
global MG_DebugLogPath   := MG_DebugLogDir . "\mouse_gesture_debug.log"
global MG_DebugMaxBytes  := 262144
global cUIA              := new UIA_Interface()

MG_DebugInit() {
    global MG_DebugEnabled, MG_DebugLogDir

    if (!MG_DebugEnabled)
        return

    if !InStr(FileExist(MG_DebugLogDir), "D")
        FileCreateDir, %MG_DebugLogDir%

    MG_DebugLog("startup", "script=" . A_ScriptFullPath)
}

MG_DebugEnsureLogDir() {
    global MG_DebugLogDir

    if !InStr(FileExist(MG_DebugLogDir), "D")
        FileCreateDir, %MG_DebugLogDir%
}

MG_DebugRotateIfNeeded() {
    global MG_DebugLogPath, MG_DebugMaxBytes

    if !FileExist(MG_DebugLogPath)
        return

    FileGetSize, logSize, %MG_DebugLogPath%
    if (logSize < MG_DebugMaxBytes)
        return

    backupPath := RegExReplace(MG_DebugLogPath, "\.log$", ".old.log")
    FileDelete, %backupPath%
    FileMove, %MG_DebugLogPath%, %backupPath%, 1
}

MG_DebugSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

MG_DebugStateText() {
    global EnableGestures, MG_IsActive, MG_CancelMenu, MG_WheelUsed

    MouseGetPos, mx, my, mouseHwnd, mouseCtrl
    activeHwnd := WinExist("A")
    overTarget := MouseIsOverTarget() ? 1 : 0
    rButtonPhysical := GetKeyState("RButton", "P") ? 1 : 0
    rButtonLogical := GetKeyState("RButton") ? 1 : 0

    mouseTitle := ""
    mouseClass := ""
    mouseExe := ""
    activeTitle := ""
    activeClass := ""
    activeExe := ""

    if (mouseHwnd) {
        WinGetTitle, mouseTitle, ahk_id %mouseHwnd%
        WinGetClass, mouseClass, ahk_id %mouseHwnd%
        WinGet, mouseExe, ProcessName, ahk_id %mouseHwnd%
    }
    if (activeHwnd) {
        WinGetTitle, activeTitle, ahk_id %activeHwnd%
        WinGetClass, activeClass, ahk_id %activeHwnd%
        WinGet, activeExe, ProcessName, ahk_id %activeHwnd%
    }

    return "EnableGestures=" . EnableGestures
        . " MG_IsActive=" . MG_IsActive
        . " MG_CancelMenu=" . MG_CancelMenu
        . " MG_WheelUsed=" . MG_WheelUsed
        . " MouseTarget=" . overTarget
        . " RPhys=" . rButtonPhysical
        . " RLog=" . rButtonLogical
        . " Mouse=(" . mx . "," . my . ")"
        . " MouseHWND=" . mouseHwnd
        . " MouseExe=" . mouseExe
        . " MouseClass=" . mouseClass
        . " MouseTitle=" . MG_DebugSanitize(mouseTitle)
        . " ActiveHWND=" . activeHwnd
        . " ActiveExe=" . activeExe
        . " ActiveClass=" . activeClass
        . " ActiveTitle=" . MG_DebugSanitize(activeTitle)
        . " ThisHotkey=" . A_ThisHotkey
        . " PriorHotkey=" . A_PriorHotkey
        . " PriorMs=" . A_TimeSincePriorHotkey
}

MG_DebugLog(event, extra := "") {
    global MG_DebugEnabled, MG_DebugLogPath

    if (!MG_DebugEnabled)
        return

    MG_DebugEnsureLogDir()
    MG_DebugRotateIfNeeded()

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec
        . " event=" . event

    if (extra != "")
        line .= " extra=" . MG_DebugSanitize(extra)

    line .= " " . MG_DebugStateText()
    FileAppend, % line . "`n", %MG_DebugLogPath%, UTF-8
}

MG_DebugSnapshot(reason := "manual") {
    global MG_DebugLogPath

    MG_DebugLog("snapshot", "reason=" . reason)
    ToolTip, 右クリック状態を記録しました
    SetTimer, CloseToolTip, -1500
}

MG_DebugSnapshotMenu() {
    MG_DebugSnapshot("tray-menu")
}

MG_DebugOpenLog() {
    global MG_DebugLogPath

    MG_DebugEnsureLogDir()
    if !FileExist(MG_DebugLogPath)
        FileAppend,, %MG_DebugLogPath%, UTF-8

    Run, notepad.exe "%MG_DebugLogPath%"
}

MouseIsOverTarget() {
    MouseGetPos, , , WinID
    return WinExist("ahk_id " . WinID . " ahk_group GestureTargetGroup")
}

; ==========================================================
; 関数1: ジェスチャの認識（アクティブ化処理を削除）
; ==========================================================
MG_RecognizeGesture() {
    static Threshold := 30
    static Interval  := 10
    global MG_IsActive, MG_CancelMenu, MG_WheelUsed
    wheelLogged := false

    ; 既存の論理的な押しっぱなし状態をリセットするために物理的な状態をチェック
    if !GetKeyState("RButton", "P") {
        MG_IsActive := false
        MG_WheelUsed := false
        MG_DebugLog("recognize_exit_no_physical_button")
        return ""
    }

    CoordMode, Mouse, Screen
    MouseGetPos, startX, startY
    lastX := startX
    lastY := startY

    gestureStr := ""
    MG_IsActive := true
    MG_CancelMenu := false
    MG_WheelUsed := false
    MG_DebugLog("recognize_start", "startX=" . startX . " startY=" . startY)

    While GetKeyState("RButton", "P")
    {
        ; 処理の隙間を作り、他のホットキー(ホイール)の割り込みを許容する
        Sleep, 15

        ; 右クリック + ホイール中はジェスチャ認識を無効化する
        if (MG_WheelUsed) {
            gestureStr := ""
            ToolTip
            if (!wheelLogged) {
                MG_DebugLog("recognize_disabled_by_wheel")
                wheelLogged := true
            }
            continue
        }

        MouseGetPos, curX, curY
        distance := Sqrt((curX - lastX)**2 + (curY - lastY)**2)

        if (distance >= Threshold)
        {
            deltaX := curX - lastX
            deltaY := curY - lastY
            dir := MG_CalcDirection8(deltaX, deltaY)

            if (dir != "" && SubStr(gestureStr, 0) != dir) {
                gestureStr .= dir
                MG_DebugLog("gesture_dir_append", "dir=" . dir . " gesture=" . gestureStr)
            }

            lastX := curX
            lastY := curY
        }

        if (gestureStr != "") {
            ToolTip, % "ジェスチャ: " . gestureStr
        }
    }

    ToolTip
    MG_IsActive := false ; ここで確実にfalseに戻す
    if (MG_WheelUsed) {
        MG_WheelUsed := false
        MG_DebugLog("recognize_finish", "result=wheel-cancelled")
        return ""
    }
    MG_DebugLog("recognize_finish", "result=" . gestureStr)
    return gestureStr
}

; ==========================================================
; 関数2: アクションの実行（ここで初めてアクティブ化）
; ==========================================================
MG_ExecuteAction(gestureStr, targetID) {
    global MG_CancelMenu

    ; --- 共通: キャンセル処理 ---
    if (gestureStr = "") {
        if (MG_CancelMenu = false) {
            MG_DebugLog("execute_passthrough_right_click", "targetID=" . targetID)
            Click, Right
        } else {
            MG_DebugLog("execute_empty_gesture_cancelled", "targetID=" . targetID)
        }
        return
    }

    ; --- 共通: アクティブ化 ---
    MG_DebugLog("execute_gesture", "targetID=" . targetID . " gesture=" . gestureStr)
    MG_ActivateTargetWindow(targetID)

    ; --- アプリ別分岐 ---
    if (WinActive("ahk_group BrowserGroup"))
        return Map_Browser(gestureStr)
    else if (WinActive("ahk_group ExplorerGroup"))
        return Map_Explorer(gestureStr)
    else if (WinActive("ahk_group EditorGroup"))
        return Map_Editor(gestureStr)
    else if (WinActive("ahk_exe pycharm64.exe"))
        return Map_Pycharm(gestureStr)
    else
        return Map_Default(gestureStr)
}

; ==========================================================
; 関数3: スクロール時の処理 (PgUp/Dn ブースト版)
; ==========================================================
MG_ScrollAction(dir) {
    global MG_CancelMenu, MG_WheelUsed

    MG_WheelUsed := true
    MG_DebugLog("scroll_action", "dir=" . dir)
    MG_ActivateTargetWindow()
    if (dir = "Up")
        SendInput ^{Home}
    else
        SendInput ^{End}
    MG_CancelMenu := true
}

; ==========================================================
; 内部関数: 対象ウィンドウをアクティブにするヘルパー
; ==========================================================
MG_ActivateTargetWindow(targetID := 0) {
    if (targetID = 0) {
        MouseGetPos, , , targetID
    }
    if (!WinActive("ahk_id " . targetID)) {
        WinActivate, ahk_id %targetID%
        WinWaitActive, ahk_id %targetID%, , 0.2
    }
}

; ==========================================================
; 内部関数: 角度計算
; ==========================================================
MG_CalcDirection8(dx, dy) {
    rad := DllCall("msvcrt\atan2", "Double", dy, "Double", dx, "CDECL Double")
    deg := rad * (180 / 3.14159265358979)
    if (deg >= -22.5 && deg < 22.5)
        return "→"
    else if (deg >= 22.5 && deg < 67.5)
        return "↘"
    else if (deg >= 67.5 && deg < 112.5)
        return "↓"
    else if (deg >= 112.5 && deg < 157.5)
        return "↙"
    else if (deg >= 157.5 || deg < -157.5)
        return "←"
    else if (deg >= -157.5 && deg < -112.5)
        return "↖"
    else if (deg >= -112.5 && deg < -67.5)
        return "↑"
    else if (deg >= -67.5 && deg < -22.5)
        return "↗"
    return ""
}
