; ==============================================================================
; Keyboard mouse helpers
; - Hold movement keys to move the cursor continuously
; - Use the grid hotkeys to jump between monitor grid intersections
; - Grid jumps can cross monitors and keep edge positions slightly inset
; ==============================================================================

global CursorConfig := {BaseSpeed: 2.0
    , MaxSpeed: 50.0
    , Acceleration: 1.25
    , TimerInterval: 10
    , IsRunning: false
    , CurrentSpeed: 2.0
    , Directions: {Up: 0, Left: 0, Down: 0, Right: 0}}

global CursorGridConfig := {DefaultCols: 4, DefaultRows: 4, EdgeInset: 6}
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

; AHK v1 requires Hotkey, If expressions to already exist as #If directives.
#If Cursor_MoveHotkeyEnabled()
#If
#If Cursor_Enabled()
#If
#If Cursor_GridHotkeyEnabled()
#If

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

    targetState := state
    nextX := state.gx + dx
    nextY := state.gy + dy

    if (nextX < 0) {
        candidateState := Cursor_GetAdjacentGridState(state, "Left")
        if (IsObject(candidateState)) {
            targetState := candidateState
            nextX := targetState.cols
        } else {
            nextX := 0
        }
    } else if (nextX > state.cols) {
        candidateState := Cursor_GetAdjacentGridState(state, "Right")
        if (IsObject(candidateState)) {
            targetState := candidateState
            nextX := 0
        } else {
            nextX := state.cols
        }
    }

    if (nextY < 0) {
        candidateState := Cursor_GetAdjacentGridState(state, "Up")
        if (IsObject(candidateState)) {
            targetState := candidateState
            nextY := targetState.rows
        } else {
            nextY := 0
        }
    } else if (nextY > state.rows) {
        candidateState := Cursor_GetAdjacentGridState(state, "Down")
        if (IsObject(candidateState)) {
            targetState := candidateState
            nextY := 0
        } else {
            nextY := state.rows
        }
    }

    if (nextX < 0)
        nextX := 0
    else if (nextX > targetState.cols)
        nextX := targetState.cols

    if (nextY < 0)
        nextY := 0
    else if (nextY > targetState.rows)
        nextY := targetState.rows

    Cursor_SetGridPosition(targetState, nextX, nextY)
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
    MouseGetPos, mx, my
    monitor := GetMonitorWorkAreaInfoFromPoint(mx, my)
    if !IsObject(monitor)
        return ""

    state := Cursor_CreateGridState(monitor)
    state.gx := Cursor_GetGridAnchorIndex(mx, monitor.Left, monitor.Width, state.cols)
    state.gy := Cursor_GetGridAnchorIndex(my, monitor.Top, monitor.Height, state.rows)
    return state
}

Cursor_SetGridPosition(state, gx, gy) {
    xInset := Cursor_GetGridEdgeInset(state.monRight - state.monLeft)
    yInset := Cursor_GetGridEdgeInset(state.monBottom - state.monTop)

    if (gx <= 0)
        targetX := state.monLeft + xInset
    else if (gx >= state.cols)
        targetX := state.monRight - xInset
    else
        targetX := state.monLeft + (gx * state.unitW)

    if (gy <= 0)
        targetY := state.monTop + yInset
    else if (gy >= state.rows)
        targetY := state.monBottom - yInset
    else
        targetY := state.monTop + (gy * state.unitH)

    MouseMove, % Round(targetX), % Round(targetY), 0
}

Cursor_CreateGridState(monitor) {
    global GRID_COLS, GRID_ROWS, CursorGridConfig

    cols := GRID_COLS ? GRID_COLS : CursorGridConfig.DefaultCols
    rows := GRID_ROWS ? GRID_ROWS : CursorGridConfig.DefaultRows
    if (cols < 1)
        cols := 1
    if (rows < 1)
        rows := 1

    return {Monitor: monitor, cols: cols, rows: rows
        , monLeft: monitor.Left, monTop: monitor.Top, monRight: monitor.Right - 1, monBottom: monitor.Bottom - 1
        , unitW: monitor.Width / cols, unitH: monitor.Height / rows}
}

Cursor_GetGridAnchorIndex(position, start, size, divisions) {
    if (size <= 0)
        return 0

    index := Round(((position - start) / size) * divisions)
    if (index < 0)
        index := 0
    else if (index > divisions)
        index := divisions
    return index
}

Cursor_GetAdjacentGridState(state, direction) {
    targetMonitor := GetAdjacentMonitorWorkAreaInfo(state.Monitor, direction)
    if !IsObject(targetMonitor)
        return ""

    return Cursor_CreateGridState(targetMonitor)
}

Cursor_GetGridEdgeInset(maxOffset) {
    global CursorGridConfig

    inset := CursorGridConfig.EdgeInset
    if (inset < 0)
        inset := 0
    if (inset > maxOffset)
        inset := maxOffset
    return inset
}
