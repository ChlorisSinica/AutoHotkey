; ========================================================
; 関数群
; =======================================================

MoveWindow(targetTitle, x, y, w, h) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel) {
            return
        }
    }
    WinMove, %targetTitle%,, x, y, w, h
}

; ピクセル指定移動 (見た目のズレ補正付き)
MoveWindowPixel(hwnd, x, y, w, h) {
    MoveWindowPixelOnce(hwnd, x, y, w, h)

    ; On DPI/frame changes between monitors the first correction can still miss.
    GetVisibleWindowPos(actualX, actualY, actualW, actualH, "ahk_id " . hwnd)
    if (Abs(actualX - x) > 1 || Abs(actualY - y) > 1 || Abs(actualW - w) > 1 || Abs(actualH - h) > 1)
        MoveWindowPixelOnce(hwnd, x, y, w, h)
}

MoveWindowPixelOnce(hwnd, x, y, w, h) {
    ; 現在の論理座標
    WinGetPos, lx, ly, lw, lh, ahk_id %hwnd%

    ; 見た目の座標を取得してオフセット計算
    VarSetCapacity(rect, 16, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", &rect, "UInt", 16)

    if (hr = 0) {
        vx := NumGet(rect, 0, "Int"), vy := NumGet(rect, 4, "Int")
        vr := NumGet(rect, 8, "Int"), vb := NumGet(rect, 12, "Int")
        vw := vr - vx, vh := vb - vy

        ; 補正値を計算
        offsetX := vx - lx
        offsetY := vy - ly
        offsetW := vw - lw
        offsetH := vh - lh

        ; 補正値を適用
        x -= offsetX
        y -= offsetY
        w -= offsetW
        h -= offsetH
    }

    WinMove, ahk_id %hwnd%,, x, y, w, h
}

; 比率(0.0～1.0)でウィンドウを移動する関数
MoveWindowRatio(targetTitle, xRatio, yRatio, wRatio, hRatio) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel)
            return
    }

    WinGet, hwnd, ID, %targetTitle%
    if !hwnd
        return

    ; ★重要: ウィンドウが現在あるモニターの作業領域を取得
    monitor := GetMonitorWorkAreaInfoFromWindow(hwnd)
    if !IsObject(monitor)
        return
    placement := GetWindowPlacementArea(monitor)

    ; 比率からピクセル値を計算
    finalX := placement.Left + (placement.Width * xRatio)
    finalY := placement.Top + (placement.Height * yRatio)
    finalW := placement.Width * wRatio
    finalH := placement.Height * hRatio

    ; ピクセル計算結果を使って移動 (DWM補正付き)
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

MoveWindowMaxHeightKeepWidth(targetTitle := "A", gapEdge := "Top") {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel)
            return
    }

    WinGet, hwnd, ID, %targetTitle%
    if !hwnd
        return

    monitor := GetMonitorWorkAreaInfoFromWindow(hwnd)
    if !IsObject(monitor)
        return
    placement := GetWindowPlacementArea(monitor)

    GetVisibleWindowPos(x, y, w, h, "ahk_id " . hwnd)
    toolbarGap := GetMonitorToolbarGap(monitor.Height)
    finalX := x
    finalW := w
    finalY := placement.Top
    finalH := placement.Height - toolbarGap

    if (gapEdge = "Top")
        finalY := placement.Top + toolbarGap

    if (finalH < 1)
        finalH := 1
    if (finalW > placement.Width) {
        finalW := placement.Width
        finalX := placement.Left
    } else {
        if (finalX < placement.Left)
            finalX := placement.Left
        if (finalX + finalW > placement.Right)
            finalX := placement.Right - finalW
    }

    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

GetMonitorToolbarGap(monitorHeight) {
    return Round(monitorHeight * 0.03)
}

WindowIsland_Toggle() {
    global EnableWinIsland

    EnableWinIsland := !EnableWinIsland
    ToolTip, % EnableWinIsland ? "Window Island: ON" : "Window Island: OFF"
    SetTimer, CloseToolTip, -1500
}

WindowIsland_Enabled() {
    global EnableWinIsland
    return EnableWinIsland
}

ApplyWindowIslandToRect(monitor, ByRef x, ByRef y, ByRef w, ByRef h) {
    if (!WindowIsland_Enabled() || !IsObject(monitor))
        return

    insets := GetWindowIslandInsets(monitor)
    minWidth := 240
    minHeight := 180

    maxInsetX := Floor((w - minWidth) / 2)
    maxInsetY := Floor((h - minHeight) / 2)
    if (maxInsetX < 0)
        maxInsetX := 0
    if (maxInsetY < 0)
        maxInsetY := 0

    insetX := (insets.X < maxInsetX) ? insets.X : maxInsetX
    insetY := (insets.Y < maxInsetY) ? insets.Y : maxInsetY

    x += insetX
    y += insetY
    w -= insetX * 2
    h -= insetY * 2
}

GetWindowIslandGaps(monitor) {
    shortEdge := (monitor.Width < monitor.Height) ? monitor.Width : monitor.Height
    gapX := Round(shortEdge * 0.006)
    gapY := Round(shortEdge * 0.008)
    return {OuterX: gapX, OuterY: gapY, InnerX: gapX, InnerY: gapY}
}

GetWindowIslandInsets(monitor) {
    gaps := GetWindowIslandGaps(monitor)
    insetX := gaps.OuterX
    insetY := gaps.OuterY
    return {X: insetX, Y: insetY}
}

GetWindowPlacementArea(monitor) {
    if !IsObject(monitor)
        return ""

    left := monitor.Left
    top := monitor.Top
    right := monitor.Right
    bottom := monitor.Bottom

    if (WindowIsland_Enabled()) {
        gaps := GetWindowIslandGaps(monitor)
        left += gaps.OuterX
        top += gaps.OuterY
        right -= gaps.OuterX
        bottom -= gaps.OuterY
    }

    width := right - left
    height := bottom - top
    if (width < 1)
        width := 1
    if (height < 1)
        height := 1

    return {Left: left
        , Top: top
        , Right: left + width
        , Bottom: top + height
        , Width: width
        , Height: height}
}

; ========================================================
; アプリ名・座標・比率を一括取得
; ========================================================
GetActiveWindowInfo() {
    ; 1. 基本情報の取得
    WinGet, processName, ProcessName, A
    WinGetTitle, title, A
    WinGet, hwnd, ID, A

    ; 2. ピクセル座標の取得 (DWM補正付き)
    GetVisibleWindowPos(x, y, w, h, "A")

    ; 3. 比率の計算 (GetActiveWindowPosRatioのロジック)
    monitor := GetMonitorWorkAreaInfoFromWindow(hwnd)
    if !IsObject(monitor)
        return
    placement := GetWindowPlacementArea(monitor)
    rx := (x - placement.Left) / placement.Width
    ry := (y - placement.Top)  / placement.Height
    rw := w / placement.Width
    rh := h / placement.Height

    ; 4. 結果の整形
    ; 設定ファイル用にそのまま貼れるコマンド文字列
    ratioCommand := Format("MoveWindowRatio(""A"", {:.3f}, {:.3f}, {:.3f}, {:.3f})", rx, ry, rw, rh)

    infoText := "【プロセス名】 " . processName . "`n"
        .  "【タイトル】 " . title . "`n"
        .  "【ピクセル座標】 X=" . x . " Y=" . y . " W=" . w . " H=" . h . "`n"
        .  "--------------------------------------------------`n"
        .  "【比率コマンド (クリップボードにコピー済)】`n" . ratioCommand

    ; 5. 出力
    Clipboard := ratioCommand
    MsgBox, 64, ウィンドウ情報解析, %infoText%
}

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

GetVisibleWindowPos(ByRef X, ByRef Y, ByRef Width, ByRef Height, WinTitle := "A") {
    ; 対象ウィンドウのハンドル(ID)を取得
    WinGet, hwnd, ID, %WinTitle%
    if !hwnd
        return

    ; RECT構造体のためのメモリ確保 (4バイト整数 x 4 = 16バイト)
    VarSetCapacity(rect, 16, 0)

    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    ; 成功すると 0 (S_OK) が返る
    hr := DllCall("dwmapi\DwmGetWindowAttribute"
        , "Ptr",  hwnd
        , "UInt", 9
        , "Ptr",  &rect
        , "UInt", 16)

    if (hr = 0) {
        ; --- 成功時: DWMから取得した「見た目の座標」を使用 ---
        X := NumGet(rect, 0, "Int")      ; Left
        Y := NumGet(rect, 4, "Int")      ; Top
        R := NumGet(rect, 8, "Int")      ; Right
        B := NumGet(rect, 12, "Int")     ; Bottom

        Width  := R - X
        Height := B - Y
    } else {
        ; --- 失敗時（DWM非対応など）: 通常のWinGetPosで代用 ---
        WinGetPos, X, Y, Width, Height, ahk_id %hwnd%
    }
}

GetMonitorWorkAreaInfoList() {
    monitors := []
    SysGet, MonCount, MonitorCount

    Loop, %MonCount% {
        SysGet, Work, MonitorWorkArea, %A_Index%
        width := WorkRight - WorkLeft
        height := WorkBottom - WorkTop
        monitors.Push({Index: A_Index
            , Left: WorkLeft
            , Top: WorkTop
            , Right: WorkRight
            , Bottom: WorkBottom
            , Width: width
            , Height: height
            , CenterX: WorkLeft + (width / 2)
            , CenterY: WorkTop + (height / 2)})
    }

    return monitors
}

GetMonitorWorkAreaInfoFromPoint(x, y) {
    monitors := GetMonitorWorkAreaInfoList()
    if !monitors.MaxIndex()
        return ""

    SysGet, primaryIndex, MonitorPrimary
    fallback := monitors[1]

    for _, monitor in monitors {
        if (monitor.Index = primaryIndex)
            fallback := monitor

        if (x >= monitor.Left && x < monitor.Right && y >= monitor.Top && y < monitor.Bottom)
            return monitor
    }

    return fallback
}

GetMonitorWorkAreaInfoFromWindow(hwnd) {
    WinGetPos, x, y, w, h, ahk_id %hwnd%
    cx := x + (w / 2)
    cy := y + (h / 2)
    return GetMonitorWorkAreaInfoFromPoint(cx, cy)
}

GetAdjacentMonitorWorkAreaInfo(currentMonitor, direction) {
    if !IsObject(currentMonitor)
        return ""

    monitors := GetMonitorWorkAreaInfoList()
    bestMonitor := ""
    bestOverlap := -1
    bestSideDistance := 0
    bestCenterDistance := 0

    for _, candidate in monitors {
        if (candidate.Index = currentMonitor.Index)
            continue

        if (direction = "Left" || direction = "Right") {
            if (direction = "Left" && candidate.Right > currentMonitor.Left)
                continue
            if (direction = "Right" && candidate.Left < currentMonitor.Right)
                continue

            overlap := GetSpanOverlap(currentMonitor.Top, currentMonitor.Bottom, candidate.Top, candidate.Bottom)
            if (overlap <= 0)
                continue
            sideDistance := (direction = "Left")
                ? (currentMonitor.Left - candidate.Right)
                : (candidate.Left - currentMonitor.Right)
            centerDistance := Abs(currentMonitor.CenterY - candidate.CenterY)
        } else {
            if (direction = "Up" && candidate.Bottom > currentMonitor.Top)
                continue
            if (direction = "Down" && candidate.Top < currentMonitor.Bottom)
                continue

            overlap := GetSpanOverlap(currentMonitor.Left, currentMonitor.Right, candidate.Left, candidate.Right)
            if (overlap <= 0)
                continue
            sideDistance := (direction = "Up")
                ? (currentMonitor.Top - candidate.Bottom)
                : (candidate.Top - currentMonitor.Bottom)
            centerDistance := Abs(currentMonitor.CenterX - candidate.CenterX)
        }

        if (!IsObject(bestMonitor)
            || overlap > bestOverlap
            || (overlap = bestOverlap && sideDistance < bestSideDistance)
            || (overlap = bestOverlap && sideDistance = bestSideDistance && centerDistance < bestCenterDistance)) {
            bestMonitor := candidate
            bestOverlap := overlap
            bestSideDistance := sideDistance
            bestCenterDistance := centerDistance
        }
    }

    return bestMonitor
}

GetSpanOverlap(start1, end1, start2, end2) {
    overlapStart := (start1 > start2) ? start1 : start2
    overlapEnd := (end1 < end2) ? end1 : end2
    overlap := overlapEnd - overlapStart
    return (overlap > 0) ? overlap : 0
}

GetSpanGap(start1, end1, start2, end2) {
    if (end1 < start2)
        return start2 - end1
    if (end2 < start1)
        return start1 - end2
    return 0
}

; 補助関数: ウィンドウハンドルからモニターハンドルを取得（今回は簡易ロジックで代用したので未使用でも可）
GetMonitorHandleFromWindow(hwnd) {
    ; Windows API: MonitorFromWindow
    return DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2) ; 2=MONITOR_DEFAULTTONEAREST
}

GetMonitorWorkAreaFromPoint(x, y, ByRef Left, ByRef Top, ByRef Width, ByRef Height) {
    monitor := GetMonitorWorkAreaInfoFromPoint(x, y)
    if !IsObject(monitor)
        return

    Left := monitor.Left
    Top := monitor.Top
    Width := monitor.Width
    Height := monitor.Height
}

; 指定ウィンドウが含まれるモニターの作業領域を取得
GetMonitorWorkAreaFromWindow(hwnd, ByRef Left, ByRef Top, ByRef Width, ByRef Height) {
    monitor := GetMonitorWorkAreaInfoFromWindow(hwnd)
    if !IsObject(monitor)
        return

    Left := monitor.Left
    Top := monitor.Top
    Width := monitor.Width
    Height := monitor.Height
}
