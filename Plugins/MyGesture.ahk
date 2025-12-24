; ==========================================================
; ジェスチャ有効化アプリ
; ==========================================================
GroupAdd, GestureTargetGroup, ahk_group BrowserGroup
GroupAdd, GestureTargetGroup, ahk_group ExplorerGroup
GroupAdd, GestureTargetGroup, ahk_group EditorGroup

global MG_IsActive := false     ; ジェスチャ認識中フラグ
global MG_CancelMenu := false   ; 右クリックメニュー無効化フラグ

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

    CoordMode, Mouse, Screen
    MouseGetPos, startX, startY

    lastX := startX
    lastY := startY

    gestureStr := ""
    MG_IsActive := true
    MG_CancelMenu := false

    While GetKeyState("RButton", "P")
    {
        MouseGetPos, curX, curY
        distance := Sqrt((curX - lastX)**2 + (curY - lastY)**2)

        if (distance >= Threshold)
        {
            deltaX := curX - lastX
            deltaY := curY - lastY
            dir := MG_CalcDirection8(deltaX, deltaY)

            if (dir != "" && SubStr(gestureStr, 0) != dir)
                gestureStr .= dir

            lastX := curX
            lastY := curY
        }

        ToolTip, % "ジェスチャ: " . gestureStr
        Sleep, %Interval%
    }

    ToolTip
    MG_IsActive := false

    return gestureStr
}

; ==========================================================
; 関数2: アクションの実行（ここで初めてアクティブ化）
; ==========================================================
MG_ExecuteAction(gestureStr, targetID) {
    ; --- 共通: キャンセル処理 ---
    if (gestureStr = "") {
        if (MG_CancelMenu = false)
            Click, Right
        return
    }

    ; --- 共通: アクティブ化 ---
    MG_ActivateTargetWindow(targetID)

    ; --- アプリ別分岐 ---
    if (WinActive("ahk_group BrowserGroup"))
        return Map_Browser(gestureStr)
    else if (WinActive("ahk_group ExplorerGroup"))
        return Map_Explorer(gestureStr)
    else if (WinActive("ahk_group EditorGroup"))
        return Map_Editor(gestureStr)
    else
        return Map_Default(gestureStr)
}

; ==========================================================
; 関数3: スクロール時の処理 (PgUp/Dn ブースト版)
; ==========================================================
MG_ScrollAction(dir) {
    MG_ActivateTargetWindow()
    boost := 10

    if (dir = "Up")
        Send, {PgUp %boost%}   ; PgUpを5回連打
    else
        Send, {PgDn %boost%}   ; PgDnを5回連打

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