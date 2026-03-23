; ============================================================================
; PowerPoint.ahk - COM + UIA ハイブリッド構成
; ============================================================================
global _PPT_IMG_EXT   := "png|jpg|jpeg|bmp|tif|tiff|gif"
global _PPT_MEDIA_EXT := "mp4|avi|wmv|mov|mkv|mp3|wav|wma|m4a|m4v|webm"
global _PPT_ALL_EXT   := _PPT_IMG_EXT . "|" . _PPT_MEDIA_EXT

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
            FormatTime, insertTime,, yyyy/MM/dd HH:mm:ss
            shp.Tags.Add("SOURCE_PATH", filePath)
            shp.Tags.Add("INSERT_DATE", insertTime)
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
        srcPath := shp.Tags("SOURCE_PATH")
        insDate := shp.Tags("INSERT_DATE")
        if (srcPath != "") {
            MsgBox, 64, 図のソース情報, Source: %srcPath%`nDate:   %insDate%
        } else {
            MsgBox, 48, , このマクロ経由で挿入されていない図です。
        }
    } catch {
    }
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

    jsonEntries := []
    missingCount := 0
    copyCount    := 0
    slideIdx     := 0

    ; For each で走査（prs.Slides(n) の直接アクセスを回避）
    For sld in prs.Slides {
        slideIdx++
        slideNum  := Format("{:02d}", slideIdx)
        shapeIdx  := 0

        For shp in sld.Shapes {
            shapeIdx++
            srcPath := ""
            try {
                srcPath := shp.Tags("SOURCE_PATH")
            } catch {
            }
            if (srcPath = "")
                continue

            SplitPath, srcPath, srcFileName
            shapeNum := Format("{:02d}", shapeIdx)
            destName := "slide" . slideNum . "_shape" . shapeNum . "_" . srcFileName
            destPath := destDir . "\" . destName

            if FileExist(srcPath) {
                FileCopy, %srcPath%, %destPath%, 1
                shp.Tags.Add("SOURCE_PATH", destPath)
                shp.AlternativeText := "[source] " . destPath
                jsonEntries.Push(PPT_JsonEntry(slideIdx, shapeIdx, srcFileName, srcPath, destPath, "copied"))
                copyCount++
            } else {
                MsgBox, 52, ファイルが見つかりません
                    , Slide %slideIdx% / Shape %shapeIdx%`n`n記録されているパス:`n%srcPath%`n`nファイルを手動で指定しますか？
                IfMsgBox, Yes
                {
                    FileSelectFile, manualPath, 3, , ファイルを選択
                        , メディアファイル (*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.gif;*.mp4;*.avi;*.wmv;*.mov;*.mkv;*.mp3;*.wav;*.wma;*.m4a;*.m4v;*.webm)
                    if (manualPath != "") {
                        FileCopy, %manualPath%, %destPath%, 1
                        shp.Tags.Add("SOURCE_PATH", destPath)
                        shp.AlternativeText := "[source] " . destPath
                        jsonEntries.Push(PPT_JsonEntry(slideIdx, shapeIdx, srcFileName, manualPath, destPath, "manual"))
                        copyCount++
                    } else {
                        jsonEntries.Push(PPT_JsonEntry(slideIdx, shapeIdx, srcFileName, srcPath, "", "skipped"))
                        missingCount++
                    }
                } else {
                    jsonEntries.Push(PPT_JsonEntry(slideIdx, shapeIdx, srcFileName, srcPath, "", "skipped"))
                    missingCount++
                }
            }
        }
    }

    ; sources_list.json 生成
    manifestPath := destDir . "\sources_list.json"
    FileDelete, %manifestPath%
    json := "{`n"
        . "  ""generated"": """ . A_YYYY "-" A_MM "-" A_DD . """,`n"
        . "  ""pptx"": """ . PPT_JsonEscape(pptPath) . """,`n"
        . "  ""sources"": [`n"
    for idx, entry in jsonEntries {
        json .= "    " . entry
        json .= (idx < jsonEntries.MaxIndex()) ? ",`n" : "`n"
    }
    json .= "  ]`n}`n"
    FileAppend, %json%, %manifestPath%, UTF-8

    ; pptx 上書き保存
    try {
        prs.Save()
    } catch {
        MsgBox, 48, 警告, pptxの保存に失敗しました。手動で保存してください。
    }

    msg := copyCount . " 枚をコピーしました。"
    if (missingCount > 0)
        msg .= "`n※ " . missingCount . " 枚はスキップされました（sources_list.jsonを確認）。"
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

PPT_JsonEntry(slide, shape, file, source, dest, status) {
    return "{""slide"": " . slide
        . ", ""shape"": " . shape
        . ", ""file"": """ . PPT_JsonEscape(file) . """"
        . ", ""source"": """ . PPT_JsonEscape(source) . """"
        . ", ""dest"": """ . PPT_JsonEscape(dest) . """"
        . ", ""status"": """ . status . """}"
}
