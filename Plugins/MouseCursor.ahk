global CursorConfig := {BaseSpeed: 2.0
    , MaxSpeed: 50.0
    , Acceleration: 1.25
    , TimerInterval: 10
    , IsRunning: false
    , CurrentSpeed: 2.0
    , Directions: {Up: 0, Left: 0, Down: 0, Right: 0}}

global CursorGridConfig := {DefaultCols: 4, DefaultRows: 2}
global CursorHotkeyConfig := ""
global CursorHotkeyState := {DownMap: {}, UpMap: {}, GridMap: {}, ModifierUp: ""}

Cursor_RegisterHotkeys(config) {
    global CursorHotkeyConfig, CursorHotkeyState

    CursorHotkeyConfig := config
    CursorHotkeyState := {DownMap: {}, UpMap: {}, GridMap: {}, ModifierUp: "*" . config.Modifier . " Up"}

    for keyName, direction in config.Move {
        downHotkey := config.Modifier . " & " . keyName
        upHotkey := downHotkey . " Up"
        CursorHotkeyState.DownMap[downHotkey] := direction
        CursorHotkeyState.UpMap[upHotkey] := direction

        Hotkey, If, Cursor_MoveHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyDown, On

        Hotkey, If, Cursor_Enabled()
        Hotkey, %upHotkey%, Cursor_MoveHotkeyUp, On
    }

    for keyName, moveSpec in config.Grid {
        downHotkey := config.Modifier . " & " . keyName
        CursorHotkeyState.GridMap[downHotkey] := moveSpec

        Hotkey, If, Cursor_GridHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyGrid, On
    }

    Hotkey, If, Cursor_Enabled()
    Hotkey, % CursorHotkeyState.ModifierUp, Cursor_MoveHotkeyModifierUp, On
    Hotkey, If
}

Cursor_Enabled() {
    global EnableMouseEmu
    return EnableMouseEmu
}

Cursor_MoveHotkeyEnabled() {
    return Cursor_Enabled() && !GetKeyState("Ctrl", "P")
}

Cursor_GridHotkeyEnabled() {
    return Cursor_Enabled() && GetKeyState("Ctrl", "P")
}

Cursor_MoveHotkeyDown() {
    global CursorHotkeyState

    direction := CursorHotkeyState.DownMap[A_ThisHotkey]
    if (direction != "")
        Cursor_KeyDown(direction)
}

Cursor_MoveHotkeyUp() {
    global CursorHotkeyState

    direction := CursorHotkeyState.UpMap[A_ThisHotkey]
    if (direction != "")
        Cursor_KeyUp(direction)
}

Cursor_MoveHotkeyGrid() {
    global CursorHotkeyState

    direction := CursorHotkeyState.GridMap[A_ThisHotkey]
    if (direction != "")
        Cursor_GridMoveByDirection(direction)
}

Cursor_MoveHotkeyModifierUp() {
    Cursor_StopContinuous()
}

Cursor_StartContinuous() {
    global CursorConfig
    static TimerFn := Func("Cursor_MoveContinuous")

    ; Avoid resetting speed on key-repeat re-entry.
    if (CursorConfig.IsRunning)
        return

    CursorConfig.CurrentSpeed := CursorConfig.BaseSpeed
    CursorConfig.IsRunning := true
    SetTimer, %TimerFn%, % CursorConfig.TimerInterval
}

Cursor_MoveContinuous() {
    global CursorConfig

    move := Cursor_GetMoveVector()
    if (move.x = 0 && move.y = 0) {
        Cursor_StopContinuous()
        return
    }

    CursorConfig.CurrentSpeed := Cursor_GetNextSpeed(CursorConfig.CurrentSpeed)
    moveX := Round(move.x * CursorConfig.CurrentSpeed)
    moveY := Round(move.y * CursorConfig.CurrentSpeed)
    MouseMove, %moveX%, %moveY%, 0, R
}

Cursor_StopContinuous() {
    global CursorConfig
    static TimerFn := Func("Cursor_MoveContinuous")

    SetTimer, %TimerFn%, Off
    CursorConfig.IsRunning := false
    CursorConfig.CurrentSpeed := CursorConfig.BaseSpeed
    Cursor_ClearDirections()
}

Cursor_KeyDown(direction) {
    global CursorConfig

    if !CursorConfig.Directions.HasKey(direction)
        return

    CursorConfig.Directions[direction] := 1
    Cursor_StartContinuous()
}

Cursor_KeyUp(direction) {
    global CursorConfig

    if !CursorConfig.Directions.HasKey(direction)
        return

    CursorConfig.Directions[direction] := 0
    if !Cursor_HasActiveDirection()
        Cursor_StopContinuous()
}

Cursor_HasActiveDirection() {
    global CursorConfig

    for _, isActive in CursorConfig.Directions {
        if (isActive)
            return true
    }
    return false
}

Cursor_ClearDirections() {
    global CursorConfig

    for direction, _ in CursorConfig.Directions
        CursorConfig.Directions[direction] := 0
}

Cursor_GetMoveVector() {
    global CursorConfig

    xMove := 0
    yMove := 0

    if (CursorConfig.Directions.Up)
        yMove -= 1
    if (CursorConfig.Directions.Down)
        yMove += 1
    if (CursorConfig.Directions.Left)
        xMove -= 1
    if (CursorConfig.Directions.Right)
        xMove += 1

    return {x: xMove, y: yMove}
}

Cursor_GetNextSpeed(currentSpeed) {
    global CursorConfig

    if (currentSpeed < CursorConfig.BaseSpeed)
        currentSpeed := CursorConfig.BaseSpeed
    if (currentSpeed >= CursorConfig.MaxSpeed)
        return CursorConfig.MaxSpeed

    nextSpeed := currentSpeed * CursorConfig.Acceleration
    if (nextSpeed > CursorConfig.MaxSpeed)
        nextSpeed := CursorConfig.MaxSpeed
    return nextSpeed
}

Cursor_GridMove(dx, dy) {
    state := Cursor_GetGridState()
    if !IsObject(state)
        return

    nextX := state.gx + dx
    nextY := state.gy + dy

    if (nextX < 0)
        nextX := 0
    else if (nextX >= state.cols)
        nextX := state.cols - 1

    if (nextY < 0)
        nextY := 0
    else if (nextY >= state.rows)
        nextY := state.rows - 1

    Cursor_SetGridPosition(state, nextX, nextY)
}

Cursor_GridMoveByDirection(direction) {
    if (direction = "Up")
        Cursor_GridMove(0, -1)
    else if (direction = "Down")
        Cursor_GridMove(0, 1)
    else if (direction = "Left")
        Cursor_GridMove(-1, 0)
    else if (direction = "Right")
        Cursor_GridMove(1, 0)
}

Cursor_GetGridState() {
    global GRID_COLS, GRID_ROWS, CursorGridConfig

    MouseGetPos, mx, my
    GetMonitorWorkAreaFromPoint(mx, my, monLeft, monTop, monWidth, monHeight)
    if (monWidth <= 0 || monHeight <= 0)
        return ""

    cols := GRID_COLS ? GRID_COLS : CursorGridConfig.DefaultCols
    rows := GRID_ROWS ? GRID_ROWS : CursorGridConfig.DefaultRows
    if (cols < 1)
        cols := 1
    if (rows < 1)
        rows := 1

    unitW := monWidth / cols
    unitH := monHeight / rows
    gx := Floor((mx - monLeft) / unitW)
    gy := Floor((my - monTop) / unitH)

    if (gx < 0)
        gx := 0
    else if (gx >= cols)
        gx := cols - 1

    if (gy < 0)
        gy := 0
    else if (gy >= rows)
        gy := rows - 1

    return {gx: gx, gy: gy, cols: cols, rows: rows
        , monLeft: monLeft, monTop: monTop, unitW: unitW, unitH: unitH}
}

Cursor_SetGridPosition(state, gx, gy) {
    targetX := state.monLeft + ((gx + 0.5) * state.unitW)
    targetY := state.monTop + ((gy + 0.5) * state.unitH)
    MouseMove, % Round(targetX), % Round(targetY), 0
}
