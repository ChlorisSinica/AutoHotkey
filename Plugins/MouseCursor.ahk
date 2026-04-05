; ==============================================================================
; Keyboard mouse helpers
; - Hold movement keys to move the cursor continuously
; - Use the grid hotkeys to jump between monitor grid intersections
; - Grid jumps can cross monitors and keep edge positions slightly inset
; ==============================================================================

global CursorConfig        := Cursor_CreateConfig()
global CursorGridConfig    := Cursor_CreateGridConfig()
global CursorHotkeyConfig  := ""
global CursorHotkeyState   := Cursor_CreateHotkeyState()
global CursorClickHeld_Left  := false
global CursorClickHeld_Right := false

Cursor_CreateConfig() {
    return {BaseSpeed: 2.0
        , MaxSpeed: 50.0
        , Acceleration: 1.25
        , TimerInterval: 10
        , JumpDistance: 100
        , IsRunning: false
        , CurrentSpeed: 2.0
        , Directions: {Up: 0, Left: 0, Down: 0, Right: 0}}
}

Cursor_CreateGridConfig() {
    return {DefaultCols: 4, DefaultRows: 4, EdgeInset: 6}
}

Cursor_CreateHotkeyState() {
    return {DownMap: {}, UpMap: {}, GridMap: {}, JumpMap: {}, EdgeMap: {}
        , ClickDownMap: {}, ClickUpMap: {}, ClickSingleMap: {}, ModifierUp: ""}
}

Cursor_RegisterHotkeys(config) {
    global CursorHotkeyConfig, CursorHotkeyState

    CursorHotkeyConfig := config
    CursorHotkeyState := {DownMap: {}, UpMap: {}, GridMap: {}, JumpMap: {}, EdgeMap: {}
        , ClickDownMap: {}, ClickUpMap: {}, ClickSingleMap: {}, ModifierUp: "*" . config.Modifier . " Up"}

    for keyName, direction in config.Move {
        downHotkey := config.Modifier . " & " . keyName
        upHotkey := downHotkey . " Up"
        CursorHotkeyState.DownMap[downHotkey] := direction
        CursorHotkeyState.UpMap[upHotkey] := direction
        CursorHotkeyState.JumpMap[downHotkey] := direction
        CursorHotkeyState.EdgeMap[downHotkey] := direction

        Hotkey, If, Cursor_MoveHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyDown, On

        Hotkey, If, Cursor_IsMouseMode()
        Hotkey, %upHotkey%, Cursor_MoveHotkeyUp, On

        Hotkey, If, Cursor_JumpHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyJump, On

        Hotkey, If, Cursor_EdgeHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyEdge, On
    }

    for keyName, moveSpec in config.Grid {
        downHotkey := config.Modifier . " & " . keyName
        CursorHotkeyState.GridMap[downHotkey] := moveSpec

        Hotkey, If, Cursor_GridHotkeyEnabled()
        Hotkey, %downHotkey%, Cursor_MoveHotkeyGrid, On
    }

    for keyName, buttonName in config.ClickHold {
        downHotkey := config.Modifier . " & " . keyName
        upHotkey := downHotkey . " Up"
        CursorHotkeyState.ClickDownMap[downHotkey] := buttonName
        CursorHotkeyState.ClickUpMap[upHotkey] := buttonName

        Hotkey, If, Cursor_IsMouseMode()
        Hotkey, %downHotkey%, Cursor_ClickHotkeyDown, On
        Hotkey, %upHotkey%, Cursor_ClickHotkeyUp, On
    }

    for keyName, buttonName in config.ClickSingle {
        downHotkey := config.Modifier . " & " . keyName
        CursorHotkeyState.ClickSingleMap[downHotkey] := buttonName

        Hotkey, If, Cursor_IsMouseMode()
        Hotkey, %downHotkey%, Cursor_ClickHotkeySingle, On
    }

    Hotkey, If, Cursor_IsMouseMode()
    Hotkey, % CursorHotkeyState.ModifierUp, Cursor_MoveHotkeyModifierUp, On
    Hotkey, If
}

Cursor_CanUseKeyboardMode() {
    global EnableNavLayer
    return EnableNavLayer ? 1 : 0
}

Cursor_CanUseMouseMode() {
    global EnableMouseEmu
    return EnableMouseEmu ? 1 : 0
}

Cursor_CanToggleModes() {
    return Cursor_CanUseKeyboardMode() && Cursor_CanUseMouseMode()
}

Cursor_IsKeyboardMode() {
    global EnableMouseCursorMode
    return Cursor_CanUseKeyboardMode() && !(EnableMouseCursorMode ? 1 : 0)
}

Cursor_IsMouseMode() {
    global EnableMouseCursorMode
    return Cursor_CanUseMouseMode() && (EnableMouseCursorMode ? 1 : 0)
}

Cursor_Enabled() {
    return Cursor_IsMouseMode()
}

Cursor_MoveHotkeyEnabled() {
    return Cursor_IsMouseMode() && !GetKeyState("Ctrl", "P") && !GetKeyState("Alt", "P")
}

Cursor_JumpHotkeyEnabled() {
    return Cursor_IsMouseMode() && GetKeyState("Ctrl", "P") && !GetKeyState("Alt", "P")
}

Cursor_GridHotkeyEnabled() {
    return Cursor_IsMouseMode() && !GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P")
}

Cursor_EdgeHotkeyEnabled() {
    return Cursor_IsMouseMode() && GetKeyState("Ctrl", "P") && GetKeyState("Alt", "P")
}

Cursor_LogModeChange(reason, prevMode, nextMode, forceCleanup := false, changed := true) {
    if !IsFunc("SUI_DebugLog")
        return

    detail := "reason=" . (reason != "" ? reason : "none")
        . " prev=" . prevMode
        . " next=" . nextMode
        . " changed=" . (changed ? 1 : 0)
        . " cleanup=" . (forceCleanup ? 1 : 0)
    SUI_DebugLog("cursor_mode", detail)
}

Cursor_SetMode(targetMode, reason := "", showToolTip := false, forceCleanup := false) {
    global EnableMouseCursorMode

    prevMode := EnableMouseCursorMode ? 1 : 0
    nextMode := targetMode ? 1 : 0
    changed := (prevMode != nextMode)

    if (changed || forceCleanup)
        Cursor_StopContinuous()
    if ((prevMode = 1 && nextMode = 0) || (forceCleanup && !Cursor_CanUseMouseMode()))
        Cursor_ReleaseHeldClicks()

    if (!changed) {
        Cursor_LogModeChange(reason, prevMode, nextMode, forceCleanup, false)
        return false
    }

    EnableMouseCursorMode := nextMode
    Cursor_LogModeChange(reason, prevMode, nextMode, forceCleanup, true)

    if (showToolTip) {
        if (nextMode)
            ToolTip, Mouse Cursor
        else
            ToolTip, Keyboard Cursor
        SetTimer, CloseToolTip, -1500
    }
    return true
}

Cursor_ResolveModeForFlags(reason := "") {
    if !Cursor_CanUseMouseMode()
        return Cursor_SetMode(0, reason, false, true)
    if !Cursor_CanUseKeyboardMode()
        return Cursor_SetMode(1, reason, false)
    return false
}

ToggleMouseCursorMode() {
    global EnableMouseCursorMode

    ; Settings GUI が開いている場合、タイマー遅延で変数が古い可能性があるため
    ; 保留中のチェックボックス変更を即座に反映する
    if IsFunc("SUI_FlushPendingChange")
        SUI_FlushPendingChange("cursor_toggle")
    if !Cursor_CanToggleModes()
        return

    Cursor_SetMode(!EnableMouseCursorMode, "toggle", true)
}

ResetMouseCursorModeIfNeeded() {
    return Cursor_ResolveModeForFlags("legacy_reset")
}

Cursor_SetHeldClick(button, isDown) {
    global CursorClickHeld_Left, CursorClickHeld_Right

    if (button = "Left") {
        if (isDown) {
            if (!CursorClickHeld_Left) {
                CursorClickHeld_Left := true
                Click, Down
            }
        } else if (CursorClickHeld_Left) {
            CursorClickHeld_Left := false
            Click, Up
        }
        return
    }

    if (button = "Right") {
        if (isDown) {
            if (!CursorClickHeld_Right) {
                CursorClickHeld_Right := true
                Click, Right, Down
            }
        } else if (CursorClickHeld_Right) {
            CursorClickHeld_Right := false
            Click, Right, Up
        }
    }
}

Cursor_LeftClickDown() {
    Cursor_SetHeldClick("Left", true)
}

Cursor_LeftClickUp() {
    Cursor_SetHeldClick("Left", false)
}

Cursor_MiddleClick() {
    Click, Middle
}

Cursor_RightClickDown() {
    Cursor_SetHeldClick("Right", true)
}

Cursor_RightClickUp() {
    Cursor_SetHeldClick("Right", false)
}

Cursor_ReleaseHeldClicks() {
    global CursorClickHeld_Left, CursorClickHeld_Right
    if (CursorClickHeld_Left) {
        Click, Up
        CursorClickHeld_Left := false
    }
    if (CursorClickHeld_Right) {
        Click, Right, Up
        CursorClickHeld_Right := false
    }
}

; AHK v1 requires Hotkey, If expressions to already exist as #If directives.
#If Cursor_CanUseKeyboardMode()
#If
#If Cursor_IsKeyboardMode()
#If
#If Cursor_CanToggleModes()
#If
#If Cursor_IsMouseMode()
#If
#If Cursor_MoveHotkeyEnabled()
#If
#If Cursor_GridHotkeyEnabled()
#If
#If Cursor_JumpHotkeyEnabled()
#If
#If Cursor_EdgeHotkeyEnabled()
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

Cursor_ClickHotkeyDown() {
    global CursorHotkeyState

    button := CursorHotkeyState.ClickDownMap[A_ThisHotkey]
    if (button = "Left")
        Cursor_LeftClickDown()
    else if (button = "Right")
        Cursor_RightClickDown()
}

Cursor_ClickHotkeyUp() {
    global CursorHotkeyState

    button := CursorHotkeyState.ClickUpMap[A_ThisHotkey]
    if (button = "Left")
        Cursor_LeftClickUp()
    else if (button = "Right")
        Cursor_RightClickUp()
}

Cursor_ClickHotkeySingle() {
    global CursorHotkeyState

    button := CursorHotkeyState.ClickSingleMap[A_ThisHotkey]
    if (button = "Middle")
        Cursor_MiddleClick()
}

Cursor_MoveHotkeyJump() {
    global CursorHotkeyState, CursorConfig

    direction := CursorHotkeyState.JumpMap[A_ThisHotkey]
    if (direction = "")
        return
    jumpDist := CursorConfig.JumpDistance
    if (direction = "Up")
        MouseMove, 0, % -jumpDist, 0, R
    else if (direction = "Down")
        MouseMove, 0, %jumpDist%, 0, R
    else if (direction = "Left")
        MouseMove, % -jumpDist, 0, 0, R
    else if (direction = "Right")
        MouseMove, %jumpDist%, 0, 0, R
}

Cursor_MoveHotkeyEdge() {
    global CursorHotkeyState, CursorGridConfig

    direction := CursorHotkeyState.EdgeMap[A_ThisHotkey]
    if (direction = "")
        return
    MouseGetPos, mx, my
    monitor := GetMonitorWorkAreaInfoFromPoint(mx, my)
    if !IsObject(monitor)
        return
    inset := CursorGridConfig.EdgeInset
    if (direction = "Up")
        MouseMove, %mx%, % monitor.Top + inset, 0
    else if (direction = "Down")
        MouseMove, %mx%, % monitor.Bottom - 1 - inset, 0
    else if (direction = "Left")
        MouseMove, % monitor.Left + inset, %my%, 0
    else if (direction = "Right")
        MouseMove, % monitor.Right - 1 - inset, %my%, 0
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
    cols := Cursor_GetGridDivisionCount("Cols")
    rows := Cursor_GetGridDivisionCount("Rows")

    return {Monitor: monitor, cols: cols, rows: rows
        , monLeft: monitor.Left, monTop: monitor.Top, monRight: monitor.Right - 1, monBottom: monitor.Bottom - 1
        , unitW: monitor.Width / cols, unitH: monitor.Height / rows}
}

Cursor_GetGridDivisionCount(axis) {
    global CursorGridConfig

    ; Cursor grid is independent from the window grid layout.
    if (axis = "Cols")
        value := CursorGridConfig.DefaultCols
    else
        value := CursorGridConfig.DefaultRows

    if (value < 1)
        value := 1
    return value
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
