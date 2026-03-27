; ==============================================================================
; GridWindow.ahk
; 依存: Application.ahk (CloseTooltip)
;       WindowManager.ahk (MoveWindowPixel, GetMonitorWorkAreaFromWindow)
; ==============================================================================

global GridModes := []
GridModes.Push({Rows: 3, Cols: 2})
GridModes.Push({Rows: 2, Cols: 4})
; GridModes.Push({Rows: 2, Cols: 2})
; GridModes.Push({Cols: 3, Rows: 3})
; GridModes.Push({Rows: 2, Cols: 3})

global GridModeIndex := 1
global GRID_COLS := GridModes[GridModeIndex].Cols
global GRID_ROWS := GridModes[GridModeIndex].Rows

Grid_ToggleMode() {
    GridModeIndex += 1

    if (GridModeIndex > GridModes.MaxIndex()) {
        GridModeIndex := 1
    }

    CurrentMode := GridModes[GridModeIndex]
    GRID_COLS := CurrentMode.Cols
    GRID_ROWS := CurrentMode.Rows

    ToolTip, Grid Mode: %GRID_ROWS%x%GRID_COLS%
    SetTimer, CloseToolTip, -1500
}

Grid_Move(dx, dy) {
    hwnd := WinExist("A")
    if !hwnd
        return
    State := Grid_GetRawState(hwnd)
    NextX := State.gx + dx
    NextY := State.gy + dy
    if (NextX < 0) {
        if (Grid_MoveAcrossMonitor(hwnd, State, "Left"))
            return
        NextX := 0
    }
    if (NextY < 0) {
        if (Grid_MoveAcrossMonitor(hwnd, State, "Up"))
            return
        NextY := 0
    }
    if (NextX + State.gw > GRID_COLS) {
        if (Grid_MoveAcrossMonitor(hwnd, State, "Right"))
            return
        NextX := GRID_COLS - State.gw
    }
    if (NextY + State.gh > GRID_ROWS) {
        if (Grid_MoveAcrossMonitor(hwnd, State, "Down"))
            return
        NextY := GRID_ROWS - State.gh
    }
    Grid_SetWindow(hwnd, State, NextX, NextY, State.gw, State.gh)
}

Grid_Resize(Dimension, Delta) {
    hwnd := WinExist("A")
    if !hwnd
        return
    State := Grid_GetRawState(hwnd)
    TargetW := State.gw
    TargetH := State.gh
    if (Dimension = "Width") {
        if (Delta < 0 && State.rawW > State.gw + 0.1) {
        } else {
            TargetW += Delta
        }
    } else {
        if (Delta < 0 && State.rawH > State.gh + 0.1) {
        } else {
            TargetH += Delta
        }
    }
    if (TargetW < 1)
        TargetW := 1
    if (TargetH < 1)
        TargetH := 1
    if (State.gx + TargetW > GRID_COLS) {
        TargetW := GRID_COLS - State.gx
    }
    if (State.gy + TargetH > GRID_ROWS) {
        TargetH := GRID_ROWS - State.gy
    }
    Grid_SetWindow(hwnd, State, State.gx, State.gy, TargetW, TargetH)
}

Grid_GetRawState(hwnd) {
    monitor := GetMonitorWorkAreaInfoFromWindow(hwnd)
    if !IsObject(monitor)
        return ""

    layout := Grid_GetMonitorLayout(monitor)
    MonLeft := layout.MonLeft
    MonTop := layout.MonTop
    UnitW := layout.UnitW
    UnitH := layout.UnitH
    try {
        GetVisibleWindowPos(wx, wy, ww, wh, "ahk_id " . hwnd)
    } catch {
        WinGetPos, wx, wy, ww, wh, ahk_id %hwnd%
    }
    rawX := (wx - MonLeft) / UnitW
    rawY := (wy - MonTop)  / UnitH
    rawW := ww / UnitW
    rawH := wh / UnitH
    ratioX := (wx - monitor.Left) / monitor.Width
    ratioY := (wy - monitor.Top) / monitor.Height
    ratioW := ww / monitor.Width
    ratioH := wh / monitor.Height
    gx := Round(rawX)
    gy := Round(rawY)
    gw := Round(rawW)
    gh := Round(rawH)
    if (gx < 0)
        gx := 0
    if (gy < 0)
        gy := 0
    if (gw < 1)
        gw := 1
    if (gh < 1)
        gh := 1
    if (gw > GRID_COLS)
        gw := GRID_COLS
    if (gh > GRID_ROWS)
        gh := GRID_ROWS
    if (gx + gw > GRID_COLS)
        gx := GRID_COLS - gw
    if (gy + gh > GRID_ROWS)
        gy := GRID_ROWS - gh
    return {gx: gx, gy: gy, gw: gw, gh: gh, rawX: rawX, rawY: rawY, rawW: rawW, rawH: rawH
        , RatioX: ratioX, RatioY: ratioY, RatioW: ratioW, RatioH: ratioH
        , Monitor: monitor, MonLeft: MonLeft, MonTop: MonTop, UnitW: UnitW, UnitH: UnitH}
}

Grid_SetWindow(hwnd, State, gx, gy, gw, gh) {
    finalX := State.MonLeft + (gx * State.UnitW)
    finalY := State.MonTop  + (gy * State.UnitH)
    finalW := gw * State.UnitW
    finalH := gh * State.UnitH
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

Grid_GetMonitorLayout(monitor) {
    return {Monitor: monitor
        , MonLeft: monitor.Left
        , MonTop: monitor.Top
        , UnitW: monitor.Width / GRID_COLS
        , UnitH: monitor.Height / GRID_ROWS}
}

Grid_MoveAcrossMonitor(hwnd, State, direction) {
    targetMonitor := GetAdjacentMonitorWorkAreaInfo(State.Monitor, direction)
    if !IsObject(targetMonitor)
        return false

    ratioW := Grid_ClampRatio(State.RatioW)
    ratioH := Grid_ClampRatio(State.RatioH)
    ratioX := Grid_ClampRatio(State.RatioX)
    ratioY := Grid_ClampRatio(State.RatioY)

    if (ratioX + ratioW > 1)
        ratioX := 1 - ratioW
    if (ratioY + ratioH > 1)
        ratioY := 1 - ratioH
    if (ratioX < 0)
        ratioX := 0
    if (ratioY < 0)
        ratioY := 0

    if (direction = "Left")
        ratioX := 1 - ratioW
    else if (direction = "Right")
        ratioX := 0
    else if (direction = "Up")
        ratioY := 1 - ratioH
    else if (direction = "Down")
        ratioY := 0

    Grid_SetWindowByRatio(hwnd, targetMonitor, ratioX, ratioY, ratioW, ratioH)
    return true
}

Grid_SetWindowByRatio(hwnd, monitor, xRatio, yRatio, wRatio, hRatio) {
    finalX := monitor.Left + (monitor.Width * xRatio)
    finalY := monitor.Top + (monitor.Height * yRatio)
    finalW := monitor.Width * wRatio
    finalH := monitor.Height * hRatio
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

Grid_ClampRatio(value) {
    if (value < 0)
        return 0
    if (value > 1)
        return 1
    return value
}
