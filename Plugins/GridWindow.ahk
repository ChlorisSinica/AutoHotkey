; ==============================================================================
; GridWindow.ahk
; 依存: Application.ahk (CloseTooltip)
;       WindowManager.ahk (MoveWindowPixel, GetMonitorWorkAreaFromWindow)
; ==============================================================================

global GridModes := []
GridModes.Push({Cols: 2, Rows: 2, Name: "2x2 (2列 x 2行)"})
GridModes.Push({Cols: 4, Rows: 2, Name: "2x4 (4列 x 2行)"})
GridModes.Push({Cols: 3, Rows: 2, Name: "2x3 (3列 x 2行)"})
GridModes.Push({Cols: 2, Rows: 3, Name: "3x2 (2列 x 3行)"})
GridModes.Push({Cols: 3, Rows: 3, Name: "3x3 (3列 x 3行)"})

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
    if (NextX < 0)
        NextX := 0
    if (NextY < 0)
        NextY := 0
    if (NextX + State.gw > GRID_COLS)
        NextX := GRID_COLS - State.gw
    if (NextY + State.gh > GRID_ROWS)
        NextY := GRID_ROWS - State.gh
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
    GetMonitorWorkAreaFromWindow(hwnd, MonLeft, MonTop, MonWidth, MonHeight)
    try {
        GetVisibleWindowPos(wx, wy, ww, wh, "ahk_id " . hwnd)
    } catch {
        WinGetPos, wx, wy, ww, wh, ahk_id %hwnd%
    }
    UnitW := MonWidth / GRID_COLS
    UnitH := MonHeight / GRID_ROWS
    rawX := (wx - MonLeft) / UnitW
    rawY := (wy - MonTop)  / UnitH
    rawW := ww / UnitW
    rawH := wh / UnitH
    gx := Round(rawX)
    gy := Round(rawY)
    gw := Round(rawW)
    gh := Round(rawH)
    if (gw < 1)
        gw := 1
    if (gh < 1)
        gh := 1
    return {gx: gx, gy: gy, gw: gw, gh: gh, rawW: rawW, rawH: rawH, MonLeft: MonLeft, MonTop: MonTop, UnitW: UnitW, UnitH: UnitH}
}

Grid_SetWindow(hwnd, State, gx, gy, gw, gh) {
    finalX := State.MonLeft + (gx * State.UnitW)
    finalY := State.MonTop  + (gy * State.UnitH)
    finalW := gw * State.UnitW
    finalH := gh * State.UnitH
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}