; ============================================================================
; PowerPoint.ahk - COM + UIA ハイブリッド構成
; ============================================================================
global _PPT_IMG_EXT   := "png|jpg|jpeg|bmp|tif|tiff|gif"
global _PPT_MEDIA_EXT := "mp4|avi|wmv|mov|mkv|mp3|wav|wma|m4a|m4v|webm"
global _PPT_ALL_EXT   := _PPT_IMG_EXT . "|" . _PPT_MEDIA_EXT
global PPT_SpacingLogEnabled := true
global PPT_SpacingLogDir := A_ScriptDir . "\.claude"
global PPT_SpacingLogPath := PPT_SpacingLogDir . "\powerpoint_spacing_debug.log"
global PPT_SpacingLogMaxBytes := 262144
global PPT_SpacingEpsilon := 0.05

; ============================================================================
;  COM ヘルパー
; ============================================================================
PPT_GetApp() {
    try {
        return ComObjActive("PowerPoint.Application")
    } catch {
        return ""
    }
}

PPT_GetSelectedShapes() {
    app := PPT_GetApp()
    if !app
        return ""
    try {
        sel := app.ActiveWindow.Selection
        if (sel.Type = 2)
            return sel.ShapeRange
    } catch e {
        PPT_SpacingLog("get_selected_shapes_error", "error=" . e.Message)
    }
    return ""
}

; ============================================================================
;  整列 (COM: ShapeRange.Align / .Distribute)
; ============================================================================
; 第2引数: -1 = スライド基準 (単一図形でも動作)
;            0 = 図形間相対 (複数選択時のみ意味がある)
;
; 方針: 単一選択→スライド基準 / 複数選択→図形間相対 で自動切替
PPT_AlignRelTo(shp) {
    ; Count=1 ならスライド基準(-1), 複数なら図形間相対(0)
    try {
        if (shp.Count <= 1)
            return -1
    } catch {
    }
    return 0
}

SetLeft() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(0, PPT_AlignRelTo(shp))
}
SetRight() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(2, PPT_AlignRelTo(shp))
}
SetTop() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(3, PPT_AlignRelTo(shp))
}
SetBottom() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(5, PPT_AlignRelTo(shp))
}
SetHorizontalCenter() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(1, PPT_AlignRelTo(shp))
}
SetVerticalCenter() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(4, PPT_AlignRelTo(shp))
}
SetHorizontalSpacer() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Distribute(0, 0)
}
SetVerticalSpace() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Distribute(1, 0)
}

; ============================================================================
;  グループ化 / 解除
; ============================================================================
GroupSet() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        newShp := shp.Group()
        newShp.Select()
    } catch {
    }
}
GroupRelease() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        newRange := shp.Ungroup()
        newRange.Select()
    } catch {
    }
}

; ============================================================================
;  前面 / 背面
; ============================================================================
SetFront() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        shp.ZOrder(0)
        shp.Select()
    } catch {
    }
}
SetBack() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        shp.ZOrder(1)
        shp.Select()
    } catch {
    }
}

; ============================================================================
;  枠線
; ============================================================================
; ExecuteMso の idMso はバージョンにより異なる場合がある。
; 複数候補を順に試行し、全て失敗したらキーチップにフォールバックする。
PPT_TryExecuteMso(candidates, fallbackKeys := "") {
    app := PPT_GetApp()
    if !app
        return false
    for _, idMso in candidates {
        try {
            app.CommandBars.ExecuteMso(idMso)
            return true
        } catch {
        }
    }
    ; 全 idMso が失敗 → キーチップにフォールバック
    if (fallbackKeys != "") {
        Send, %fallbackKeys%
        return true
    }
    return false
}

SetFrameLine() {
    PPT_TryExecuteMso(["ShapeOutlineColorPicker", "OutlineColorPicker"]
        , "!jpsow{Home}{Down}{Enter}")
}

SetFrameSize() {
    PPT_TryExecuteMso(["OutlineWeightGallery", "ShapeOutlineWeightPicker"
        , "ShapeOutlineWeightMoreLinesDialog"], "!jpw")
}

; 黒枠線サイクル: 0.5pt → 0.25pt → 枠線なし → 0.5pt ...
PPT_CycleBlackBorder() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return

    try {
        line := shp.Item(1).Line
        isVisible := line.Visible
        weight := line.Weight

        ; 現在の状態を判定してサイクル
        if (isVisible = 0) {
            ; 枠線なし → 黒 0.5pt
            PPT_SetBorder(shp, true, 0, 0.5)
            ToolTip, 枠線: 黒 0.5pt
        } else if (weight > 0.3) {
            ; 0.5pt → 0.25pt
            PPT_SetBorder(shp, true, 0, 0.25)
            ToolTip, 枠線: 黒 0.25pt
        } else {
            ; 0.25pt → なし
            PPT_SetBorder(shp, false, 0, 0)
            ToolTip, 枠線: なし
        }
        SetTimer, CloseToolTip, -1500
    } catch {
    }
}

PPT_SetBorder(shp, visible, rgb, weight) {
    try {
        Loop % shp.Count {
            line := shp.Item(A_Index).Line
            if (visible) {
                line.Visible := -1  ; msoTrue
                line.ForeColor.RGB := rgb
                line.Weight := weight
            } else {
                line.Visible := 0   ; msoFalse
            }
        }
    } catch {
    }
}

; ============================================================================
;  書式設定パネルを開く / テキストのみ貼り付け
; ============================================================================
OpenFormatObject() {
    ; パネルが開いているか UIA で検出 (FindElementByKeyword を使わない)
    panel := PPT_DetectFormatPanel()
    if (panel) {
        ; 開いている → 閉じる
        PPT_CloseFormatPanel(panel)
        return
    }
    ; 閉じている → 開く
    PPT_TryExecuteMso(["ObjectSizeAndPositionDialog"])
}

PPT_DetectFormatPanel() {
    hwnd := WinExist("ahk_exe POWERPNT.EXE")
    if !hwnd
        return ""
    uia := UIA_Interface()
    if !uia
        return ""
    try {
        rootEl := uia.ElementFromHandle(hwnd)
    } catch {
        return ""
    }
    if !rootEl
        return ""

    panelNames := ["Format Shape", "Format Picture", "Size and Properties"
        , "図形の書式設定", "図の書式設定", "サイズとプロパティ"]
    for _, n in panelNames {
        try {
            cond := uia.CreatePropertyCondition(30005, n)  ; NamePropertyId
            found := rootEl.FindFirst(cond, 0x4)  ; Descendants
            if found
                return found
        } catch {
        }
    }
    return ""
}

PPT_CloseFormatPanel(panel) {
    ; パネルの親要素から Close ボタンを探す
    try {
        uia := UIA_Interface()
        walker := uia.TreeWalkerTrue
        parent := walker.GetParentElement(panel)
        target := parent ? parent : panel

        btnCond := uia.CreatePropertyCondition(30003, 50000)  ; ControlType=Button
        buttons := target.FindAll(btnCond, 0x4)  ; Descendants
        if buttons {
            Loop % buttons.MaxIndex() {
                btn := buttons[A_Index]
                bName := btn.CurrentName
                if (InStr(bName, "Close") || InStr(bName, "閉じる")) {
                    try btn.Invoke()
                    return
                }
            }
        }
    } catch {
    }
    ; フォールバック: パネルにフォーカスしてCtrl+Shift+F1で閉じる
    try {
        panel.SetFocus()
        Sleep, 50
    } catch {
    }
    Send, ^+{F1}
}

PasteTextOnly() {
    PPT_TryExecuteMso(["PasteTextOnly", "PasteAsText"])
}

; ============================================================================
;  UIA層: 書式設定パネル内の SpinBox フォーカス
; ============================================================================
PPT_GetFormatPanel() {
    hwnd := WinExist("ahk_exe POWERPNT.EXE")
    if !hwnd
        return ""

    uia := UIA_Interface()
    if !uia
        return ""

    rootEl := uia.ElementFromHandle(hwnd)
    if !rootEl
        return ""

    names := []
    names.Push("Format Shape")
    names.Push("Format Picture")
    names.Push("Size and Properties")

    for _, n in names {
        cond := uia.CreatePropertyCondition(uia.NamePropertyId, n)
        panel := rootEl.FindFirst(cond, 0x4)
        if panel
            return panel
    }

    return FindElementByKeyword(rootEl, ["Format Shape", "Format Picture"])
}

PPT_FocusPanelField(keywords, excludeKeywords := "") {
    OpenFormatObject()
    Sleep, 400

    panel := PPT_GetFormatPanel()
    if !panel {
        hwnd := WinExist("ahk_exe POWERPNT.EXE")
        if !hwnd
            return false
        uia := UIA_Interface()
        panel := uia.ElementFromHandle(hwnd)
    }
    if !panel
        return false

    el := FindElementByKeyword(panel, keywords, excludeKeywords)
    if el {
        try {
            el.SetFocus()
            return true
        } catch {
        }
    }

    uia := UIA_Interface()
    editCond := uia.CreatePropertyCondition(uia.ControlTypePropertyId, uia.EditControlTypeId)
    edits := panel.FindAll(editCond, 0x4)
    if edits {
        Loop % edits.MaxIndex() {
            edit := edits[A_Index]
            try {
                eName := edit.CurrentName
                for _, kw in keywords {
                    if InStr(eName, kw) {
                        edit.SetFocus()
                        return true
                    }
                }
            } catch {
            }
        }
    }
    return false
}

FocusWidthField() {
    PPT_FocusPanelField(["Width"], ["Height"])
}
FocusHeightField() {
    PPT_FocusPanelField(["Height"], ["Width"])
}
FocusRotationField() {
    PPT_FocusPanelField(["Rotation"])
}

; ============================================================================
;  グリッド配置 & 間隔微調整
; ============================================================================
PPT_GetSlideSize() {
    app := PPT_GetApp()
    if !app
        return ""
    try {
        ps := app.ActivePresentation.PageSetup
        return {w: ps.SlideWidth, h: ps.SlideHeight}
    } catch {
    }
    return ""
}

PPT_CollectShapes(shapeRange) {
    arr := []
    try {
        Loop % shapeRange.Count {
            s := shapeRange.Item(A_Index)
            arr.Push({ref: s, id: s.Id, name: s.Name, left: s.Left, top: s.Top, w: s.Width, h: s.Height})
        }
    } catch e {
        PPT_SpacingLog("collect_shapes_error", "error=" . e.Message)
    }
    return arr
}

PPT_SortShapesByKey(ByRef arr, key) {
    Loop % arr.MaxIndex() - 1 {
        i := A_Index + 1
        temp := arr[i]
        j := i - 1
        while (j >= 1 && arr[j][key] > temp[key]) {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := temp
    }
}

PPT_ClampPosition(pos, shapeSize, slideSize) {
    if (pos < 0)
        pos := 0
    if (pos + shapeSize > slideSize)
        pos := slideSize - shapeSize
    return pos
}

PPT_SpacingEnsureLogDir() {
    global PPT_SpacingLogDir

    if !InStr(FileExist(PPT_SpacingLogDir), "D")
        FileCreateDir, %PPT_SpacingLogDir%
}

PPT_SpacingRotateLogIfNeeded() {
    global PPT_SpacingLogPath, PPT_SpacingLogMaxBytes

    if !FileExist(PPT_SpacingLogPath)
        return

    FileGetSize, logSize, %PPT_SpacingLogPath%
    if (logSize < PPT_SpacingLogMaxBytes)
        return

    backupPath := RegExReplace(PPT_SpacingLogPath, "\.log$", ".old.log")
    FileDelete, %backupPath%
    FileMove, %PPT_SpacingLogPath%, %backupPath%, 1
}

PPT_SpacingSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

PPT_SpacingValueText(value) {
    if (value = "")
        return "NA"
    return Round(value, 3)
}

PPT_SpacingNearlyEqual(a, b, epsilon := "") {
    global PPT_SpacingEpsilon

    if (epsilon = "")
        epsilon := PPT_SpacingEpsilon
    return (Abs(a - b) <= epsilon)
}

PPT_SpacingLog(event, extra := "") {
    global PPT_SpacingLogEnabled, PPT_SpacingLogPath

    if (!PPT_SpacingLogEnabled)
        return

    PPT_SpacingEnsureLogDir()
    PPT_SpacingRotateLogIfNeeded()
    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " extra=" . PPT_SpacingSanitize(extra)
    FileAppend, % line . "`n", %PPT_SpacingLogPath%, UTF-8
}

PPT_SpacingOpenLog() {
    global PPT_SpacingLogPath

    PPT_SpacingEnsureLogDir()
    if !FileExist(PPT_SpacingLogPath)
        FileAppend,, %PPT_SpacingLogPath%, UTF-8
    Run, notepad.exe "%PPT_SpacingLogPath%"
}

PPT_SpacingDescribeSelection() {
    app := PPT_GetApp()
    if !app
        return "ppt=0"

    try {
        win := app.ActiveWindow
        if !win
            return "active_window=0"

        sel := win.Selection
        if !sel
            return "selection=0"

        info := "type=" . sel.Type
        try info .= " slide=" . win.View.Slide.SlideIndex
        try {
            if (sel.Type = 2)
                info .= " count=" . sel.ShapeRange.Count
        }
        return info
    } catch e {
        return "selection_error=" . PPT_SpacingSanitize(e.Message)
    }
}

PPT_SpacingDescribeShapes(shapes) {
    text := ""
    if !IsObject(shapes)
        return "shapes=0"

    for i, s in shapes {
        if (text != "")
            text .= " | "
        text .= "#" . i
            . ":id=" . s.id
            . ",name=" . PPT_SpacingSanitize(s.name)
            . ",left=" . Round(s.left, 3)
            . ",top=" . Round(s.top, 3)
            . ",w=" . Round(s.w, 3)
            . ",h=" . Round(s.h, 3)
    }
    return text
}

PPT_GetShapeAxisPosition(shapeRef, axis) {
    try {
        if (axis = "H")
            return shapeRef.Left
        if (axis = "V")
            return shapeRef.Top
    } catch {
    }
    return ""
}

PPT_MoveShapeAxisBy(shapeRef, axis, delta) {
    if (axis = "H") {
        try {
            shapeRef.IncrementLeft(delta)
            return true
        } catch {
        }
    } else if (axis = "V") {
        try {
            shapeRef.IncrementTop(delta)
            return true
        } catch {
        }
    }
    return false
}

PPT_SetShapeAxisPosition(shapeRef, axis, pos) {
    before := PPT_GetShapeAxisPosition(shapeRef, axis)

    if (axis = "H") {
        try {
            shapeRef.Left := pos
        } catch e {
            PPT_SpacingLog("shape_set_direct_error"
                , "axis=" . axis . " target=" . Round(pos, 3) . " error=" . e.Message)
        }
    } else if (axis = "V") {
        try {
            shapeRef.Top := pos
        } catch e {
            PPT_SpacingLog("shape_set_direct_error"
                , "axis=" . axis . " target=" . Round(pos, 3) . " error=" . e.Message)
        }
    }

    after := PPT_GetShapeAxisPosition(shapeRef, axis)
    if (after != "" && PPT_SpacingNearlyEqual(after, pos)) {
        PPT_SpacingLog("shape_set_direct_ok"
            , "axis=" . axis . " before=" . PPT_SpacingValueText(before) . " after=" . PPT_SpacingValueText(after) . " target=" . Round(pos, 3))
        return true
    }

    if (before = "")
        before := 0

    delta := pos - before
    if (PPT_SpacingNearlyEqual(before, pos)) {
        PPT_SpacingLog("shape_set_noop"
            , "axis=" . axis . " before=" . PPT_SpacingValueText(before) . " after=" . PPT_SpacingValueText(after) . " target=" . Round(pos, 3))
        return (after != "")
    }

    if (PPT_MoveShapeAxisBy(shapeRef, axis, delta)) {
        afterFallback := PPT_GetShapeAxisPosition(shapeRef, axis)
        if (afterFallback != "" && PPT_SpacingNearlyEqual(afterFallback, pos)) {
            PPT_SpacingLog("shape_set_fallback_ok"
                , "axis=" . axis . " before=" . PPT_SpacingValueText(before) . " after=" . PPT_SpacingValueText(afterFallback) . " target=" . Round(pos, 3))
            return true
        }

        PPT_SpacingLog("shape_set_fallback_mismatch"
            , "axis=" . axis . " before=" . PPT_SpacingValueText(before) . " after_direct=" . PPT_SpacingValueText(after) . " after_fallback=" . PPT_SpacingValueText(afterFallback) . " target=" . Round(pos, 3))
        return false
    }

    PPT_SpacingLog("shape_set_failed"
        , "axis=" . axis . " before=" . PPT_SpacingValueText(before) . " after=" . PPT_SpacingValueText(after) . " target=" . Round(pos, 3))
    return false
}

; --- 最小オブジェクトの中心に揃える ---
; ^!u/o (既存) は最大オブジェクト基準。これはその逆で最小基準。
PPT_AlignCenterToSmallest(axis) {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        if (shp.Count < 2)
            return
    } catch {
        return
    }

    shapes := PPT_CollectShapes(shp)
    sizeKey := (axis = "H") ? "w" : "h"
    posKey := (axis = "H") ? "left" : "top"

    ; 最小サイズのオブジェクトを見つける
    minSize := shapes[1][sizeKey]
    minIdx := 1
    for i, s in shapes {
        if (s[sizeKey] < minSize) {
            minSize := s[sizeKey]
            minIdx := i
        }
    }

    ; 最小オブジェクトの中心座標
    targetCenter := shapes[minIdx][posKey] + shapes[minIdx][sizeKey] / 2

    ; 全オブジェクトをその中心に揃える
    for i, s in shapes {
        targetPos := targetCenter - s[sizeKey] / 2
        PPT_SetShapeAxisPosition(s.ref, axis, targetPos)
    }
}

; --- グリッド配置: 横方向 ---
PPT_GridDistributeH() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        if (shp.Count < 2)
            return
    } catch {
        return
    }
    slide := PPT_GetSlideSize()
    if !IsObject(slide)
        return

    shapes := PPT_CollectShapes(shp)
    PPT_SortShapesByKey(shapes, "left")
    n := shapes.MaxIndex()
    cellW := slide.w / n

    for i, s in shapes {
        cellCenter := cellW * (i - 1) + cellW / 2
        newLeft := cellCenter - s.w / 2
        newLeft := PPT_ClampPosition(newLeft, s.w, slide.w)
        try s.ref.Left := newLeft
    }

    ToolTip, % "Grid H: " . n
    SetTimer, CloseToolTip, -1500
}

; --- グリッド配置: 縦方向 ---
PPT_GridDistributeV() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        if (shp.Count < 2)
            return
    } catch {
        return
    }
    slide := PPT_GetSlideSize()
    if !IsObject(slide)
        return

    shapes := PPT_CollectShapes(shp)
    PPT_SortShapesByKey(shapes, "top")
    n := shapes.MaxIndex()
    cellH := slide.h / n

    for i, s in shapes {
        cellCenter := cellH * (i - 1) + cellH / 2
        newTop := cellCenter - s.h / 2
        newTop := PPT_ClampPosition(newTop, s.h, slide.h)
        try s.ref.Top := newTop
    }

    ToolTip, % "Grid V: " . n
    SetTimer, CloseToolTip, -1500
}

; --- 間隔微調整 ---
global PPT_SpacingState := {IsRunning: false
    , Axis: ""
    , Direction: 0
    , StepSize: 2.0
    , MaxStep: 10.0
    , Acceleration: 1.06
    , CurrentStep: 2.0
    , InitialDelay: 240
    , TimerInterval: 30
    , DelayPending: false
    , KeyToWatch: ""}

; 1ステップ分の間隔調整 (クランプ付き)
; debugLevel: 0=なし, 1=到達確認のみ, 2=詳細
global PPT_SpacingDebug := 2

PPT_SpacingAdjust(axis, direction) {
    global PPT_SpacingDebug, PPT_SpacingEpsilon

    PPT_SpacingLog("adjust_start"
        , "axis=" . axis . " direction=" . direction . " state_running=" . PPT_SpacingState.IsRunning . " " . PPT_SpacingDescribeSelection())

    shp := PPT_GetSelectedShapes()
    if !shp {
        PPT_SpacingLog("adjust_no_selection", "axis=" . axis . " direction=" . direction . " " . PPT_SpacingDescribeSelection())
        if (PPT_SpacingDebug >= 2)
            ToolTip, [DBG] no selection
        return
    }
    cnt := 0
    try cnt := shp.Count
    if (cnt < 2) {
        PPT_SpacingLog("adjust_too_few_shapes", "axis=" . axis . " direction=" . direction . " count=" . cnt)
        if (PPT_SpacingDebug >= 2)
            ToolTip, % "[DBG] count=" . cnt
        return
    }
    slide := PPT_GetSlideSize()
    if !IsObject(slide) {
        PPT_SpacingLog("adjust_no_slide", "axis=" . axis . " direction=" . direction)
        if (PPT_SpacingDebug >= 2)
            ToolTip, [DBG] no slide size
        return
    }

    shapes := PPT_CollectShapes(shp)
    PPT_SpacingLog("adjust_shapes_loaded"
        , "axis=" . axis . " direction=" . direction . " slideMax=" . ((axis = "H") ? slide.w : slide.h)
        . " shapes=" . PPT_SpacingDescribeShapes(shapes))
    posKey := (axis = "H") ? "left" : "top"
    sizeKey := (axis = "H") ? "w" : "h"
    slideMax := (axis = "H") ? slide.w : slide.h
    PPT_SortShapesByKey(shapes, posKey)

    n := shapes.MaxIndex()

    ; 重心を計算
    centroid := 0
    for i, s in shapes
        centroid += s[posKey] + s[sizeKey] / 2
    centroid := centroid / n

    ; 現在のステップサイズ (リピート時は加速値を使用)
    step := PPT_SpacingState.IsRunning ? PPT_SpacingState.CurrentStep : PPT_SpacingState.StepSize

    ; rank ベースのオフセットを計算して仮位置を求める
    newPositions := []
    for i, s in shapes {
        rank := i - (n + 1) / 2
        newPos := s[posKey] + rank * step * direction
        newPositions.Push(newPos)
    }

    ; クランプチェック: スライド外
    for i, s in shapes {
        clamped := PPT_ClampPosition(newPositions[i], s[sizeKey], slideMax)
        if !PPT_SpacingNearlyEqual(clamped, newPositions[i]) {
            PPT_SpacingLog("adjust_clamp_slide"
                , "axis=" . axis . " direction=" . direction . " index=" . i
                . " current=" . Round(s[posKey], 3) . " target=" . Round(newPositions[i], 3)
                . " clamped=" . Round(clamped, 3) . " size=" . Round(s[sizeKey], 3))
            if (PPT_SpacingDebug >= 2)
                ToolTip, % "[DBG] clamp-slide i=" . i . " pos=" . Round(newPositions[i], 1) . " clamped=" . Round(clamped, 1)
            return
        }

        newPositions[i] := clamped
    }

    ; クランプチェック: 重なり (隙間 >= 0)
    Loop % n - 1 {
        i := A_Index
        rightEdge := newPositions[i] + shapes[i][sizeKey]
        if ((rightEdge - newPositions[i + 1]) > PPT_SpacingEpsilon) {
            PPT_SpacingLog("adjust_clamp_overlap"
                , "axis=" . axis . " direction=" . direction . " leftIndex=" . i
                . " leftEdge=" . Round(rightEdge, 3) . " rightTarget=" . Round(newPositions[i + 1], 3))
            if (PPT_SpacingDebug >= 2)
                ToolTip, % "[DBG] clamp-overlap i=" . i . " edge=" . Round(rightEdge, 1) . " next=" . Round(newPositions[i + 1], 1)
            return
        }
    }

    ; 全チェック通過 → 適用
    applyResults := ""
    for i, s in shapes {
        ok := PPT_SetShapeAxisPosition(s.ref, axis, newPositions[i])
        actual := PPT_GetShapeAxisPosition(s.ref, axis)
        if (applyResults != "")
            applyResults .= " | "
        applyResults .= "#" . i
            . ":id=" . s.id
            . ",from=" . Round(s[posKey], 3)
            . ",to=" . Round(newPositions[i], 3)
            . ",actual=" . PPT_SpacingValueText(actual)
            . ",ok=" . (ok ? 1 : 0)
    }
    PPT_SpacingLog("adjust_applied"
        , "axis=" . axis . " direction=" . direction . " step=" . Round(step, 3) . " results=" . applyResults)

    if (PPT_SpacingDebug >= 2)
        ToolTip, % "[DBG] applied " . axis . " dir=" . direction . " step=" . Round(step, 2)
}

; 長押しリピート開始
PPT_SpacingRepeatStart(axis, direction, watchKey) {
    global PPT_SpacingState, PPT_SpacingDebug

    if (PPT_SpacingState.IsRunning
        && PPT_SpacingState.Axis = axis
        && PPT_SpacingState.Direction = direction
        && PPT_SpacingState.KeyToWatch = watchKey) {
        PPT_SpacingLog("repeat_start_ignored"
            , "axis=" . axis . " direction=" . direction . " key=" . watchKey)
        return
    }

    PPT_SpacingLog("repeat_start"
        , "axis=" . axis . " direction=" . direction . " key=" . watchKey . " " . PPT_SpacingDescribeSelection())

    if (PPT_SpacingDebug >= 1)
        ToolTip, % "[DBG] SpacingStart axis=" . axis . " dir=" . direction . " key=" . watchKey

    static TickFn := Func("PPT_SpacingRepeatTick")

    ; 即座に1回実行
    PPT_SpacingAdjust(axis, direction)

    ; タイマー起動
    PPT_SpacingState.Axis := axis
    PPT_SpacingState.Direction := direction
    PPT_SpacingState.CurrentStep := PPT_SpacingState.StepSize
    PPT_SpacingState.DelayPending := true
    PPT_SpacingState.KeyToWatch := watchKey
    PPT_SpacingState.IsRunning := true
    SetTimer, %TickFn%, % -PPT_SpacingState.InitialDelay
}

; タイマーコールバック
PPT_SpacingRepeatTick() {
    global PPT_SpacingState
    static TickFn := Func("PPT_SpacingRepeatTick")

    ; キーが離されたら停止
    if !GetKeyState(PPT_SpacingState.KeyToWatch, "P") {
        PPT_SpacingLog("repeat_stop_by_keyup"
            , "axis=" . PPT_SpacingState.Axis . " key=" . PPT_SpacingState.KeyToWatch)
        PPT_SpacingRepeatStop()
        return
    }

    if (PPT_SpacingState.DelayPending) {
        PPT_SpacingState.DelayPending := false
        SetTimer, %TickFn%, % PPT_SpacingState.TimerInterval
    }

    ; 加速
    PPT_SpacingState.CurrentStep := PPT_SpacingState.CurrentStep * PPT_SpacingState.Acceleration
    if (PPT_SpacingState.CurrentStep > PPT_SpacingState.MaxStep)
        PPT_SpacingState.CurrentStep := PPT_SpacingState.MaxStep

    PPT_SpacingAdjust(PPT_SpacingState.Axis, PPT_SpacingState.Direction)
}

; タイマー停止
PPT_SpacingRepeatStop() {
    global PPT_SpacingState
    static TickFn := Func("PPT_SpacingRepeatTick")

    SetTimer, %TickFn%, Off
    PPT_SpacingLog("repeat_stop"
        , "axis=" . PPT_SpacingState.Axis . " key=" . PPT_SpacingState.KeyToWatch . " final_step=" . Round(PPT_SpacingState.CurrentStep, 3))
    PPT_SpacingState.IsRunning := false
    PPT_SpacingState.CurrentStep := PPT_SpacingState.StepSize
    PPT_SpacingState.DelayPending := false
}

; グリッド配置のリピート用
PPT_GridRepeatStart(axis, watchKey) {
    global PPT_SpacingState
    static TickFn := Func("PPT_GridRepeatTick")

    ; 即座に1回実行
    if (axis = "H")
        PPT_GridDistributeH()
    else
        PPT_GridDistributeV()

    PPT_SpacingState.Axis := axis
    PPT_SpacingState.KeyToWatch := watchKey
    PPT_SpacingState.IsRunning := true
    SetTimer, %TickFn%, 200
}

PPT_GridRepeatTick() {
    global PPT_SpacingState

    if !GetKeyState(PPT_SpacingState.KeyToWatch, "P") {
        PPT_GridRepeatStop()
        return
    }

    if (PPT_SpacingState.Axis = "H")
        PPT_GridDistributeH()
    else
        PPT_GridDistributeV()
}

PPT_GridRepeatStop() {
    global PPT_SpacingState
    static TickFn := Func("PPT_GridRepeatTick")

    SetTimer, %TickFn%, Off
    PPT_SpacingState.IsRunning := false
}

; ============================================================================
;  ユーティリティ
; ============================================================================
SetWidthCm(cm) {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Width := cm * 28.3464567
}
SetHeightCm(cm) {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Height := cm * 28.3464567
}
ShowSizeCm() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        w := Round(shp.Width / 28.3464567, 2)
        h := Round(shp.Height / 28.3464567, 2)
        ToolTip, % w . " cm x " . h . " cm"
        SetTimer, CloseToolTip, -2000
    } catch {
    }
}

; ============================================================================
;  デバッグ: お使いの Office で有効な idMso を調査する
;  main.ahk の PowerPoint セクションに一時的に追加して使用:
;    ^+!d::PPT_DiagnoseMso()
; ============================================================================
PPT_DiagnoseMso() {
    app := PPT_GetApp()
    if !app {
        MsgBox, PPT not found
        return
    }

    candidates := ["PasteTextOnly", "PasteAsText", "PasteSpecialDialog"
        , "ShapeOutlineColorPicker", "OutlineColorPicker"
        , "ShapeOutlineWeightPicker", "OutlineWeightGallery"
        , "ShapeOutlineWeightMoreLinesDialog"
        , "ObjectSizeAndPositionDialog", "ObjectFormatDialog"]

    result := "idMso Diagnostic Results:`n`n"
    for _, id in candidates {
        try {
            app.CommandBars.GetEnabledMso(id)
            result .= "[OK] " . id . "`n"
        } catch e {
            result .= "[NG] " . id . " - " . e.Message . "`n"
        }
    }
    MsgBox, % result
}

; ----------------------------------------------------------------------------
;  Phase 1: CF_HDROP から画像パスリストを取得（GlobalLock修正版）
; ----------------------------------------------------------------------------
GetClipboardImagePaths() {
    result := []
    if !DllCall("IsClipboardFormatAvailable", "uint", 15)
        return result
    if !DllCall("OpenClipboard", "ptr", 0)
        return result

    hDrop := DllCall("GetClipboardData", "uint", 15, "ptr")
    if !hDrop {
        DllCall("CloseClipboard")
        return result
    }

    ; GlobalLock でメモリを確保してからDragQueryFileWに渡す
    pDrop := DllCall("GlobalLock", "ptr", hDrop, "ptr")
    if !pDrop {
        DllCall("CloseClipboard")
        return result
    }

    count := DllCall("shell32\DragQueryFileW"
        , "ptr", pDrop, "uint", 0xFFFFFFFF, "ptr", 0, "uint", 0)

    Loop % count {
        VarSetCapacity(buf, 1024, 0)
        DllCall("shell32\DragQueryFileW"
            , "ptr", pDrop, "uint", A_Index - 1, "str", buf, "uint", 512)
        f := buf
        SplitPath, f, , , ext
        if RegExMatch(ext, "i)^(" . _PPT_ALL_EXT . ")$")
            result.Push(f)
    }

    DllCall("GlobalUnlock", "ptr", hDrop)
    DllCall("CloseClipboard")
    return result
}

; ----------------------------------------------------------------------------
;  Phase 2: パスリストからCOM経由で画像を挿入・Tags付与
; ----------------------------------------------------------------------------
PPT_InsertImagesWithMetadata(pathArray) {
    app := PPT_GetApp()
    if !app
        return 0
    try {
        sld := app.ActiveWindow.View.Slide
    } catch {
        return 0
    }

    count   := 0
    offsetX := 50
    offsetY := 50

    for i, filePath in pathArray {
        try {
            SplitPath, filePath, , , ext
            if RegExMatch(ext, "i)^(" . _PPT_MEDIA_EXT . ")$") {
                shp := sld.Shapes.AddMediaObject2(filePath
                    , 0, -1, offsetX, offsetY)
            } else {
                shp := sld.Shapes.AddPicture(filePath
                    , 0, -1, offsetX, offsetY, -1, -1)
            }
            SplitPath, filePath, srcFileName
            FormatTime, insertTime,, yyyy/MM/dd HH:mm:ss
            FormatTime, idTime,, yyyyMMdd-HHmmss
            Random, idRand, 0x100000, 0xFFFFFF
            mediaId := idTime . "-" . Format("{:06x}", idRand)
            shp.Tags.Add("MEDIA_ID", mediaId)
            shp.Tags.Add("SOURCE_PATH", filePath)
            shp.Tags.Add("SOURCE_NAME", srcFileName)
            shp.Tags.Add("INSERT_DATE", insertTime)
            shp.Tags.Add("INSERTED_BY", A_UserName . "@" . A_ComputerName)
            shp.AlternativeText := "[source] " . filePath
            offsetX += 20
            offsetY += 20
            count++
        } catch e {
            MsgBox, 16, PPT Insert Error, % "File: " . filePath . "`n" . e.Message
        }
    }
    return count
}

; ----------------------------------------------------------------------------
;  Phase 3: Ctrl+V / F15 フック本体
; ----------------------------------------------------------------------------
PasteImageWithMetadata() {
    paths := GetClipboardImagePaths()
    if (paths.MaxIndex() = "") {
        Send ^v
        return
    }
    count := PPT_InsertImagesWithMetadata(paths)
    if (count > 0) {
        ToolTip, % count . " 枚挿入・パス記録済み"
        SetTimer, CloseToolTip, -2000
    } else {
        Send ^v
    }
}

; ----------------------------------------------------------------------------
;  Phase 4: メタデータ確認
; ----------------------------------------------------------------------------
PPT_ShowSourcePath() {
    app := PPT_GetApp()
    if !app
        return
    try {
        sel := app.ActiveWindow.Selection
        if (sel.Type != 2) {
            MsgBox, 48, , 図を選択してください。
            return
        }
        shp     := sel.ShapeRange(1)
        mediaId := shp.Tags("MEDIA_ID")
        srcPath := shp.Tags("SOURCE_PATH")
        srcName := shp.Tags("SOURCE_NAME")
        insDate := shp.Tags("INSERT_DATE")
        insBy   := shp.Tags("INSERTED_BY")
        if (srcPath != "") {
            info := "ID:       " . mediaId
                . "`nFile:     " . srcName
                . "`nSource: " . srcPath
                . "`nDate:    " . insDate
                . "`nBy:       " . insBy
            MsgBox, 64, 図のソース情報, %info%
        } else {
            MsgBox, 48, , このマクロ経由で挿入されていない図です。
        }
    } catch {
    }
}

; ----------------------------------------------------------------------------
;  Phase 5 helpers: エクスポート判定 / 実行ユーザ判定
; ----------------------------------------------------------------------------
PPT_GetCurrentUserKey() {
    return A_UserName . "@" . A_ComputerName
}

PPT_IsExportedStatus(status) {
    return (status = "copied" || status = "manual")
}

PPT_LoadExportedIds(manifestPath) {
    exportedIds := {}
    if !FileExist(manifestPath)
        return exportedIds

    FileRead, existingJson, %manifestPath%
    pos := 1
    while (pos := RegExMatch(existingJson
        , "\{[^{}]*""media_id"":\s*""([^""]+)""[^{}]*""status"":\s*""([^""]+)""[^{}]*\}"
        , m, pos)) {
        if PPT_IsExportedStatus(m2)
            exportedIds[m1] := true
        pos += StrLen(m)
    }
    return exportedIds
}

; ----------------------------------------------------------------------------
;  Phase 5: 一括整理コマンド（For each ループ修正版）
; ----------------------------------------------------------------------------
PPT_ExportSources() {
    app := PPT_GetApp()
    if !app {
        MsgBox, 16, エラー, PowerPoint が見つかりません。
        return
    }
    try {
        prs     := app.ActivePresentation
        pptPath := prs.FullName
    } catch {
        MsgBox, 16, エラー, プレゼンテーションが開かれていません。
        return
    }
    if (pptPath = "") {
        MsgBox, 16, エラー, 先にファイルを保存してください。
        return
    }

    SplitPath, pptPath, , pptDir, , pptBaseName
    destDir := pptDir . "\" . pptBaseName . "_sources"
    if !FileExist(destDir)
        FileCreateDir, %destDir%

    manifestPath := destDir . "\sources_list.json"
    exportedIds := PPT_LoadExportedIds(manifestPath)
    currentUserKey := PPT_GetCurrentUserKey()

    jsonEntries       := []
    copyCount         := 0
    exportedSkipCount := 0
    missingCount      := 0
    foreignSkipCount  := 0
    slideIdx          := 0

    For sld in prs.Slides {
        slideIdx++
        shapeIdx := 0

        For shp in sld.Shapes {
            shapeIdx++
            mediaId := ""
            try {
                mediaId := shp.Tags("MEDIA_ID")
            } catch {
            }
            if (mediaId = "")
                continue

            ; エクスポート済みならスキップ
            if (exportedIds.HasKey(mediaId)) {
                exportedSkipCount++
                continue
            }

            srcPath := ""
            try {
                srcPath := shp.Tags("SOURCE_PATH")
            } catch {
            }
            srcName := ""
            try {
                srcName := shp.Tags("SOURCE_NAME")
            } catch {
            }
            if (srcName = "")
                SplitPath, srcPath, srcName

            insertedBy := ""
            try {
                insertedBy := shp.Tags("INSERTED_BY")
            } catch {
            }

            destName := mediaId . "_" . srcName
            destPath := destDir . "\" . destName

            if FileExist(srcPath) {
                FileCopy, %srcPath%, %destPath%, 1
                jsonEntries.Push(PPT_JsonEntry(mediaId, slideIdx, shapeIdx, srcName, srcPath, destPath, "copied"))
                copyCount++
            } else {
                isForeignSource := (insertedBy != "" && insertedBy != currentUserKey)
                if (isForeignSource) {
                    jsonEntries.Push(PPT_JsonEntry(mediaId, slideIdx, shapeIdx, srcName, srcPath, "", "skipped_foreign"))
                    foreignSkipCount++
                    continue
                }

                MsgBox, 52, ファイルが見つかりません
                    , Slide %slideIdx% / Shape %shapeIdx%`nID: %mediaId%`n`n記録されているパス:`n%srcPath%`n`nファイルを手動で指定しますか？
                IfMsgBox, Yes
                {
                    FileSelectFile, manualPath, 3, , ファイルを選択
                        , メディアファイル (*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif;*.mp4;*.avi;*.wmv;*.mov;*.mkv;*.mp3;*.wav;*.wma;*.m4a;*.m4v;*.webm)
                    if (manualPath != "") {
                        FileCopy, %manualPath%, %destPath%, 1
                        jsonEntries.Push(PPT_JsonEntry(mediaId, slideIdx, shapeIdx, srcName, manualPath, destPath, "manual"))
                        copyCount++
                    } else {
                        jsonEntries.Push(PPT_JsonEntry(mediaId, slideIdx, shapeIdx, srcName, srcPath, "", "skipped"))
                        missingCount++
                    }
                } else {
                    jsonEntries.Push(PPT_JsonEntry(mediaId, slideIdx, shapeIdx, srcName, srcPath, "", "skipped"))
                    missingCount++
                }
            }
        }
    }

    ; sources_list.json 生成（既存エントリ + 新規エントリをマージ）
    FormatTime, genTime,, yyyy/MM/dd HH:mm:ss
    if FileExist(manifestPath) && (jsonEntries.MaxIndex() != "") {
        ; 既存JSONの末尾 ] } の前に新規エントリを追記
        FileRead, existingJson, %manifestPath%
        ; "generated" と閉じ括弧を更新するため、全体を再構築
        existingJson := RegExReplace(existingJson, """generated"":\s*""[^""]*""", """generated"": """ . genTime . """")
        ; 既存の sources 配列の末尾に追加
        insertPos := InStr(existingJson, "]", false, 0)
        if (insertPos > 0) {
            before := SubStr(existingJson, 1, insertPos - 1)
            after  := SubStr(existingJson, insertPos)
            ; 既存エントリがあるかチェック（カンマ要否）
            needComma := RegExMatch(RTrim(before), "\}$")
            newLines := ""
            for idx, entry in jsonEntries {
                if (idx = 1 && needComma)
                    newLines .= ",`n"
                else if (idx > 1)
                    newLines .= ",`n"
                newLines .= "    " . entry
            }
            newLines .= "`n"
            existingJson := before . newLines . after
        }
        FileDelete, %manifestPath%
        FileAppend, %existingJson%, %manifestPath%, UTF-8
    } else if (jsonEntries.MaxIndex() != "") {
        ; 新規作成
        FileDelete, %manifestPath%
        json := "{`n"
            . "  ""generated"": """ . genTime . """,`n"
            . "  ""pptx"": """ . PPT_JsonEscape(pptPath) . """,`n"
            . "  ""exported_by"": """ . A_UserName . "@" . A_ComputerName . """,`n"
            . "  ""sources"": [`n"
        for idx, entry in jsonEntries {
            json .= "    " . entry
            json .= (idx < jsonEntries.MaxIndex()) ? ",`n" : "`n"
        }
        json .= "  ]`n}`n"
        FileAppend, %json%, %manifestPath%, UTF-8
    }

    ; pptx 上書き保存
    try {
        prs.Save()
    } catch {
        MsgBox, 48, 警告, pptxの保存に失敗しました。手動で保存してください。
    }

    msg := copyCount . " 枚をコピーしました。"
    if (exportedSkipCount > 0)
        msg .= "`n" . exportedSkipCount . " 枚はエクスポート済みのためスキップ。"
    if (foreignSkipCount > 0)
        msg .= "`n" . foreignSkipCount . " 枚は別ユーザ/別PCのソースのため手動指定せずスキップ。"
    if (missingCount > 0)
        msg .= "`n※ " . missingCount . " 枚はファイル未発見（sources_list.jsonを確認）。"
    if (copyCount = 0 && exportedSkipCount > 0 && missingCount = 0 && foreignSkipCount = 0)
        msg := "新規エクスポート対象はありません。`n(" . exportedSkipCount . " 枚はエクスポート済み)"
    MsgBox, 64, 整理完了, %msg%`n`n%destDir%
}

PPT_JsonEscape(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, """", "\""")
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    return str
}

PPT_JsonEntry(mediaId, slide, shape, file, source, dest, status) {
    return "{""media_id"": """ . mediaId . """"
        . ", ""slide"": " . slide
        . ", ""shape"": " . shape
        . ", ""file"": """ . PPT_JsonEscape(file) . """"
        . ", ""source"": """ . PPT_JsonEscape(source) . """"
        . ", ""dest"": """ . PPT_JsonEscape(dest) . """"
        . ", ""status"": """ . status . """}"
}
