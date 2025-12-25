global BaseSpeed := 2
global MaxSpeed := 50
global Acceleration := 1.25
global TimerInterval := 10
global CurrentSpeed := BaseSpeed

; --- 1. 開始関数 ---
StartCursorMove() {
    TimerFn := Func("MoveCursor")

    ; 速度リセット
    CurrentSpeed := BaseSpeed

    ; タイマー開始
    SetTimer, %TimerFn%, %TimerInterval%
}

; --- 2. 移動ループ関数 ---
MoveCursor() {
    global BaseSpeed, MaxSpeed, Acceleration, CurrentSpeed

    ; 【重要】モディファイアキー(vk1D)が離されたら停止
    if !GetKeyState("vk1D", "P") {
        StopCursor()
        return
    }

    xMove := 0
    yMove := 0

    ; WASDの入力状態をチェック
    if GetKeyState("w", "P")
        yMove -= 1
    if GetKeyState("s", "P")
        yMove += 1
    if GetKeyState("a", "P")
        xMove -= 1
    if GetKeyState("d", "P")
        xMove += 1

    ; 移動キーがすべて離されたら停止
    if (xMove = 0 && yMove = 0) {
        StopCursor()
        return
    }

    ; 加速計算
    if (CurrentSpeed < MaxSpeed)
        CurrentSpeed *= Acceleration
    if (CurrentSpeed > MaxSpeed)
        CurrentSpeed := MaxSpeed

    ; 移動量の適用
    MoveX := Round(xMove * CurrentSpeed)
    MoveY := Round(yMove * CurrentSpeed)

    MouseMove, %MoveX%, %MoveY%, 0, R
}

; --- 3. 停止関数 ---
StopCursor() {
    global BaseSpeed, CurrentSpeed

    TimerFn := Func("MoveCursor")
    SetTimer, %TimerFn%, Off

    CurrentSpeed := BaseSpeed
}