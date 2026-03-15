; ============================================================================
; PowerPoint.ahk - COM + UIA ハイブリッド構成
; ============================================================================

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
    } catch {
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
    if shp
        try shp.Group()
}
GroupRelease() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.Ungroup()
}

; ============================================================================
;  前面 / 背面
; ============================================================================

SetFront() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.ZOrder(0)
}
SetBack() {
    shp := PPT_GetSelectedShapes()
    if shp
        try shp.ZOrder(1)
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

; ============================================================================
;  書式設定パネルを開く / テキストのみ貼り付け
; ============================================================================

OpenFormatObject() {
    PPT_TryExecuteMso(["ObjectSizeAndPositionDialog"])
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
