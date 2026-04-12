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

global GridModeIndex  := 1
global GRID_COLS      := GridModes[GridModeIndex].Cols
global GRID_ROWS      := GridModes[GridModeIndex].Rows

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
    try {
        GetVisibleWindowPos(wx, wy, ww, wh, "ahk_id " . hwnd)
    } catch {
        WinGetPos, wx, wy, ww, wh, ahk_id %hwnd%
    }
    cx := wx + (ww / 2)
    cy := wy + (wh / 2)
    monitor := GetMonitorWorkAreaInfoFromPoint(cx, cy)
    if !IsObject(monitor)
        return ""

    layout := Grid_GetMonitorLayout(monitor)
    MonLeft := layout.AreaLeft
    MonTop := layout.AreaTop
    PitchW := layout.PitchW
    PitchH := layout.PitchH
    InnerX := layout.InnerX
    InnerY := layout.InnerY
    rawX := (wx - MonLeft) / PitchW
    rawY := (wy - MonTop) / PitchH
    rawW := (ww + InnerX) / PitchW
    rawH := (wh + InnerY) / PitchH
    ratioX := (wx - layout.AreaLeft) / layout.AreaWidth
    ratioY := (wy - layout.AreaTop) / layout.AreaHeight
    ratioW := ww / layout.AreaWidth
    ratioH := wh / layout.AreaHeight
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
        , Monitor: monitor, MonLeft: MonLeft, MonTop: MonTop
        , CellW: layout.CellW, CellH: layout.CellH
        , PitchW: PitchW, PitchH: PitchH
        , InnerX: InnerX, InnerY: InnerY}
}

Grid_SetWindow(hwnd, State, gx, gy, gw, gh) {
    finalX := State.MonLeft + (gx * State.PitchW)
    finalY := State.MonTop + (gy * State.PitchH)
    finalW := (gw * State.CellW) + ((gw - 1) * State.InnerX)
    finalH := (gh * State.CellH) + ((gh - 1) * State.InnerY)
    Grid_ClampToWorkArea(State.Monitor, finalX, finalY, finalW, finalH)
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

Grid_GetMonitorLayout(monitor) {
    outerX := 0
    outerY := 0
    innerX := 0
    innerY := 0

    if (WindowIsland_Enabled()) {
        gaps := GetWindowIslandGaps(monitor)
        outerX := gaps.OuterX
        outerY := gaps.OuterY
        innerX := gaps.InnerX
        innerY := gaps.InnerY
    }

    Grid_NormalizeAxisGaps(monitor.Width, GRID_COLS, outerX, innerX, cellW, pitchW, areaW)
    Grid_NormalizeAxisGaps(monitor.Height, GRID_ROWS, outerY, innerY, cellH, pitchH, areaH)

    return {Monitor: monitor
        , MonLeft: monitor.Left
        , MonTop: monitor.Top
        , AreaLeft: monitor.Left + outerX
        , AreaTop: monitor.Top + outerY
        , AreaWidth: areaW
        , AreaHeight: areaH
        , CellW: cellW
        , CellH: cellH
        , PitchW: pitchW
        , PitchH: pitchH
        , OuterX: outerX
        , OuterY: outerY
        , InnerX: innerX
        , InnerY: innerY}
}

Grid_MoveAcrossMonitor(hwnd, State, direction) {
    targetMonitor := GetAdjacentMonitorWorkAreaInfo(State.Monitor, direction)
    if !IsObject(targetMonitor)
        return false

    layout := Grid_GetMonitorLayout(targetMonitor)
    gw := State.gw
    gh := State.gh
    gx := State.gx
    gy := State.gy

    if (direction = "Left")
        gx := GRID_COLS - gw
    else if (direction = "Right")
        gx := 0
    else if (direction = "Up")
        gy := GRID_ROWS - gh
    else if (direction = "Down")
        gy := 0

    finalX := layout.AreaLeft + (gx * layout.PitchW)
    finalY := layout.AreaTop + (gy * layout.PitchH)
    finalW := (gw * layout.CellW) + ((gw - 1) * layout.InnerX)
    finalH := (gh * layout.CellH) + ((gh - 1) * layout.InnerY)
    Grid_ClampToWorkArea(targetMonitor, finalX, finalY, finalW, finalH)
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
    return true
}

Grid_SetWindowByRatio(hwnd, monitor, xRatio, yRatio, wRatio, hRatio) {
    layout := Grid_GetMonitorLayout(monitor)
    finalX := layout.AreaLeft + (layout.AreaWidth * xRatio)
    finalY := layout.AreaTop + (layout.AreaHeight * yRatio)
    finalW := layout.AreaWidth * wRatio
    finalH := layout.AreaHeight * hRatio
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

Grid_ClampRatio(value) {
    if (value < 0)
        return 0
    if (value > 1)
        return 1
    return value
}

Grid_ClampToWorkArea(monitor, ByRef x, ByRef y, ByRef w, ByRef h) {
    if !IsObject(monitor)
        return
    if (y < monitor.Top)
        y := monitor.Top
    if (x < monitor.Left)
        x := monitor.Left
    if (x + w > monitor.Right)
        x := monitor.Right - w
    if (y + h > monitor.Bottom)
        y := monitor.Bottom - h
}

Grid_NormalizeAxisGaps(axisSize, count, ByRef outerGap, ByRef innerGap, ByRef cellSize, ByRef pitchSize, ByRef areaSize) {
    if (count < 1)
        count := 1

    minCellSize := 1
    availableForGaps := axisSize - (count * minCellSize)
    if (availableForGaps < 0)
        availableForGaps := 0

    requestedGapSize := (outerGap * 2) + (innerGap * (count - 1))
    if (requestedGapSize > availableForGaps && requestedGapSize > 0) {
        scale := availableForGaps / requestedGapSize
        outerGap := Floor(outerGap * scale)
        innerGap := Floor(innerGap * scale)
    }

    areaSize := axisSize - (outerGap * 2)
    if (areaSize < count)
        areaSize := count

    cellSize := (axisSize - (outerGap * 2) - (innerGap * (count - 1))) / count
    if (cellSize < 1)
        cellSize := 1
    pitchSize := cellSize + innerGap
}
