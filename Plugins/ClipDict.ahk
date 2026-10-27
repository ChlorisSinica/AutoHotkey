; ==============================================================================
; ClipDict.ahk
; クリップボードのテキストを辞書 (1～9) で一括置換する GUI
; 依存: AppInit.ahk (ClipboardWrite), Application.ahk (CloseToolTip)
;       WindowManager.ahk (GetMonitorWorkAreaInfoFromWindow, GetMonitorWorkAreaInfoFromPoint)
; 辞書: config\ClipDict\dict<N>.tsv (UTF-8 / 1行1件: 検索<TAB>置換<TAB>種別)
; ==============================================================================

global ClipDict_MaxDicts      := 9
global ClipDict_Dir           := A_ScriptDir . "\config\ClipDict"
global ClipDict_Dicts         := {}
global ClipDict_Index         := 1
global ClipDict_SourceText    := ""
global ClipDict_PrevHwnd      := 0
global ClipDict_GuiHwnd       := 0
global ClipDict_PendingSave   := 0
global ClipDict_Dpi           := 96
global ClipDict_Scale         := 1
global ClipDict_LastMonitor   := 0
global ClipDictDictDDL, ClipDictNameEdit, ClipDictCaseCheck, ClipDictLV
global ClipDictFromEdit, ClipDictToEdit, ClipDictRegexCheck
global ClipDictSourceEdit, ClipDictResultEdit, ClipDictStatus, ClipDictApplyBtn

; ==========================================================
; --- 入口 ---
; ==========================================================
ClipDict_Open(index := 1) {
    activeHwnd := WinExist("A")
    if (activeHwnd && activeHwnd != ClipDict_GuiHwnd)
        ClipDict_PrevHwnd := activeHwnd

    ; 表示中なら今の場所のまま、閉じていれば作業中のウィンドウがあるモニタで開く。
    visible := ClipDict_GuiHwnd && DllCall("IsWindowVisible", "Ptr", ClipDict_GuiHwnd)
    monitor := visible ? GetMonitorWorkAreaInfoFromWindow(ClipDict_GuiHwnd) : ClipDict_GetTargetMonitor()
    dpi := ClipDict_GetMonitorDpi(monitor)
    ClipDict_FlushPendingSave()
    if (!ClipDict_GuiHwnd || dpi != ClipDict_Dpi)
        ClipDict_CreateGui(dpi)

    ClipDict_LoadAll()
    ClipDict_ReadClipboard()
    ClipDict_SelectDict(index)
    ; 前回と同じモニタなら前回の位置のまま、モニタが変わったか作り直したときは中央へ置く。
    if (visible ? !ClipDict_LastMonitor : monitor.Index != ClipDict_LastMonitor)
        ClipDict_PlaceOnMonitor(monitor)
    ClipDict_LastMonitor := monitor.Index
    ; Gui Show は主モニタの DPI で計算した外枠サイズに戻してしまうため ShowWindow で出す。
    DllCall("ShowWindow", "Ptr", ClipDict_GuiHwnd, "Int", 1) ; SW_SHOWNORMAL
    WinActivate, % "ahk_id " . ClipDict_GuiHwnd
    GuiControl, ClipDict:Focus, ClipDictApplyBtn
}

ClipDict_IsGuiActive() {
    return ClipDict_GuiHwnd && WinActive("ahk_id " . ClipDict_GuiHwnd)
}

ClipDict_Close() {
    ClipDict_FlushPendingSave()
    Gui, ClipDict:Hide
}

ClipDict_GuiClose(guiHwnd := 0) {
    ClipDict_Close()
}

ClipDict_GuiEscape(guiHwnd := 0) {
    ClipDict_Close()
}

; ==========================================================
; --- GUI 構築 ---
; ==========================================================
; main.ahk はスレッドを Per-Monitor DPI 対応にしているが、AHK v1 の GUI は主モニタの
; DPI (A_ScreenDPI) で拡大されるため、-DPIScale にして表示先モニタの DPI で自前に拡大する。
ClipDict_CreateGui(dpi) {
    ClipDict_Dpi := dpi
    ClipDict_Scale := dpi / 96
    ClipDict_LastMonitor := 0
    Gui, ClipDict:New, +HwndguiHwnd +LabelClipDict_Gui -DPIScale, クリップボード辞書置換
    ClipDict_GuiHwnd := guiHwnd
    Gui, ClipDict:Default
    ; フォントの pt は A_ScreenDPI で px 換算されるので、その分を打ち消す。
    Gui, ClipDict:Font, % "s" . Round(9 * dpi / A_ScreenDPI), Segoe UI
    Gui, ClipDict:Color, F3F3F3

    Gui, ClipDict:Add, Text, % ClipDict_Pos("x12 y15 w32 h20"), 辞書
    Gui, ClipDict:Add, DropDownList, % ClipDict_Pos("x46 y12 w220 AltSubmit vClipDictDictDDL gClipDict_OnDictSelect")
    Gui, ClipDict:Add, Text, % ClipDict_Pos("x284 y15 w32 h20"), 名前
    Gui, ClipDict:Add, Edit, % ClipDict_Pos("x318 y12 w200 h23 vClipDictNameEdit gClipDict_OnNameChange")
    Gui, ClipDict:Add, CheckBox, % ClipDict_Pos("x536 y14 w212 h20 vClipDictCaseCheck gClipDict_OnCaseToggle"), 大文字と小文字を区別する

    Gui, ClipDict:Add, ListView, % ClipDict_Pos("x12 y44 w736 h200 AltSubmit -Multi Grid NoSort NoSortHdr +LV0x10000 vClipDictLV gClipDict_OnListEvent"), No|検索|置換|種別|件数
    LV_ModifyCol(1, ClipDict_Px(40) . " Right")
    LV_ModifyCol(2, ClipDict_Px(270))
    LV_ModifyCol(3, ClipDict_Px(270))
    LV_ModifyCol(4, ClipDict_Px(70))
    LV_ModifyCol(5, ClipDict_Px(60) . " Right")

    Gui, ClipDict:Add, Text, % ClipDict_Pos("x12 y257 w32 h20"), 検索
    Gui, ClipDict:Add, Edit, % ClipDict_Pos("x46 y254 w270 h23 vClipDictFromEdit")
    Gui, ClipDict:Add, Text, % ClipDict_Pos("x328 y257 w32 h20"), 置換
    Gui, ClipDict:Add, Edit, % ClipDict_Pos("x362 y254 w270 h23 vClipDictToEdit")
    Gui, ClipDict:Add, CheckBox, % ClipDict_Pos("x646 y256 w102 h20 vClipDictRegexCheck"), 正規表現

    Gui, ClipDict:Add, Button, % ClipDict_Pos("x46 y286 w64 h25 gClipDict_OnAddEntry"), 追加
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x114 y286 w64 h25 gClipDict_OnUpdateEntry"), 上書き
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x182 y286 w64 h25 gClipDict_DeleteSelectedEntry"), 削除
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x250 y286 w32 h25 gClipDict_OnMoveUp"), ↑
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x286 y286 w32 h25 gClipDict_OnMoveDown"), ↓
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x322 y286 w64 h25 gClipDict_OnClearEntry"), クリア
    Gui, ClipDict:Add, Text, % ClipDict_Pos("x398 y284 w350 h30 c606060"), Enter: 行を選択中なら上書き / 未選択なら追加`n正規表現の置換文字列では $1 で後方参照、\r\n で改行

    Gui, ClipDict:Add, Text, % ClipDict_Pos("x12 y322 w360 h18"), クリップボード
    Gui, ClipDict:Add, Text, % ClipDict_Pos("x388 y322 w360 h18"), 置換後プレビュー
    Gui, ClipDict:Add, Edit, % ClipDict_Pos("x12 y340 w360 h178 ReadOnly Multi -WantReturn vClipDictSourceEdit")
    Gui, ClipDict:Add, Edit, % ClipDict_Pos("x388 y340 w360 h178 ReadOnly Multi -WantReturn vClipDictResultEdit")

    Gui, ClipDict:Add, Text, % ClipDict_Pos("x12 y523 w252 h32 vClipDictStatus")
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x270 y526 w70 h27 gClipDict_OnReloadClipboard"), 再読込
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x344 y526 w150 h27 Default vClipDictApplyBtn gClipDict_OnDefaultButton"), 置換してコピー (Enter)
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x498 y526 w172 h27 gClipDict_ApplyAndPaste"), 置換して貼り付け (Ctrl+Enter)
    Gui, ClipDict:Add, Button, % ClipDict_Pos("x674 y526 w74 h27 gClipDict_Close"), 閉じる
}

; "x12 y15 w32 h20 vFoo" のうち座標とサイズだけを ClipDict_Scale 倍にする。
ClipDict_Pos(options) {
    result := ""
    Loop, Parse, options, %A_Space%
    {
        if RegExMatch(A_LoopField, "^([xywh])(\d+)$", m)
            result .= m1 . ClipDict_Px(m2) . " "
        else
            result .= A_LoopField . " "
    }
    return RTrim(result)
}

ClipDict_Px(value) {
    return Round(value * ClipDict_Scale)
}

ClipDict_GetTargetMonitor() {
    if (ClipDict_PrevHwnd && WinExist("ahk_id " . ClipDict_PrevHwnd))
        return GetMonitorWorkAreaInfoFromWindow(ClipDict_PrevHwnd)
    CoordMode, Mouse, Screen
    MouseGetPos, mouseX, mouseY
    return GetMonitorWorkAreaInfoFromPoint(mouseX, mouseY)
}

ClipDict_GetMonitorDpi(monitor) {
    point := (Round(monitor.CenterX) & 0xFFFFFFFF) | (Round(monitor.CenterY) << 32)
    hMonitor := DllCall("MonitorFromPoint", "Int64", point, "UInt", 2, "Ptr") ; 2=MONITOR_DEFAULTTONEAREST
    if (DllCall("shcore\GetDpiForMonitor", "Ptr", hMonitor, "Int", 0, "UInt*", dpiX, "UInt*", dpiY) != 0)
        return A_ScreenDPI
    return dpiX
}

; 非表示のまま表示先モニタの中央へ置く (表示は呼び出し側)。
ClipDict_PlaceOnMonitor(monitor) {
    clientW := ClipDict_Px(760)
    clientH := ClipDict_Px(562)
    Gui, ClipDict:Show, Hide w%clientW% h%clientH%
    ; 外枠は表示先モニタの DPI で求める (AHK 任せだと主モニタの DPI でタイトルバー分ずれる)。
    VarSetCapacity(rect, 16, 0)
    NumPut(clientW, rect, 8, "Int")
    NumPut(clientH, rect, 12, "Int")
    style := DllCall("GetWindowLong", "Ptr", ClipDict_GuiHwnd, "Int", -16, "UInt")
    exStyle := DllCall("GetWindowLong", "Ptr", ClipDict_GuiHwnd, "Int", -20, "UInt")
    DllCall("AdjustWindowRectExForDpi", "Ptr", &rect, "UInt", style, "Int", false, "UInt", exStyle, "UInt", ClipDict_Dpi)
    outerW := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
    outerH := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
    x := Round(monitor.Left + Max(0, (monitor.Width - outerW) / 2))
    y := Round(monitor.Top + Max(0, (monitor.Height - outerH) / 2))
    DllCall("SetWindowPos", "Ptr", ClipDict_GuiHwnd, "Ptr", 0, "Int", x, "Int", y, "Int", outerW, "Int", outerH, "UInt", 0x14) ; NOZORDER|NOACTIVATE
}

; ==========================================================
; --- GUI イベント ---
; ==========================================================
ClipDict_OnDictSelect() {
    GuiControlGet, index, ClipDict:, ClipDictDictDDL
    ClipDict_SelectDict(index)
}

ClipDict_OnNameChange() {
    GuiControlGet, name, ClipDict:, ClipDictNameEdit
    dict := ClipDict_GetDict(ClipDict_Index)
    ; 辞書切替時の GuiControl 代入でも発火するため、変化が無ければ保存しない。
    if (name == dict.Name)
        return
    dict.Name := name
    ClipDict_ScheduleSave(ClipDict_Index)
}

ClipDict_OnCaseToggle() {
    GuiControlGet, checked, ClipDict:, ClipDictCaseCheck
    ClipDict_GetDict(ClipDict_Index).CaseSensitive := checked ? 1 : 0
    ClipDict_CommitChanges(ClipDict_GetSelectedRow())
}

ClipDict_OnListEvent() {
    if (A_GuiEvent == "I") {
        if InStr(ErrorLevel, "S", true)
            ClipDict_LoadEntryIntoFields(A_EventInfo)
        return
    }
    if (A_GuiEvent == "K" && A_EventInfo = 46) {
        ClipDict_DeleteSelectedEntry()
        return
    }
    if (A_GuiEvent = "DoubleClick" && A_EventInfo)
        GuiControl, ClipDict:Focus, ClipDictFromEdit
}

ClipDict_OnDefaultButton() {
    ; Enter は既定ボタンに届くため、フォーカス位置で動作を切り替える。
    GuiControlGet, focused, ClipDict:FocusV
    if (focused = "ClipDictFromEdit" || focused = "ClipDictToEdit") {
        ClipDict_SubmitEntry("auto")
        return
    }
    if (focused = "ClipDictNameEdit") {
        ClipDict_FlushPendingSave()
        GuiControl, ClipDict:Focus, ClipDictLV
        return
    }
    ClipDict_ApplyAndCopy()
}

ClipDict_OnAddEntry() {
    ClipDict_SubmitEntry("add")
}

ClipDict_OnUpdateEntry() {
    ClipDict_SubmitEntry("update")
}

ClipDict_OnMoveUp() {
    ClipDict_MoveSelectedEntry(-1)
}

ClipDict_OnMoveDown() {
    ClipDict_MoveSelectedEntry(1)
}

ClipDict_OnClearEntry() {
    ClipDict_ClearEntryFields()
    GuiControl, ClipDict:Focus, ClipDictFromEdit
}

ClipDict_OnReloadClipboard() {
    ClipDict_ReadClipboard()
    ClipDict_RefreshPreview()
}

; ==========================================================
; --- 置換の実行 ---
; ==========================================================
ClipDict_ApplyAndCopy() {
    ClipDict_FlushPendingSave()
    if (ClipDict_SourceText = "") {
        ClipDict_SetStatus("クリップボードにテキストがありません")
        return false
    }

    result := ClipDict_Apply(ClipDict_SourceText, ClipDict_GetDict(ClipDict_Index), counts, errors)
    total := ClipDict_SumCounts(counts)
    ; 変化が無ければ書き戻さず、元のリッチテキスト等を保持する。
    if (!(result == ClipDict_SourceText) && !ClipboardWrite(result)) {
        ClipDict_SetStatus("クリップボードへの書き込みに失敗しました")
        return false
    }

    Gui, ClipDict:Hide
    message := ClipDict_DictLabel(ClipDict_Index) . ": " . total . " 件置換"
    message .= (result == ClipDict_SourceText) ? " (クリップボードは変更なし)" : "してコピーしました"
    if (errors.Count())
        message .= "`n正規表現エラー " . errors.Count() . " 件をスキップ"
    ToolTip, %message%
    closeToolTipFn := Func("CloseToolTip")
    SetTimer, %closeToolTipFn%, -2000
    return true
}

ClipDict_ApplyAndPaste() {
    if !ClipDict_ApplyAndCopy()
        return
    target := ClipDict_PrevHwnd
    if !(target && WinExist("ahk_id " . target))
        return
    WinActivate, ahk_id %target%
    WinWaitActive, ahk_id %target%,, 1
    if (ErrorLevel)
        return
    Send, ^v
}

; 辞書の各エントリを上から順に適用する。counts[i] は置換件数 (正規表現エラー時は -1)。
ClipDict_Apply(text, dict, ByRef counts, ByRef errors) {
    counts := []
    errors := {}
    prevCaseSense := A_StringCaseSense
    StringCaseSense, % dict.CaseSensitive ? "On" : "Off"

    for index, entry in dict.Entries {
        count := 0
        if (entry.Regex) {
            pattern := ClipDict_RegexPattern(entry.From, dict.CaseSensitive)
            ; try 内では正規表現エラーが例外になる (try 外だと "" が返るだけ)。
            try {
                text := RegExReplace(text, pattern, ClipDict_Unescape(entry.To), count)
            } catch e {
                counts[index] := -1
                errors[index] := e.Message
                continue
            }
        } else if (entry.From != "") {
            text := StrReplace(text, entry.From, entry.To, count)
        }
        counts[index] := count
    }

    StringCaseSense, %prevCaseSense%
    return text
}

ClipDict_RegexPattern(pattern, caseSensitive) {
    if (caseSensitive)
        return pattern
    ; 先頭に AHK のオプション指定 (例: "m)") があれば i を足す。
    if RegExMatch(pattern, "^[imsxADJUXPSC]*\)")
        return "i" . pattern
    return "i)" . pattern
}

ClipDict_RegexError(pattern) {
    try {
        RegExMatch("", pattern)
    } catch e {
        return e.Message
    }
    return ""
}

ClipDict_SumCounts(counts) {
    total := 0
    for _, count in counts {
        if (count > 0)
            total += count
    }
    return total
}

; ==========================================================
; --- 画面更新 ---
; ==========================================================
ClipDict_SelectDict(index) {
    ClipDict_FlushPendingSave()
    ClipDict_Index := ClipDict_NormalizeIndex(index)
    dict := ClipDict_GetDict(ClipDict_Index)
    ClipDict_RefreshDictChoices()
    GuiControl, ClipDict:, ClipDictNameEdit, % dict.Name
    GuiControl, ClipDict:, ClipDictCaseCheck, % dict.CaseSensitive ? 1 : 0
    ClipDict_ClearEntryFields()
    ClipDict_RefreshList()
}

ClipDict_RefreshDictChoices() {
    if (!ClipDict_GuiHwnd)
        return
    items := ""
    Loop, %ClipDict_MaxDicts% {
        label := StrReplace(ClipDict_DictLabel(A_Index), "|", "｜")
        items .= "|" . label . " (" . ClipDict_GetDict(A_Index).Entries.Length() . ")"
    }
    GuiControl, ClipDict:, ClipDictDictDDL, %items%
    GuiControl, ClipDict:Choose, ClipDictDictDDL, %ClipDict_Index%
}

ClipDict_RefreshList(selectRow := 0, visibleRow := 0) {
    Gui, ClipDict:Default
    Gui, ClipDict:ListView, ClipDictLV
    GuiControl, ClipDict:-Redraw, ClipDictLV
    LV_Delete()
    for index, entry in ClipDict_GetDict(ClipDict_Index).Entries
        LV_Add("", index, ClipDict_DisplayText(entry.From), ClipDict_DisplayText(entry.To), entry.Regex ? "正規表現" : "通常", "")
    if (selectRow)
        LV_Modify(selectRow, "Select Focus Vis")
    else if (visibleRow)
        LV_Modify(visibleRow, "Vis")
    GuiControl, ClipDict:+Redraw, ClipDictLV
    ClipDict_RefreshPreview()
}

ClipDict_RefreshPreview() {
    dict := ClipDict_GetDict(ClipDict_Index)
    result := ClipDict_Apply(ClipDict_SourceText, dict, counts, errors)
    GuiControl, ClipDict:, ClipDictResultEdit, % result

    Gui, ClipDict:Default
    Gui, ClipDict:ListView, ClipDictLV
    for index in dict.Entries
        LV_Modify(index, "Col5", counts[index] < 0 ? "ERR" : counts[index])

    if (ClipDict_SourceText = "") {
        ClipDict_SetStatus("クリップボードにテキストがありません")
        return
    }
    hitRules := 0
    for _, count in counts {
        if (count > 0)
            hitRules += 1
    }
    status := ClipDict_SumCounts(counts) . " 件置換 (" . hitRules . "/" . dict.Entries.Length() . " ルールが一致)"
    for index, message in errors {
        status .= "`nNo." . index . " 正規表現エラー: " . message
        break
    }
    ClipDict_SetStatus(status)
}

ClipDict_ReadClipboard() {
    text := ""
    try text := Clipboard
    ClipDict_SourceText := text
    GuiControl, ClipDict:, ClipDictSourceEdit, % text
}

ClipDict_SetStatus(text) {
    GuiControl, ClipDict:, ClipDictStatus, % text
}

ClipDict_DisplayText(text) {
    text := StrReplace(text, "`r`n", "⏎")
    text := StrReplace(text, "`n", "⏎")
    text := StrReplace(text, "`r", "⏎")
    return StrReplace(text, "`t", "⇥")
}

; ==========================================================
; --- エントリ編集 ---
; ==========================================================
ClipDict_GetSelectedRow() {
    Gui, ClipDict:Default
    Gui, ClipDict:ListView, ClipDictLV
    return LV_GetNext(0)
}

ClipDict_LoadEntryIntoFields(row) {
    entry := ClipDict_GetDict(ClipDict_Index).Entries[row]
    if !IsObject(entry)
        return
    GuiControl, ClipDict:, ClipDictFromEdit, % entry.From
    GuiControl, ClipDict:, ClipDictToEdit, % entry.To
    GuiControl, ClipDict:, ClipDictRegexCheck, % entry.Regex ? 1 : 0
}

ClipDict_ClearEntryFields() {
    Gui, ClipDict:Default
    Gui, ClipDict:ListView, ClipDictLV
    LV_Modify(0, "-Select")
    GuiControl, ClipDict:, ClipDictFromEdit
    GuiControl, ClipDict:, ClipDictToEdit
    GuiControl, ClipDict:, ClipDictRegexCheck, 0
}

; mode: "add" / "update" / "auto" (行選択中なら update)
ClipDict_SubmitEntry(mode) {
    GuiControlGet, from, ClipDict:, ClipDictFromEdit
    GuiControlGet, to, ClipDict:, ClipDictToEdit
    GuiControlGet, isRegex, ClipDict:, ClipDictRegexCheck
    if (from = "") {
        ClipDict_SetStatus("検索文字列を入力してください")
        GuiControl, ClipDict:Focus, ClipDictFromEdit
        return false
    }
    if (isRegex) {
        error := ClipDict_RegexError(from)
        if (error != "") {
            ClipDict_SetStatus("正規表現エラー: " . error)
            GuiControl, ClipDict:Focus, ClipDictFromEdit
            return false
        }
    }

    row := ClipDict_GetSelectedRow()
    if (mode = "auto")
        mode := row ? "update" : "add"
    if (mode = "update" && !row) {
        ClipDict_SetStatus("上書きする行を選択してください")
        return false
    }

    entries := ClipDict_GetDict(ClipDict_Index).Entries
    entry := {From: from, To: to, Regex: isRegex ? 1 : 0}
    if (mode = "update") {
        entries[row] := entry
        return ClipDict_CommitChanges(row)
    }

    entries.Push(entry)
    ClipDict_CommitChanges(0, entries.Length())
    ClipDict_ClearEntryFields()
    GuiControl, ClipDict:Focus, ClipDictFromEdit
    return true
}

ClipDict_DeleteSelectedEntry() {
    row := ClipDict_GetSelectedRow()
    if (!row) {
        ClipDict_SetStatus("削除する行を選択してください")
        return
    }
    ClipDict_GetDict(ClipDict_Index).Entries.RemoveAt(row)
    ; 入力欄には削除した内容が残るので、「追加」で元に戻せる。
    if ClipDict_CommitChanges()
        ClipDict_SetStatus("No." . row . " を削除しました (「追加」で戻せます)")
}

ClipDict_MoveSelectedEntry(delta) {
    row := ClipDict_GetSelectedRow()
    entries := ClipDict_GetDict(ClipDict_Index).Entries
    target := row + delta
    if (!row || target < 1 || target > entries.Length())
        return
    moved := entries[row]
    entries[row] := entries[target]
    entries[target] := moved
    ClipDict_CommitChanges(target)
}

ClipDict_CommitChanges(selectRow := 0, visibleRow := 0) {
    saved := ClipDict_SaveDict(ClipDict_Index)
    ClipDict_RefreshDictChoices()
    ClipDict_RefreshList(selectRow, visibleRow)
    if (!saved)
        ClipDict_SetStatus("辞書ファイルを保存できません: " . ClipDict_DictPath(ClipDict_Index))
    return saved
}

; ==========================================================
; --- 辞書データ ---
; ==========================================================
ClipDict_NormalizeIndex(index) {
    if index is not integer
        return 1
    return (index < 1 || index > ClipDict_MaxDicts) ? 1 : index
}

ClipDict_NewDict(index) {
    return {Name: "辞書" . index, CaseSensitive: 1, Entries: []}
}

ClipDict_GetDict(index) {
    if !ClipDict_Dicts.HasKey(index)
        ClipDict_Dicts[index] := ClipDict_NewDict(index)
    return ClipDict_Dicts[index]
}

ClipDict_DictLabel(index) {
    name := ClipDict_GetDict(index).Name
    return index . ": " . (name != "" ? name : "辞書" . index)
}

ClipDict_DictPath(index) {
    return ClipDict_Dir . "\dict" . index . ".tsv"
}

ClipDict_LoadAll() {
    ClipDict_Dicts := {}
    Loop, %ClipDict_MaxDicts%
        ClipDict_Dicts[A_Index] := ClipDict_LoadDict(ClipDict_DictPath(A_Index), A_Index)
}

ClipDict_ScheduleSave(index) {
    if (ClipDict_PendingSave && ClipDict_PendingSave != index)
        ClipDict_FlushPendingSave()
    ClipDict_PendingSave := index
    saveFn := Func("ClipDict_FlushPendingSave")
    SetTimer, %saveFn%, -600
}

ClipDict_FlushPendingSave() {
    index := ClipDict_PendingSave
    if (!index)
        return
    ClipDict_PendingSave := 0
    ClipDict_SaveDict(index)
    ClipDict_RefreshDictChoices()
}

; ファイル形式: "#name<TAB>名前" / "#case<TAB>1" の後に 1行1件 "検索<TAB>置換<TAB>種別(r=正規表現)"。
; その他の # 行はコメント。値中の \ TAB CR LF と先頭の # はエスケープして保存する。
ClipDict_LoadDict(path, index) {
    dict := ClipDict_NewDict(index)
    if !FileExist(path)
        return dict
    file := FileOpen(path, "r", "UTF-8")
    if !IsObject(file)
        return dict
    content := file.Read()
    file.Close()

    Loop, Parse, content, `n
    {
        line := RTrim(A_LoopField, "`r")
        if (line = "")
            continue
        if (SubStr(line, 1, 1) = "#") {
            if RegExMatch(line, "^#(name|case)\t(.*)$", meta) {
                if (meta1 = "name")
                    dict.Name := ClipDict_Unescape(meta2)
                else
                    dict.CaseSensitive := meta2 ? 1 : 0
            }
            continue
        }
        fields := StrSplit(line, "`t")
        from := ClipDict_Unescape(fields[1])
        if (from = "")
            continue
        dict.Entries.Push({From: from, To: ClipDict_Unescape(fields[2]), Regex: InStr(fields[3], "r") ? 1 : 0})
    }
    return dict
}

ClipDict_SaveDict(index) {
    dict := ClipDict_GetDict(index)
    path := ClipDict_DictPath(index)
    SplitPath, path,, dir
    if !InStr(FileExist(dir), "D") {
        FileCreateDir, %dir%
        if (ErrorLevel)
            return false
    }

    content := "# ClipDict 辞書 (UTF-8)  1行1件: 検索<TAB>置換<TAB>種別(r=正規表現)`r`n"
        . "# 値の中の \ TAB CR LF は \\ \t \r \n、先頭の # は \# と書く`r`n"
        . "#name`t" . ClipDict_Escape(dict.Name) . "`r`n"
        . "#case`t" . (dict.CaseSensitive ? 1 : 0) . "`r`n"
    for _, entry in dict.Entries
        content .= ClipDict_Escape(entry.From) . "`t" . ClipDict_Escape(entry.To) . "`t" . (entry.Regex ? "r" : "") . "`r`n"

    tempPath := path . ".tmp"
    file := FileOpen(tempPath, "w", "UTF-8")
    if !IsObject(file)
        return false
    file.Write(content)
    file.Close()
    FileMove, %tempPath%, %path%, 1
    return !ErrorLevel
}

ClipDict_Escape(text) {
    text := StrReplace(text, "\", "\\")
    text := StrReplace(text, "`t", "\t")
    text := StrReplace(text, "`r", "\r")
    text := StrReplace(text, "`n", "\n")
    if (SubStr(text, 1, 1) = "#")
        text := "\" . text
    return text
}

; \\ \t \r \n \# を復元する。それ以外の \ はそのまま残す。
ClipDict_Unescape(text) {
    if !InStr(text, "\")
        return text
    out := ""
    length := StrLen(text)
    pos := 1
    while (pos <= length) {
        char := SubStr(text, pos, 1)
        if (char = "\" && pos < length) {
            nextChar := SubStr(text, pos + 1, 1)
            mapped := ""
            if (nextChar == "\")
                mapped := "\"
            else if (nextChar == "t")
                mapped := "`t"
            else if (nextChar == "r")
                mapped := "`r"
            else if (nextChar == "n")
                mapped := "`n"
            else if (nextChar == "#")
                mapped := "#"
            if (mapped != "") {
                char := mapped
                pos += 1
            }
        }
        out .= char
        pos += 1
    }
    return out
}
