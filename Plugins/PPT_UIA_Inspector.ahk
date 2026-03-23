; ============================================================================
; PPT_UIA_Inspector.ahk
; PowerPoint の「図形の書式設定」パネル内の UIA ツリーを調査するスクリプト
; ============================================================================
; 使い方:
;   1. PowerPoint で図形を選択した状態で実行
;   2. Ctrl+Shift+F12 で「図形の書式設定」パネルを開き、UIA ツリーをダンプ
;   3. 結果は OutputDebug + MsgBox で表示される
;   4. DebugView (SysInternals) または AHK の ListLines で確認
; ============================================================================

global UIA := UIA_Interface()

InspectFormatPanel() {
    ; --- COM で書式設定パネルを開く ---
    try {
        ppt := ComObjActive("PowerPoint.Application")
        ppt.CommandBars.ExecuteMso("ObjectSizeAndPositionDialog")
    } catch e {
        MsgBox, 16, エラー, PowerPoint が起動していないか、図形が選択されていません。`n%e.Message%
        return
    }
    Sleep, 800  ; パネルが開くのを待つ

    ; --- UIA で PowerPoint ウィンドウを取得 ---
    hwnd := WinExist("ahk_exe POWERPNT.EXE")
    if !hwnd {
        MsgBox, 16, エラー, PowerPoint ウィンドウが見つかりません。
        return
    }
    rootEl := UIA.ElementFromHandle(hwnd)

    ; --- パネル全体を探す ---
    ; 「図形の書式設定」「Format Shape」などの名前を持つペインを探す
    result := ""
    result .= "============================================`n"
    result .= " PowerPoint UIA ツリー調査結果`n"
    result .= "============================================`n`n"

    ; 方法1: 全 Pane / Window 要素を列挙
    result .= "--- Pane / Custom 要素一覧 ---`n"
    condTrue := UIA.CreateTrueCondition()
    allElements := rootEl.FindAll(condTrue, 0x4)  ; Descendants

    panelFound := false
    if allElements {
        Loop % allElements.MaxIndex() {
            el := allElements[A_Index]
            try {
                ctrlType := el.CurrentControlType
                name := el.CurrentName
                autoId := el.CurrentAutomationId
                className := el.CurrentClassName

                ; 書式設定パネルの候補を探す
                if (InStr(name, "書式") || InStr(name, "Format")
                    || InStr(name, "サイズ") || InStr(name, "Size")
                    || InStr(autoId, "Format") || InStr(autoId, "Size")) {
                    result .= Format("  ★ Name='{}' | AutomationId='{}' | CtrlType={} | Class='{}'"
                        , name, autoId, ctrlType, className) . "`n"
                    panelFound := true

                    ; この要素の子を深掘り
                    result .= DumpChildren(el, "    ", 3)
                }
            } catch {
            }
        }
    }

    if !panelFound {
        result .= "  (書式設定パネルが見つかりませんでした)`n"
        result .= "  → パネルが開いているか確認してください`n`n"

        ; フォールバック: Edit / Spinner コントロールを全列挙
        result .= "--- 全 Edit / Spinner 要素 ---`n"
        if allElements {
            Loop % allElements.MaxIndex() {
                el := allElements[A_Index]
                try {
                    ctrlType := el.CurrentControlType
                    ; Edit=50004, Spinner=50016
                    if (ctrlType = 50004 || ctrlType = 50016) {
                        name := el.CurrentName
                        autoId := el.CurrentAutomationId
                        className := el.CurrentClassName
                        result .= Format("  Name='{}' | AutomationId='{}' | CtrlType={} | Class='{}'"
                            , name, autoId, ctrlType, className) . "`n"
                    }
                } catch {
                }
            }
        }
    }

    ; --- 結果を表示 ---
    OutputDebug, % result

    ; ファイルにも出力
    filePath := A_ScriptDir . "\PPT_UIA_Dump.txt"
    FileDelete, %filePath%
    FileAppend, %result%, %filePath%, UTF-8
    MsgBox, 64, UIA 調査完了, 結果を以下に保存しました:`n%filePath%`n`n（最初の1000文字を表示）`n`n%result%
}

; --- 子要素を再帰的にダンプ ---
DumpChildren(parentEl, indent, maxDepth) {
    if (maxDepth <= 0)
        return ""

    result := ""
    try {
        condTrue := UIA.CreateTrueCondition()
        children := parentEl.FindAll(condTrue, 0x2)  ; Children のみ
        if !children
            return ""

        Loop % children.MaxIndex() {
            el := children[A_Index]
            try {
                ctrlType := el.CurrentControlType
                name := el.CurrentName
                autoId := el.CurrentAutomationId
                className := el.CurrentClassName

                ctrlName := GetControlTypeName(ctrlType)
                result .= indent . Format("[{}] Name='{}' | AutomationId='{}' | Class='{}'"
                    , ctrlName, name, autoId, className) . "`n"

                ; 再帰
                result .= DumpChildren(el, indent . "  ", maxDepth - 1)
            } catch {
            }
        }
    } catch {
    }
    return result
}

GetControlTypeName(ct) {
    static names := {50000: "Button", 50001: "Calendar", 50002: "CheckBox"
        , 50003: "ComboBox", 50004: "Edit", 50005: "Hyperlink"
        , 50006: "Image", 50007: "ListItem", 50008: "List"
        , 50009: "Menu", 50010: "MenuBar", 50011: "MenuItem"
        , 50012: "ProgressBar", 50013: "RadioButton", 50014: "ScrollBar"
        , 50015: "Slider", 50016: "Spinner", 50017: "StatusBar"
        , 50018: "Tab", 50019: "TabItem", 50020: "Text"
        , 50021: "ToolBar", 50022: "ToolTip", 50023: "Tree"
        , 50024: "TreeItem", 50025: "Custom", 50026: "Group"
        , 50027: "Thumb", 50028: "DataGrid", 50029: "DataItem"
        , 50030: "Document", 50031: "SplitButton", 50032: "Window"
        , 50033: "Pane", 50034: "Header", 50035: "HeaderItem"
        , 50036: "Table", 50037: "TitleBar", 50038: "Separator"
        , 50039: "SemanticZoom", 50040: "AppBar"}
    return names.HasKey(ct) ? names[ct] : ct
}
