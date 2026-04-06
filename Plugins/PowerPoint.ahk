; ============================================================================
; PowerPoint.ahk - COM + UIA ハイブリッド構成
; ============================================================================
global _PPT_IMG_EXT                      := "png|jpg|jpeg|bmp|tif|tiff|gif|svg|emf|wmf|eps|ai"
global _PPT_MEDIA_EXT                    := "mp4|avi|wmv|mov|mkv|mp3|wav|wma|m4a|m4v|webm"
global _PPT_ALL_EXT                      := _PPT_IMG_EXT . "|" . _PPT_MEDIA_EXT
global PPT_SpacingLogEnabled             := true
global PPT_SpacingLogDir                 := A_ScriptDir . "\.claude"
global PPT_SpacingLogPath                := PPT_SpacingLogDir . "\powerpoint_spacing_debug.log"
global PPT_SpacingLogMaxBytes            := 262144
global PPT_CaptionLogEnabled             := true
global PPT_CaptionLogPath                := PPT_SpacingLogDir . "\powerpoint_caption_debug.log"
global PPT_CaptionLogMaxBytes            := 262144
global PPT_CaptionConfigPath             := PPT_SpacingLogDir . "\powerpoint_caption.ini"
global PPT_CaptionVisualGapHorizontal    := 0.5
global PPT_CaptionVisualGapVertical      := 2.5
global PPT_CaptionPresetIndex            := 2
global PPT_CaptionPresets                := []
PPT_CaptionPresets.Push({Name: "10pt", FontSize: 10, Thickness: 18, MarginLeft: 0, MarginTop: 0, MarginRight: 0, MarginBottom: 0})
PPT_CaptionPresets.Push({Name: "12pt", FontSize: 12, Thickness: 20, MarginLeft: 0, MarginTop: 0, MarginRight: 0, MarginBottom: 0})
PPT_CaptionPresets.Push({Name: "14pt", FontSize: 14, Thickness: 22, MarginLeft: 0, MarginTop: 0, MarginRight: 0, MarginBottom: 0})
PPT_CaptionPresets.Push({Name: "16pt", FontSize: 16, Thickness: 24, MarginLeft: 0, MarginTop: 0, MarginRight: 0, MarginBottom: 0})
global PPT_SpacingEpsilon                := 0.05

; ============================================================================
;  COM ヘルパー
; ============================================================================
PPT_GetApp() {
    try {
        return ComObjActive("PowerPoint.Application")
    } catch e {
        Debug_LogCatch("PPT_Spacing", "get_app_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "align_relto_count_error", e)
    }
    return 0
}

PPT_SetLeft() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(0, PPT_AlignRelTo(shp))
}
PPT_SetRight() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(2, PPT_AlignRelTo(shp))
}
PPT_SetTop() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(3, PPT_AlignRelTo(shp))
}
PPT_SetBottom() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(5, PPT_AlignRelTo(shp))
}
PPT_SetHorizontalCenter() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(1, PPT_AlignRelTo(shp))
}
PPT_SetVerticalCenter() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Align(4, PPT_AlignRelTo(shp))
}
PPT_SetHorizontalSpacer() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Distribute(0, 0)
}
PPT_SetVerticalSpace() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Distribute(1, 0)
}

; ============================================================================
;  グループ化 / 解除
; ============================================================================
PPT_GroupSet() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        newShp := shp.Group()
        newShp.Select()
    } catch e {
        Debug_LogCatch("PPT_Spacing", "group_set_error", e)
    }
}
PPT_GroupRelease() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        newRange := shp.Ungroup()
        newRange.Select()
    } catch e {
        Debug_LogCatch("PPT_Spacing", "group_release_error", e)
    }
}

; ============================================================================
;  前面 / 背面
; ============================================================================
PPT_SetFront() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        shp.ZOrder(0)
        shp.Select()
    } catch e {
        Debug_LogCatch("PPT_Spacing", "set_front_error", e)
    }
}
PPT_SetBack() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        shp.ZOrder(1)
        shp.Select()
    } catch e {
        Debug_LogCatch("PPT_Spacing", "set_back_error", e)
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
        } catch e {
            Debug_LogCatch("PPT_Spacing", "execute_mso_error", e)
        }
    }
    ; 全 idMso が失敗 → キーチップにフォールバック
    if (fallbackKeys != "") {
        Send, %fallbackKeys%
        return true
    }
    return false
}

PPT_SetFrameLine() {
    PPT_TryExecuteMso(["ShapeOutlineColorPicker", "OutlineColorPicker"]
        , "!jpsow{Home}{Down}{Enter}")
}

PPT_SetFrameSize() {
    PPT_TryExecuteMso(["OutlineWeightGallery", "ShapeOutlineWeightPicker"
        , "ShapeOutlineWeightMoreLinesDialog"], "!jpw")
}

; 黒枠線サイクル: 枠線なし → 0.25pt → 0.5pt → 枠線なし ...
PPT_CycleBlackBorder() {
    app := PPT_GetApp()
    if !app
        return
    try {
        sel := app.ActiveWindow.Selection
        if (sel.Type != 2)
            return
        ; グループ内の子図形が選択されている場合は ChildShapeRange を使用
        shp := ""
        try shp := sel.ChildShapeRange
        if !shp || (shp.Count = 0)
            shp := sel.ShapeRange
        if !shp
            return
    } catch e {
        Debug_LogCatch("PPT_Spacing", "cycle_border_selection_error", e)
        return
    }

    try {
        line := shp.Item(1).Line
        isVisible := line.Visible
        weight := line.Weight

        ; 現在の状態を判定してサイクル
        if (isVisible = 0) {
            ; 枠線なし → 黒 0.25pt
            PPT_SetBorder(shp, true, 0, 0.25)
            ToolTip, 枠線: 黒 0.25pt
        } else if (weight < 0.3) {
            ; 0.25pt → 0.5pt
            PPT_SetBorder(shp, true, 0, 0.5)
            ToolTip, 枠線: 黒 0.5pt
        } else {
            ; 0.5pt → なし
            PPT_SetBorder(shp, false, 0, 0)
            ToolTip, 枠線: なし
        }
        SetTimer, CloseToolTip, -1500
    } catch e {
        Debug_LogCatch("PPT_Spacing", "cycle_border_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "set_border_error", e)
    }
}

; ============================================================================
;  書式設定パネルを開く / テキストのみ貼り付け
; ============================================================================
PPT_OpenFormatObject() {
    panelHwnd := ""
    panel := PPT_DetectFormatPanel(panelHwnd)
    if (panel) {
        if !PPT_CloseFormatPanel(panel, panelHwnd) {
            ToolTip, 図形の書式設定: 閉じられません
            SetTimer, CloseToolTip, -1500
        }
        return
    }
    PPT_TryExecuteMso(["ObjectSizeAndPositionDialog"])
}

PPT_CloseFormatObject() {
    panelHwnd := ""
    panel := PPT_DetectFormatPanel(panelHwnd)
    if !panel {
        ToolTip, 図形の書式設定: 開いていません
        SetTimer, CloseToolTip, -1500
        return false
    }

    closed := PPT_CloseFormatPanel(panel, panelHwnd)
    if (closed)
        ToolTip, 図形の書式設定: 閉じました
    else
        ToolTip, 図形の書式設定: 閉じられません
    SetTimer, CloseToolTip, -1500
    return closed
}

PPT_GetWindowHandles() {
    handles := []
    WinGet, hwndList, List, ahk_exe POWERPNT.EXE
    Loop % hwndList {
        hwnd := hwndList%A_Index%
        if hwnd
            handles.Push(hwnd)
    }
    return handles
}

PPT_FindFormatPanelInRoot(rootEl, uia) {
    panelNames := ["Format Shape", "Format Picture", "Size and Properties"
        , "図形の書式設定", "図の書式設定", "サイズとプロパティ"]
    for _, n in panelNames {
        try {
            cond := uia.CreatePropertyCondition(30005, n)  ; NamePropertyId
            found := rootEl.FindFirst(cond, 0x4)  ; Descendants
            if found
                return found
        } catch e {
            Debug_LogCatch("PPT_Spacing", "find_format_panel_error", e)
        }
    }
    try {
        return FindElementByKeyword(rootEl, panelNames)
    } catch e {
        Debug_LogCatch("PPT_Spacing", "find_format_panel_keyword_error", e)
    }
    return ""
}

PPT_GetElementRect(el) {
    try br := el.CurrentBoundingRectangle
    catch
        return ""
    if !IsObject(br)
        return ""
    return {l: br.l + 0
        , t: br.t + 0
        , r: br.r + 0
        , b: br.b + 0
        , w: (br.r - br.l) + 0
        , h: (br.b - br.t) + 0}
}

PPT_IsElementRectValid(rect, minSize := 1) {
    return IsObject(rect) && (rect.w >= minSize) && (rect.h >= minSize)
}

PPT_DescribeUiElement(el) {
    rectText := "rect=NA"
    name := ""
    aid := ""
    hwnd := ""
    rect := PPT_GetElementRect(el)
    if PPT_IsElementRectValid(rect)
        rectText := "rect=(" . Round(rect.l, 1) . "," . Round(rect.t, 1) . "," . Round(rect.w, 1) . "," . Round(rect.h, 1) . ")"
    try name := el.CurrentName
    try aid := el.CurrentAutomationId
    try hwnd := el.CurrentNativeWindowHandle
    return "name=" . PPT_SpacingSanitize(name)
        . ",aid=" . PPT_SpacingSanitize(aid)
        . ",hwnd=" . hwnd
        . "," . rectText
}

PPT_FindFormatCloseButton(panel, panelHwnd := "") {
    uia := UIA_Interface()
    if !uia
        return ""

    panelRect := PPT_GetElementRect(panel)
    if !PPT_IsElementRectValid(panelRect, 10)
        return ""

    roots := [panel]
    try {
        parent := uia.TreeWalkerTrue.GetParentElement(panel)
        if parent
            roots.Push(parent)
    } catch e {
        Debug_LogCatch("PPT_Spacing", "find_close_parent_error", e)
    }
    if panelHwnd {
        try {
            rootEl := uia.ElementFromHandle(panelHwnd)
            if rootEl
                roots.Push(rootEl)
        } catch e {
            Debug_LogCatch("PPT_Spacing", "find_close_hwnd_error", e)
        }
    }

    bestButton := ""
    bestScore := -1000000
    for _, root in roots {
        try {
            btnCond := uia.CreatePropertyCondition(uia.ControlTypePropertyId, uia.ButtonControlTypeId)
            buttons := root.FindAll(btnCond, 0x4)
            if !buttons
                continue

            Loop % buttons.MaxIndex() {
                btn := buttons[A_Index]
                rect := PPT_GetElementRect(btn)
                if !PPT_IsElementRectValid(rect, 8)
                    continue

                centerX := rect.l + (rect.w / 2)
                centerY := rect.t + (rect.h / 2)
                if (centerX < panelRect.r - 180)
                    continue
                if (centerX > panelRect.r + 60)
                    continue
                if (centerY < panelRect.t - 40)
                    continue
                if (centerY > panelRect.t + 90)
                    continue

                name := ""
                aid := ""
                try name := btn.CurrentName
                try aid := btn.CurrentAutomationId

                score := 0
                if (InStr(name, "Close") || InStr(name, "閉じる"))
                    score += 10000
                if (InStr(aid, "Close") || InStr(aid, "close"))
                    score += 5000
                score -= Abs(centerX - panelRect.r)
                score -= Abs(centerY - panelRect.t)
                score -= Abs(rect.w - 24)
                score -= Abs(rect.h - 24)

                if (score > bestScore) {
                    bestScore := score
                    bestButton := btn
                }
            }
        } catch e {
            Debug_LogCatch("PPT_Spacing", "find_close_button_error", e)
        }
    }

    if bestButton
        PPT_SpacingLog("format_close_button_candidate"
            , "panel=" . PPT_DescribeUiElement(panel)
            . " button=" . PPT_DescribeUiElement(bestButton)
            . " score=" . Round(bestScore, 1))
    return bestButton
}

PPT_TryActivateCloseButton(btn) {
    try {
        btn.Invoke()
        return true
    } catch e {
        Debug_LogCatch("PPT_Spacing", "close_invoke_error", e)
    }
    try {
        btn.Click("left")
        return true
    } catch e {
        Debug_LogCatch("PPT_Spacing", "close_click_error", e)
    }
    try {
        btn.GetCurrentPatternAs("LegacyIAccessible").DoDefaultAction()
        return true
    } catch e {
        Debug_LogCatch("PPT_Spacing", "close_legacy_error", e)
    }
    return false
}

PPT_TryCloseFormatPanelWindow(panel, panelHwnd := "") {
    uia := UIA_Interface()
    if !uia || !panel
        return false

    appW := 0, appH := 0
    if panelHwnd
        WinGetPos, , , appW, appH, ahk_id %panelHwnd%

    current := panel
    Loop 3 {
        if !current
            break

        rect := PPT_GetElementRect(current)
        tooLarge := false
        if (panelHwnd && PPT_IsElementRectValid(rect, 10))
            tooLarge := (rect.w >= appW * 0.9) && (rect.h >= appH * 0.9)

        if !tooLarge {
            try {
                windowPattern := current.GetCurrentPatternAs("Window")
                if IsObject(windowPattern) {
                    windowPattern.Close()
                    Sleep, 150
                    if !PPT_DetectFormatPanel() {
                        PPT_SpacingLog("format_close_window_pattern", "target=" . PPT_DescribeUiElement(current))
                        return true
                    }
                }
            } catch e {
                Debug_LogCatch("PPT_Spacing", "close_walk_window_error", e)
            }

            nativeHwnd := ""
            try nativeHwnd := current.CurrentNativeWindowHandle
            catch e {
                Debug_LogCatch("PPT_Spacing", "close_walk_hwnd_error", e)
            }
            if (nativeHwnd && nativeHwnd != panelHwnd) {
                WinClose, ahk_id %nativeHwnd%
                Sleep, 150
                if !PPT_DetectFormatPanel() {
                    PPT_SpacingLog("format_close_native_hwnd", "target=" . PPT_DescribeUiElement(current))
                    return true
                }
            }
        }

        nextCurrent := ""
        try nextCurrent := uia.TreeWalkerTrue.GetParentElement(current)
        catch e {
            Debug_LogCatch("PPT_Spacing", "close_walk_parent_error", e)
        }
        current := nextCurrent
    }
    return false
}

PPT_DetectFormatPanel(ByRef panelHwnd := "") {
    panelHwnd := ""
    handles := PPT_GetWindowHandles()
    if !IsObject(handles) || (handles.MaxIndex() = "")
        return ""
    uia := UIA_Interface()
    if !uia
        return ""

    for _, hwnd in handles {
        try {
            rootEl := uia.ElementFromHandle(hwnd)
            if !rootEl
                continue
            found := PPT_FindFormatPanelInRoot(rootEl, uia)
            if found
            {
                panelHwnd := hwnd
                return found
            }
        } catch e {
            Debug_LogCatch("PPT_Spacing", "detect_panel_error", e)
        }
    }
    return ""
}

PPT_CloseFormatPanel(panel := "", panelHwnd := "") {
    if !panel {
        panel := PPT_DetectFormatPanel(panelHwnd)
        if !panel
            return false
    }

    activeHwnd := panelHwnd
    if !activeHwnd
        activeHwnd := WinExist("ahk_exe POWERPNT.EXE")
    if activeHwnd {
        WinActivate, ahk_id %activeHwnd%
        WinWaitActive, ahk_id %activeHwnd%,, 1
    }

    PPT_SpacingLog("format_close_start", "panel=" . PPT_DescribeUiElement(panel))

    ; 1) パネル右上の Close ボタン
    btn := PPT_FindFormatCloseButton(panel, panelHwnd)
    if btn {
        if PPT_TryActivateCloseButton(btn) {
            Sleep, 150
            if !PPT_DetectFormatPanel() {
                PPT_SpacingLog("format_close_button_ok", "button=" . PPT_DescribeUiElement(btn))
                return true
            }
        }
        PPT_SpacingLog("format_close_button_failed", "button=" . PPT_DescribeUiElement(btn))
    }

    ; 2) WindowPattern / child window close
    if PPT_TryCloseFormatPanelWindow(panel, panelHwnd)
        return true

    ; 3) パネルにフォーカスして Esc
    try {
        panel.SetFocus()
        Sleep, 50
    } catch e {
        Debug_LogCatch("PPT_Spacing", "close_panel_setfocus_error", e)
    }
    Send, {Esc}
    Sleep, 150
    if !PPT_DetectFormatPanel() {
        PPT_SpacingLog("format_close_esc_ok", "panel=" . PPT_DescribeUiElement(panel))
        return true
    }
    PPT_SpacingLog("format_close_fail", "panel=" . PPT_DescribeUiElement(panel))
    return false
}

PPT_PasteTextOnly() {
    PPT_TryExecuteMso(["PasteTextOnly", "PasteAsText"])
}

; ============================================================================
;  UIA層: 書式設定パネル内の SpinBox フォーカス
; ============================================================================
PPT_GetFormatPanel() {
    return PPT_DetectFormatPanel()
}

PPT_FocusPanelField(keywords, excludeKeywords := "") {
    PPT_OpenFormatObject()
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
        } catch e {
            Debug_LogCatch("PPT_Spacing", "focus_panel_setfocus_error", e)
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
            } catch e {
                Debug_LogCatch("PPT_Spacing", "focus_panel_edit_error", e)
            }
        }
    }
    return false
}

PPT_FocusWidthField() {
    PPT_FocusRibbonSizeField(["Width", "幅"], ["Height", "高さ"])
}

; リボンの書式タブをUIA経由でアクティブにし、サイズ系スピンボックスにフォーカス
PPT_FocusRibbonSizeField(keywords, excludeKeywords := "") {
    hwnd := WinExist("ahk_exe POWERPNT.EXE")
    if !hwnd
        return false
    uia := UIA_Interface()
    if !uia
        return false
    rootEl := uia.ElementFromHandle(hwnd)
    if !rootEl
        return false

    ; Step 1: コンテキストタブ（図形の書式 / 図の形式 等）を選択
    tabNames := ["図形の書式", "図の形式", "Shape Format", "Picture Format"
        , "ビデオの書式", "オーディオの書式", "Video Format", "Audio Format"]
    for _, tName in tabNames {
        cond := uia.CreatePropertyCondition(30005, tName)  ; NamePropertyId
        tab := rootEl.FindFirst(cond, 0x4)
        if tab {
            try tab.Invoke()
            catch e {
                Debug_LogCatch("PPT_Spacing", "focus_ribbon_invoke_error", e)
                try tab.GetCurrentPatternAs("LegacyIAccessible").DoDefaultAction()
                catch e {
                    Debug_LogCatch("PPT_Spacing", "focus_ribbon_legacy_error", e)
                    try tab.SetFocus()
                }
            }
            Sleep, 200
            break
        }
    }

    ; Step 2: 幅スピンボックスを探してフォーカス
    el := FindElementByKeyword(rootEl, keywords, excludeKeywords)
    if el {
        try {
            el.SetFocus()
            return true
        } catch e {
            Debug_LogCatch("PPT_Spacing", "focus_ribbon_setfocus_error", e)
        }
    }
    return false
}
PPT_FocusHeightField() {
    PPT_FocusPanelField(["Height", "高さ"], ["Width", "幅"])
}
PPT_FocusRotationField() {
    PPT_FocusPanelField(["Rotation", "回転"])
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "get_slide_size_error", e)
    }
    return ""
}

PPT_CollectShapes(shapeRange) {
    arr := []
    try {
        Loop % shapeRange.Count {
            s := shapeRange.Item(A_Index)
            left := s.Left
            top := s.Top
            w := s.Width
            h := s.Height
            arr.Push({ref: s
                , id: s.Id
                , name: s.Name
                , left: left
                , top: top
                , w: w
                , h: h
                , right: left + w
                , bottom: top + h
                , centerX: left + (w / 2)
                , centerY: top + (h / 2)})
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

PPT_DebugInit() {
    global PPT_SpacingLogEnabled, PPT_SpacingLogPath, PPT_SpacingLogMaxBytes
    global PPT_CaptionLogEnabled, PPT_CaptionLogPath, PPT_CaptionLogMaxBytes

    Debug_CreateChannel("PPT_Spacing", PPT_SpacingLogPath, PPT_SpacingLogMaxBytes, PPT_SpacingLogEnabled)
    Debug_CreateChannel("PPT_Caption", PPT_CaptionLogPath, PPT_CaptionLogMaxBytes, PPT_CaptionLogEnabled)
    Debug_Log("PPT_Spacing", "startup", "script=" . A_ScriptFullPath)
}

PPT_SpacingSanitize(text) {
    return Debug_Sanitize(text)
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
    Debug_Log("PPT_Spacing", event, extra)
}

PPT_SpacingOpenLog() {
    Debug_OpenLog("PPT_Spacing")
}

PPT_CaptionLog(event, extra := "") {
    Debug_Log("PPT_Caption", event, extra)
}

PPT_CaptionOpenLog() {
    Debug_OpenLog("PPT_Caption")
}

PPT_CaptionFormatSettingValue(value) {
    if (value = "")
        return ""
    return RegExReplace(RTrim(RTrim(Format("{:.2f}", value), "0"), "."), "\.$", "")
}

PPT_CaptionTryParseGapValue(value, ByRef parsedValue) {
    value := Trim(value)
    if (value = "")
        return false
    if !RegExMatch(value, "^-?\d+(\.\d+)?$")
        return false
    parsedValue := value + 0
    return true
}

PPT_CaptionNormalizeGapValue(value) {
    value := Round(value + 0, 2)
    if (value < 0)
        value := 0
    if (value > 20)
        value := 20
    return value
}

PPT_CaptionNormalizePresetIndex(value, fallback := 2) {
    global PPT_CaptionPresets

    maxIndex := PPT_CaptionPresets.MaxIndex()
    if (fallback < 1 || fallback > maxIndex)
        fallback := 2

    if (value = "" || value = "ERROR" || value = "__MISSING__")
        return fallback

    value := Floor(value + 0)
    if (value < 1 || value > maxIndex)
        return fallback
    return value
}

PPT_GetCaptionPreset() {
    global PPT_CaptionPresets, PPT_CaptionPresetIndex

    PPT_CaptionPresetIndex := PPT_CaptionNormalizePresetIndex(PPT_CaptionPresetIndex, 2)
    return PPT_CaptionPresets[PPT_CaptionPresetIndex]
}

PPT_CaptionShowPresetStatus(prefix := "Caption preset") {
    preset := PPT_GetCaptionPreset()

    ToolTip, % prefix . ": " . preset.Name
    SetTimer, CloseToolTip, -1500
}

PPT_CycleCaptionPreset() {
    global PPT_CaptionPresetIndex, PPT_CaptionPresets

    PPT_CaptionPresetIndex := PPT_CaptionNormalizePresetIndex(PPT_CaptionPresetIndex, 2) + 1
    if (PPT_CaptionPresetIndex > PPT_CaptionPresets.MaxIndex())
        PPT_CaptionPresetIndex := 1

    PPT_CaptionSaveConfig()
    preset := PPT_GetCaptionPreset()
    PPT_CaptionLog("caption_preset_cycle", "preset=" . preset.Name)
    PPT_CaptionShowPresetStatus()
}

PPT_CaptionSaveConfig() {
    global PPT_CaptionConfigPath, PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical
    global PPT_CaptionPresetIndex
    global SUI_ConfigPath

    configPath := ""
    if (SUI_ConfigPath != "") {
        configPath := SUI_ConfigPath
        if IsFunc("SUI_EnsureConfigPath")
            SUI_EnsureConfigPath()
    } else {
        Debug_EnsureDir(A_ScriptDir . "\.claude")
        configPath := PPT_CaptionConfigPath
    }

    IniWrite, % PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapHorizontal), %configPath%, PowerPoint, CaptionHorizontalGap
    IniWrite, % PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapVertical), %configPath%, PowerPoint, CaptionVerticalGap
    IniWrite, % PPT_CaptionNormalizePresetIndex(PPT_CaptionPresetIndex, 2), %configPath%, PowerPoint, CaptionPresetIndex
}

PPT_CaptionInit() {
    global PPT_CaptionConfigPath, PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical
    global PPT_CaptionPresetIndex
    global SUI_ConfigPath

    horizontalGapRaw := "__MISSING__"
    verticalGapRaw := "__MISSING__"
    presetIndexRaw := "__MISSING__"
    usedLegacyConfig := false

    if (SUI_ConfigPath != "") {
        if IsFunc("SUI_EnsureConfigPath")
            SUI_EnsureConfigPath()
        IniRead, horizontalGapRaw, %SUI_ConfigPath%, PowerPoint, CaptionHorizontalGap, __MISSING__
        IniRead, verticalGapRaw, %SUI_ConfigPath%, PowerPoint, CaptionVerticalGap, __MISSING__
        IniRead, presetIndexRaw, %SUI_ConfigPath%, PowerPoint, CaptionPresetIndex, __MISSING__
    }

    if (horizontalGapRaw = "__MISSING__" || verticalGapRaw = "__MISSING__" || presetIndexRaw = "__MISSING__") {
        Debug_EnsureDir(A_ScriptDir . "\.claude")
        IniRead, legacyHorizontalGapRaw, %PPT_CaptionConfigPath%, Caption, HorizontalGap, % PPT_CaptionVisualGapHorizontal
        IniRead, legacyVerticalGapRaw, %PPT_CaptionConfigPath%, Caption, VerticalGap, % PPT_CaptionVisualGapVertical
        IniRead, legacyPresetIndexRaw, %PPT_CaptionConfigPath%, PowerPoint, CaptionPresetIndex, %PPT_CaptionPresetIndex%
        usedLegacyConfig := true

        if (horizontalGapRaw = "__MISSING__")
            horizontalGapRaw := legacyHorizontalGapRaw
        if (verticalGapRaw = "__MISSING__")
            verticalGapRaw := legacyVerticalGapRaw
        if (presetIndexRaw = "__MISSING__")
            presetIndexRaw := legacyPresetIndexRaw
    }

    if PPT_CaptionTryParseGapValue(horizontalGapRaw, horizontalGap)
        PPT_CaptionVisualGapHorizontal := PPT_CaptionNormalizeGapValue(horizontalGap)
    if PPT_CaptionTryParseGapValue(verticalGapRaw, verticalGap)
        PPT_CaptionVisualGapVertical := PPT_CaptionNormalizeGapValue(verticalGap)
    PPT_CaptionPresetIndex := PPT_CaptionNormalizePresetIndex(presetIndexRaw, PPT_CaptionPresetIndex)

    if (SUI_ConfigPath != "" && usedLegacyConfig)
        PPT_CaptionSaveConfig()
}

PPT_CaptionShowGapStatus(prefix := "Caption gap") {
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical

    ToolTip, % prefix . " H=" . PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapHorizontal) . " V=" . PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapVertical)
    SetTimer, CloseToolTip, -1500
}

PPT_CaptionAdjustGap(axis, delta) {
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical

    if (axis = "H")
        PPT_CaptionVisualGapHorizontal := PPT_CaptionNormalizeGapValue(PPT_CaptionVisualGapHorizontal + delta)
    else
        PPT_CaptionVisualGapVertical := PPT_CaptionNormalizeGapValue(PPT_CaptionVisualGapVertical + delta)

    PPT_CaptionSaveConfig()
    PPT_CaptionShowGapStatus("Caption gap")
}

PPT_CaptionPromptGap(axis) {
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical

    if (axis = "H") {
        currentValue := PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapHorizontal)
        axisLabel := "上下"
    } else {
        currentValue := PPT_CaptionFormatSettingValue(PPT_CaptionVisualGapVertical)
        axisLabel := "左右"
    }

    InputBox, userInput, Caption Gap, % axisLabel . " キャプションの gap(pt) を入力してください。", , 320, 140,,,,, %currentValue%
    if ErrorLevel
        return

    if !PPT_CaptionTryParseGapValue(userInput, parsedValue) {
        MsgBox, 48, Caption Gap, 数値を入力してください。
        return
    }

    parsedValue := PPT_CaptionNormalizeGapValue(parsedValue)
    if (axis = "H")
        PPT_CaptionVisualGapHorizontal := parsedValue
    else
        PPT_CaptionVisualGapVertical := parsedValue

    PPT_CaptionSaveConfig()
    PPT_CaptionShowGapStatus("Caption gap set")
}

PPT_CaptionFormatNumber(value) {
    if (value = "")
        return ""
    return Round(value, 3)
}

PPT_CaptionDescribeRect(rect) {
    if !IsObject(rect)
        return "rect=0"

    return "target=("
        . PPT_CaptionFormatNumber(rect.x) . ","
        . PPT_CaptionFormatNumber(rect.y) . ","
        . PPT_CaptionFormatNumber(rect.w) . ","
        . PPT_CaptionFormatNumber(rect.h) . ")"
        . ",create=("
        . PPT_CaptionFormatNumber(rect.createX) . ","
        . PPT_CaptionFormatNumber(rect.createY) . ","
        . PPT_CaptionFormatNumber(rect.createW) . ","
        . PPT_CaptionFormatNumber(rect.createH) . ")"
        . ",rotation=" . PPT_CaptionFormatNumber(rect.rotation)
        . ",orientation=" . rect.orientation
}

PPT_CaptionDescribeTarget(shape) {
    if !IsObject(shape)
        return "shape=0"

    return "id=" . shape.id
        . ",name=" . PPT_SpacingSanitize(shape.name)
        . ",left=" . PPT_CaptionFormatNumber(shape.left)
        . ",top=" . PPT_CaptionFormatNumber(shape.top)
        . ",right=" . PPT_CaptionFormatNumber(shape.right)
        . ",bottom=" . PPT_CaptionFormatNumber(shape.bottom)
        . ",w=" . PPT_CaptionFormatNumber(shape.w)
        . ",h=" . PPT_CaptionFormatNumber(shape.h)
}

PPT_CaptionDescribeTextBox(shapeRef) {
    textValue := ""
    shapeId := ""
    shapeName := ""
    left := ""
    top := ""
    width := ""
    height := ""
    rotation := ""
    orientation := ""
    marginLeft := ""
    marginTop := ""
    marginRight := ""
    marginBottom := ""
    anchor := ""
    wordWrap := ""
    boundLeft := ""
    boundTop := ""
    boundWidth := ""
    boundHeight := ""
    fontSize := ""
    presetName := ""

    try shapeId := shapeRef.Id
    try shapeName := shapeRef.Name
    try left := shapeRef.Left
    try top := shapeRef.Top
    try width := shapeRef.Width
    try height := shapeRef.Height
    try rotation := shapeRef.Rotation
    try textValue := shapeRef.TextFrame.TextRange.Text
    try orientation := shapeRef.TextFrame.Orientation
    try marginLeft := shapeRef.TextFrame.MarginLeft
    try marginTop := shapeRef.TextFrame.MarginTop
    try marginRight := shapeRef.TextFrame.MarginRight
    try marginBottom := shapeRef.TextFrame.MarginBottom
    try anchor := shapeRef.TextFrame.VerticalAnchor
    try wordWrap := shapeRef.TextFrame.WordWrap
    try fontSize := shapeRef.TextFrame.TextRange.Font.Size
    presetName := PPT_GetShapeTagValue(shapeRef, "AHK_CAPTION_PRESET")
    try {
        textRange := shapeRef.TextFrame.TextRange
        boundLeft := textRange.BoundLeft
        boundTop := textRange.BoundTop
        boundWidth := textRange.BoundWidth
        boundHeight := textRange.BoundHeight
    } catch e {
        Debug_LogCatch("PPT_Caption", "caption_text_bounds_error", e)
    }

    return "id=" . shapeId
        . ",name=" . PPT_SpacingSanitize(shapeName)
        . ",left=" . PPT_CaptionFormatNumber(left)
        . ",top=" . PPT_CaptionFormatNumber(top)
        . ",w=" . PPT_CaptionFormatNumber(width)
        . ",h=" . PPT_CaptionFormatNumber(height)
        . ",rotation=" . PPT_CaptionFormatNumber(rotation)
        . ",orientation=" . orientation
        . ",anchor=" . anchor
        . ",wordWrap=" . wordWrap
        . ",fontSize=" . PPT_CaptionFormatNumber(fontSize)
        . ",preset=" . presetName
        . ",margins=("
        . PPT_CaptionFormatNumber(marginLeft) . ","
        . PPT_CaptionFormatNumber(marginTop) . ","
        . PPT_CaptionFormatNumber(marginRight) . ","
        . PPT_CaptionFormatNumber(marginBottom) . ")"
        . ",textBounds=("
        . PPT_CaptionFormatNumber(boundLeft) . ","
        . PPT_CaptionFormatNumber(boundTop) . ","
        . PPT_CaptionFormatNumber(boundWidth) . ","
        . PPT_CaptionFormatNumber(boundHeight) . ")"
        . ",text=" . PPT_SpacingSanitize(textValue)
}

PPT_GetCaptionTextBounds(shapeRef) {
    try {
        textRange := shapeRef.TextFrame.TextRange
        return {left: textRange.BoundLeft
            , top: textRange.BoundTop
            , w: textRange.BoundWidth
            , h: textRange.BoundHeight}
    } catch e {
        Debug_LogCatch("PPT_Caption", "text_bounds_error", e)
    }
    return ""
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "shape_axis_error", e)
    }
    return ""
}

PPT_MoveShapeAxisBy(shapeRef, axis, delta) {
    if (axis = "H") {
        try {
            shapeRef.IncrementLeft(delta)
            return true
        } catch e {
            Debug_LogCatch("PPT_Spacing", "move_shape_h_error", e)
        }
    } else if (axis = "V") {
        try {
            shapeRef.IncrementTop(delta)
            return true
        } catch e {
            Debug_LogCatch("PPT_Spacing", "move_shape_v_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "align_center_count_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "grid_h_count_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "grid_v_count_error", e)
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
global PPT_SpacingState := PPT_CreateSpacingState()

PPT_CreateSpacingState() {
    return {IsRunning: false
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
}

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
        if (PPT_SpacingDebug >= 2) {
            ToolTip, [DBG] no selection
            SetTimer, CloseToolTip, -1500
        }
        return
    }
    cnt := 0
    try cnt := shp.Count
    if (cnt < 2) {
        PPT_SpacingLog("adjust_too_few_shapes", "axis=" . axis . " direction=" . direction . " count=" . cnt)
        if (PPT_SpacingDebug >= 2) {
            ToolTip, % "[DBG] count=" . cnt
            SetTimer, CloseToolTip, -1500
        }
        return
    }
    slide := PPT_GetSlideSize()
    if !IsObject(slide) {
        PPT_SpacingLog("adjust_no_slide", "axis=" . axis . " direction=" . direction)
        if (PPT_SpacingDebug >= 2) {
            ToolTip, [DBG] no slide size
            SetTimer, CloseToolTip, -1500
        }
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
            if (PPT_SpacingDebug >= 2) {
                ToolTip, % "[DBG] clamp-slide i=" . i . " pos=" . Round(newPositions[i], 1) . " clamped=" . Round(clamped, 1)
                SetTimer, CloseToolTip, -1500
            }
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
            if (PPT_SpacingDebug >= 2) {
                ToolTip, % "[DBG] clamp-overlap i=" . i . " edge=" . Round(rightEdge, 1) . " next=" . Round(newPositions[i + 1], 1)
                SetTimer, CloseToolTip, -1500
            }
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

    if (PPT_SpacingDebug >= 2) {
        ToolTip, % "[DBG] applied " . axis . " dir=" . direction . " step=" . Round(step, 2)
        if !PPT_SpacingState.IsRunning
            SetTimer, CloseToolTip, -1500
    }
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
    ToolTip
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
;  Edge caption text boxes
; ============================================================================
PPT_GetActiveSlide() {
    app := PPT_GetApp()
    if !app
        return ""

    try {
        return app.ActiveWindow.View.Slide
    } catch e {
        Debug_LogCatch("PPT_Caption", "get_active_slide_error", e)
    }
    return ""
}

PPT_CopyShapeList(shapes) {
    copied := []
    if !IsObject(shapes)
        return copied

    for _, s in shapes
        copied.Push(s)
    return copied
}

PPT_GetSelectionLayout(shapes) {
    count := IsObject(shapes) ? shapes.MaxIndex() : 0
    if (count <= 1)
        return "single"

    minCenterX := shapes[1].centerX
    maxCenterX := shapes[1].centerX
    minCenterY := shapes[1].centerY
    maxCenterY := shapes[1].centerY

    for _, s in shapes {
        if (s.centerX < minCenterX)
            minCenterX := s.centerX
        if (s.centerX > maxCenterX)
            maxCenterX := s.centerX
        if (s.centerY < minCenterY)
            minCenterY := s.centerY
        if (s.centerY > maxCenterY)
            maxCenterY := s.centerY
    }

    spanX := maxCenterX - minCenterX
    spanY := maxCenterY - minCenterY

    if (spanX >= spanY * 1.5)
        return "horizontal"
    if (spanY >= spanX * 1.5)
        return "vertical"
    return "mixed"
}

PPT_GetEdgeCaptionTargets(shapes, edge) {
    layout := PPT_GetSelectionLayout(shapes)
    targets := []

    if (layout = "single" || layout = "mixed") {
        ordered := PPT_CopyShapeList(shapes)
        if (edge = "Top" || edge = "Bottom")
            PPT_SortShapesByKey(ordered, "left")
        else
            PPT_SortShapesByKey(ordered, "top")
        return ordered
    }

    if (layout = "horizontal") {
        if (edge = "Top" || edge = "Bottom") {
            ordered := PPT_CopyShapeList(shapes)
            PPT_SortShapesByKey(ordered, "left")
            return ordered
        }

        chosen := shapes[1]
        for _, s in shapes {
            if (edge = "Left" && s.left < chosen.left)
                chosen := s
            else if (edge = "Right" && s.right > chosen.right)
                chosen := s
        }
        targets.Push(chosen)
        return targets
    }

    if (layout = "vertical") {
        if (edge = "Left" || edge = "Right") {
            ordered := PPT_CopyShapeList(shapes)
            PPT_SortShapesByKey(ordered, "top")
            return ordered
        }

        chosen := shapes[1]
        for _, s in shapes {
            if (edge = "Top" && s.top < chosen.top)
                chosen := s
            else if (edge = "Bottom" && s.bottom > chosen.bottom)
                chosen := s
        }
        targets.Push(chosen)
        return targets
    }

    return PPT_CopyShapeList(shapes)
}

PPT_GetCaptionRect(shape, edge, slideSize) {
    preset := PPT_GetCaptionPreset()
    gap := 0
    lineH := preset.Thickness
    x := 0
    y := 0
    w := 0
    h := 0
    createX := 0
    createY := 0
    createW := 0
    createH := 0
    rotation := 0
    orientation := PPT_GetCaptionOrientation(edge)

    if (edge = "Top") {
        x := shape.left
        y := shape.top - gap - lineH
        w := shape.w
        h := lineH
        createX := x
        createY := y
        createW := w
        createH := h
    } else if (edge = "Bottom") {
        x := shape.left
        y := shape.bottom + gap
        w := shape.w
        h := lineH
        createX := x
        createY := y
        createW := w
        createH := h
    } else if (edge = "Left") {
        x := shape.left - gap - lineH
        y := shape.top
        w := lineH
        h := shape.h
        createX := x
        createY := y
        createW := w
        createH := h
    } else {
        x := shape.right + gap
        y := shape.top
        w := lineH
        h := shape.h
        createX := x
        createY := y
        createW := w
        createH := h
    }

    x := PPT_ClampPosition(x, w, slideSize.w)
    y := PPT_ClampPosition(y, h, slideSize.h)
    createX := x
    createY := y
    createW := w
    createH := h

    return {x: x
        , y: y
        , w: w
        , h: h
        , createX: createX
        , createY: createY
        , createW: createW
        , createH: createH
        , orientation: orientation
        , rotation: rotation}
}

PPT_GetCaptionVerticalAnchor(edge) {
    if (edge = "Top")
        return 4
    if (edge = "Bottom")
        return 1
    return 3
}

PPT_GetCaptionOrientation(edge) {
    if (edge = "Left")
        return 2
    if (edge = "Right")
        return 3
    return 1
}

PPT_GetShapeTagValue(shapeRef, tagName) {
    value := ""
    try value := shapeRef.Tags(tagName)
    return value
}

PPT_IsManagedCaption(shapeRef, edge := "", targetId := "") {
    if (PPT_GetShapeTagValue(shapeRef, "AHK_KIND") != "EDGE_CAPTION")
        return false
    if (edge != "" && PPT_GetShapeTagValue(shapeRef, "AHK_EDGE") != edge)
        return false
    if (targetId != "" && PPT_GetShapeTagValue(shapeRef, "AHK_TARGET_ID") != targetId)
        return false
    return true
}

PPT_FindManagedCaptions(slide, edge, targetId) {
    matches := []
    if !slide
        return matches

    for shp in slide.Shapes {
        if PPT_IsManagedCaption(shp, edge, targetId)
            matches.Push(shp)
    }
    return matches
}

PPT_GetShapeTextOrientation(shapeRef) {
    orientation := ""
    try orientation := shapeRef.TextFrame.Orientation
    if (orientation = "") {
        try orientation := shapeRef.TextFrame2.Orientation
    }
    return orientation
}

PPT_IsLegacyCaptionCandidate(shapeRef, rect, edge, epsilon := 0.75) {
    expectedOrientation := PPT_GetCaptionOrientation(edge)
    legacyOrientation := ""
    expectedRotation := rect.rotation
    rotation := 0

    if PPT_IsManagedCaption(shapeRef)
        return false

    try {
        textValue := shapeRef.TextFrame.TextRange.Text
    } catch e {
        Debug_LogCatch("PPT_Caption", "legacy_caption_text_error", e)
        return false
    }

    if !PPT_SpacingNearlyEqual(shapeRef.Left, rect.x, epsilon)
        return false
    if !PPT_SpacingNearlyEqual(shapeRef.Top, rect.y, epsilon)
        return false
    if !PPT_SpacingNearlyEqual(shapeRef.Width, rect.w, epsilon)
        return false
    if !PPT_SpacingNearlyEqual(shapeRef.Height, rect.h, epsilon)
        return false

    orientation := PPT_GetShapeTextOrientation(shapeRef)
    try rotation := shapeRef.Rotation

    if (edge = "Left")
        legacyOrientation := 2
    else if (edge = "Right")
        legacyOrientation := 3

    if (edge = "Left" || edge = "Right") {
        orientationMatch := (orientation = "" || orientation = expectedOrientation || orientation = legacyOrientation)
        rotationMatch := PPT_SpacingNearlyEqual(rotation, expectedRotation, epsilon)
        legacyRotationMatch := PPT_SpacingNearlyEqual(rotation, 0, epsilon)
        if !(orientationMatch && (rotationMatch || legacyRotationMatch))
            return false
    } else {
        if (orientation != "" && orientation != expectedOrientation)
            return false
        if !PPT_SpacingNearlyEqual(rotation, 0, epsilon)
            return false
    }

    return true
}

PPT_FindLegacyCaptions(slide, rect, edge) {
    matches := []
    if !slide
        return matches

    for shp in slide.Shapes {
        if PPT_IsLegacyCaptionCandidate(shp, rect, edge)
            matches.Push(shp)
    }
    return matches
}

PPT_FindExistingCaptions(slide, target, edge, rect := "") {
    matches := PPT_FindManagedCaptions(slide, edge, target.id)
    if (matches.MaxIndex())
        return matches

    if !IsObject(rect)
        return matches

    matches := PPT_FindLegacyCaptions(slide, rect, edge)
    if (matches.MaxIndex()) {
        PPT_CaptionLog("caption_legacy_match"
            , "edge=" . edge
            . " target=" . PPT_CaptionDescribeTarget(target)
            . " rect=" . PPT_CaptionDescribeRect(rect)
            . " count=" . matches.MaxIndex())
        for _, shp in matches
            PPT_TagCaptionIdentity(shp, edge, target.id)
    }
    return matches
}

PPT_DeleteShapes(shapeList) {
    deleted := 0
    if !IsObject(shapeList)
        return deleted

    for _, shp in shapeList {
        try {
            shp.Delete()
            deleted++
        }
    }
    return deleted
}

PPT_SetShapeTagValue(shapeRef, tagName, tagValue) {
    try shapeRef.Tags.Delete(tagName)
    try shapeRef.Tags.Add(tagName, tagValue)
}

PPT_TagCaptionIdentity(textBox, edge, targetId) {
    PPT_SetShapeTagValue(textBox, "AHK_KIND", "EDGE_CAPTION")
    PPT_SetShapeTagValue(textBox, "AHK_EDGE", edge)
    PPT_SetShapeTagValue(textBox, "AHK_TARGET_ID", targetId)
}

PPT_TagCaptionStyle(textBox) {
    preset := PPT_GetCaptionPreset()
    PPT_SetShapeTagValue(textBox, "AHK_CAPTION_PRESET", preset.Name)
}

PPT_CaptionPresetMatches(shapeRef) {
    preset := PPT_GetCaptionPreset()
    return (PPT_GetShapeTagValue(shapeRef, "AHK_CAPTION_PRESET") = preset.Name)
}

PPT_TagCaption(textBox, edge, targetId) {
    PPT_TagCaptionIdentity(textBox, edge, targetId)
    PPT_TagCaptionStyle(textBox)
}

PPT_StyleCaptionTextBox(textBox, edge, labelText := "Caption", preserveText := false) {
    preset := PPT_GetCaptionPreset()
    anchor := PPT_GetCaptionVerticalAnchor(edge)
    orientation := PPT_GetCaptionOrientation(edge)
    currentText := ""

    if (preserveText) {
        try currentText := textBox.TextFrame.TextRange.Text
        if (currentText != "")
            labelText := currentText
    }

    try textBox.Line.Visible := 0
    try textBox.Fill.Visible := 0

    try textBox.TextFrame.AutoSize := 0
    try textBox.TextFrame.Orientation := orientation
    try textBox.TextFrame.MarginLeft := preset.MarginLeft
    try textBox.TextFrame.MarginRight := preset.MarginRight
    try textBox.TextFrame.MarginTop := preset.MarginTop
    try textBox.TextFrame.MarginBottom := preset.MarginBottom
    try textBox.TextFrame.WordWrap := 0
    try textBox.TextFrame.VerticalAnchor := anchor
    try textBox.TextFrame.TextRange.Text := labelText
    try textBox.TextFrame.TextRange.Font.Size := preset.FontSize
    try textBox.TextFrame.TextRange.Font.Name := "Arial"
    try textBox.TextFrame.TextRange.ParagraphFormat.Alignment := 2
    try textBox.TextFrame.TextRange.ParagraphFormat.Bullet.Type := 0  ; ppBulletNone

    try {
        textBox.TextFrame2.AutoSize := 0
        textBox.TextFrame2.Orientation := orientation
        textBox.TextFrame2.MarginLeft := preset.MarginLeft
        textBox.TextFrame2.MarginRight := preset.MarginRight
        textBox.TextFrame2.MarginTop := preset.MarginTop
        textBox.TextFrame2.MarginBottom := preset.MarginBottom
        textBox.TextFrame2.WordWrap := 0
        textBox.TextFrame2.VerticalAnchor := anchor
        font2 := textBox.TextFrame2.TextRange.Font
        font2.Size := preset.FontSize
        font2.NameAscii := "Arial"
        font2.NameFarEast := "Meiryo"
    } catch e {
        Debug_LogCatch("PPT_Caption", "caption_style_textframe2_error", e)
    }
}

PPT_ApplyCaptionGeometry(textBox, rect) {
    try textBox.Rotation := rect.rotation
    try textBox.Left := rect.x
    try textBox.Top := rect.y
    try textBox.Width := rect.w
    try textBox.Height := rect.h
}

PPT_GetCaptionVisualGap(edge) {
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical

    if (edge = "Top" || edge = "Bottom")
        return PPT_CaptionVisualGapHorizontal
    return PPT_CaptionVisualGapVertical
}

PPT_AlignCaptionToShape(textBox, shape, edge, gap := "", slideSize := "") {

    if (gap = "")
        gap := PPT_GetCaptionVisualGap(edge)

    bounds := PPT_GetCaptionTextBounds(textBox)
    if !IsObject(bounds)
        return false

    dx := 0
    dy := 0

    if (edge = "Top")
        dy := (shape.top - gap) - (bounds.top + bounds.h)
    else if (edge = "Bottom")
        dy := (shape.bottom + gap) - bounds.top
    else if (edge = "Left")
        dx := (shape.left - gap) - (bounds.left + bounds.w)
    else if (edge = "Right")
        dx := (shape.right + gap) - bounds.left

    if (dx = 0 && dy = 0)
        return true

    try textBox.Left := textBox.Left + dx
    try textBox.Top := textBox.Top + dy

    if IsObject(slideSize) {
        try textBox.Left := PPT_ClampPosition(textBox.Left, textBox.Width, slideSize.w)
        try textBox.Top := PPT_ClampPosition(textBox.Top, textBox.Height, slideSize.h)
    }
    return true
}

PPT_AddEdgeCaption(edge) {
    slide := PPT_GetActiveSlide()
    if !slide
        return

    shapeRange := PPT_GetSelectedShapes()
    if !shapeRange {
        ToolTip, 図形を選択してください
        SetTimer, CloseToolTip, -1500
        return
    }

    shapes := PPT_CollectShapes(shapeRange)
    if !IsObject(shapes) || !shapes.MaxIndex()
        return

    slideSize := PPT_GetSlideSize()
    if !IsObject(slideSize)
        return

    targets := PPT_GetEdgeCaptionTargets(shapes, edge)
    layout := PPT_GetSelectionLayout(shapes)
    allExist := true
    allMatchPreset := true
    affectedCount := 0
    preset := PPT_GetCaptionPreset()

    PPT_CaptionLog("caption_start"
        , "edge=" . edge
        . " preset=" . preset.Name
        . " layout=" . layout
        . " slide=(" . PPT_CaptionFormatNumber(slideSize.w) . "," . PPT_CaptionFormatNumber(slideSize.h) . ") "
        . PPT_SpacingDescribeSelection())

    for _, target in targets {
        rect := PPT_GetCaptionRect(target, edge, slideSize)
        captions := PPT_FindExistingCaptions(slide, target, edge, rect)
        PPT_CaptionLog("caption_probe"
            , "edge=" . edge
            . " target=" . PPT_CaptionDescribeTarget(target)
            . " rect=" . PPT_CaptionDescribeRect(rect)
            . " existing=" . captions.MaxIndex())
        if !(captions.MaxIndex()) {
            allExist := false
            allMatchPreset := false
        } else if !PPT_CaptionPresetMatches(captions[1]) {
            allMatchPreset := false
        }
    }

    if (allExist && allMatchPreset) {
        deletedCount := 0
        for _, target in targets {
            rect := PPT_GetCaptionRect(target, edge, slideSize)
            captions := PPT_FindExistingCaptions(slide, target, edge, rect)
            deletedCount += PPT_DeleteShapes(captions)
            PPT_CaptionLog("caption_delete"
                , "edge=" . edge
                . " target=" . PPT_CaptionDescribeTarget(target)
                . " rect=" . PPT_CaptionDescribeRect(rect)
                . " deleted=" . captions.MaxIndex())
        }

        if (deletedCount > 0) {
            ToolTip, % edge . " caption removed: " . deletedCount
            SetTimer, CloseToolTip, -1500
        }
        return
    }

    for _, target in targets {
        rect := PPT_GetCaptionRect(target, edge, slideSize)
        captions := PPT_FindExistingCaptions(slide, target, edge, rect)
        textBox := ""
        preserveText := 0

        if (captions.MaxIndex()) {
            textBox := captions[1]
            preserveText := 1
            if (captions.MaxIndex() > 1) {
                extras := []
                Loop % captions.MaxIndex() - 1
                    extras.Push(captions[A_Index + 1])
                PPT_DeleteShapes(extras)
            }
        }

        try {
            if !textBox {
                textBox := slide.Shapes.AddTextbox(rect.orientation, rect.createX, rect.createY, rect.createW, rect.createH)
                PPT_TagCaptionIdentity(textBox, edge, target.id)
                PPT_CaptionLog("caption_created"
                    , "edge=" . edge
                    . " target=" . PPT_CaptionDescribeTarget(target)
                    . " rect=" . PPT_CaptionDescribeRect(rect)
                    . " actual=" . PPT_CaptionDescribeTextBox(textBox))
            }
            PPT_StyleCaptionTextBox(textBox, edge, "Caption", preserveText)
            PPT_ApplyCaptionGeometry(textBox, rect)
            PPT_AlignCaptionToShape(textBox, target, edge, "", slideSize)
            PPT_TagCaption(textBox, edge, target.id)
            PPT_CaptionLog("caption_applied"
                , "edge=" . edge
                . " preset=" . preset.Name
                . " target=" . PPT_CaptionDescribeTarget(target)
                . " rect=" . PPT_CaptionDescribeRect(rect)
                . " preserveText=" . preserveText
                . " visualGap=" . PPT_CaptionFormatNumber(PPT_GetCaptionVisualGap(edge))
                . " actual=" . PPT_CaptionDescribeTextBox(textBox))
            affectedCount++
        } catch e {
            PPT_CaptionLog("caption_apply_error"
                , "edge=" . edge
                . " target=" . PPT_CaptionDescribeTarget(target)
                . " rect=" . PPT_CaptionDescribeRect(rect)
                . " error=" . e.Message)
        }
    }

    if (affectedCount > 0) {
        ToolTip, % edge . " caption: " . affectedCount . " [" . preset.Name . "]"
        SetTimer, CloseToolTip, -1500
    }
}

; ============================================================================
;  ユーティリティ
; ============================================================================
PPT_SetWidthCm(cm) {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Width := cm * 28.3464567
}
PPT_SetHeightCm(cm) {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Height := cm * 28.3464567
}
PPT_ShowSizeCm() {
    shp := PPT_GetSelectedShapes()
    if !shp
        return
    try {
        w := Round(shp.Width / 28.3464567, 2)
        h := Round(shp.Height / 28.3464567, 2)
        ToolTip, % w . " cm x " . h . " cm"
        SetTimer, CloseToolTip, -2000
    } catch e {
        Debug_LogCatch("PPT_Spacing", "show_size_cm_error", e)
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
PPT_GetClipboardImagePaths() {
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "insert_images_slide_error", e)
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
PPT_PasteImageWithMetadata() {
    paths := PPT_GetClipboardImagePaths()
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "show_source_path_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "export_presentation_error", e)
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
            } catch e {
                Debug_LogCatch("PPT_Spacing", "export_tag_media_id_error", e)
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
            } catch e {
                Debug_LogCatch("PPT_Spacing", "export_tag_source_path_error", e)
            }
            srcName := ""
            try {
                srcName := shp.Tags("SOURCE_NAME")
            } catch e {
                Debug_LogCatch("PPT_Spacing", "export_tag_source_name_error", e)
            }
            if (srcName = "")
                SplitPath, srcPath, srcName

            insertedBy := ""
            try {
                insertedBy := shp.Tags("INSERTED_BY")
            } catch e {
                Debug_LogCatch("PPT_Spacing", "export_tag_inserted_by_error", e)
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
    } catch e {
        Debug_LogCatch("PPT_Spacing", "export_save_error", e)
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
