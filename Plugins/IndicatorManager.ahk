; ==============================================================================
; Indicator / settings UI
; TreeView (checkboxes) + ListView (hotkey help)
; ==============================================================================
global _SUI_ItemMap := {}
global _SUI_HelpData := {}
global _SUI_ParentIDs := []
global _SUI_PendingID := 0
global _SUI_CheckStateMap := {}
global SUI_SettingsGuiHwnd := 0
global SUI_SubSettingsGuiHwnd := 0
global SettingsTree := ""
global SettingsLV := ""
global RadioNotepads := 0
global RadioStandard := 0
global SUI_DebugEnabled := true
global SUI_DebugLogDir := A_ScriptDir . "\.claude"
global SUI_DebugLogPath := SUI_DebugLogDir . "\indicator_manager_debug.log"
global SUI_DebugMaxBytes := 262144

Indicator_Init() {
    SUI_DebugInit()
    SUI_RegisterMessageHandlers()
    SettingsUI.Init()
}

Settings_Open() {
    SUI_DebugLog("settings_open")
    SettingsUI.Show()
}

Settings_Close() {
    global SUI_SettingsGuiHwnd, SUI_SubSettingsGuiHwnd, _SUI_PendingID

    SUI_FlushPendingChange("close")
    SUI_DebugLog("settings_close")
    Gui, Settings:Destroy
    Gui, SubSettings:Destroy
    SUI_SettingsGuiHwnd := 0
    SUI_SubSettingsGuiHwnd := 0
    _SUI_PendingID := 0
}

SUI_DebugInit() {
    global SUI_DebugEnabled

    if (!SUI_DebugEnabled)
        return

    SUI_DebugEnsureLogDir()
    SUI_DebugLog("startup", "script=" . A_ScriptFullPath)
}

SUI_DebugEnsureLogDir() {
    global SUI_DebugLogDir

    if !InStr(FileExist(SUI_DebugLogDir), "D")
        FileCreateDir, %SUI_DebugLogDir%
}

SUI_DebugRotateIfNeeded() {
    global SUI_DebugLogPath, SUI_DebugMaxBytes

    if !FileExist(SUI_DebugLogPath)
        return

    FileGetSize, logSize, %SUI_DebugLogPath%
    if (logSize < SUI_DebugMaxBytes)
        return

    backupPath := RegExReplace(SUI_DebugLogPath, "\.log$", ".old.log")
    FileDelete, %backupPath%
    FileMove, %SUI_DebugLogPath%, %backupPath%, 1
}

SUI_DebugSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

SUI_DebugFlagsText() {
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableBrowser, EnablePPT, EnableExcel

    return "EnableNavLayer=" . EnableNavLayer
        . " EnableWinPlace=" . EnableWinPlace
        . " EnableWinIsland=" . EnableWinIsland
        . " EnableVDesk=" . EnableVDesk
        . " EnableMouseEmu=" . EnableMouseEmu
        . " EnableMouseBtn=" . EnableMouseBtn
        . " EnableGestures=" . EnableGestures
        . " EnableBrowser=" . EnableBrowser
        . " EnablePPT=" . EnablePPT
        . " EnableExcel=" . EnableExcel
}

SUI_DebugDescribeItem(itemID) {
    global _SUI_ItemMap, _SUI_CheckStateMap

    if (!itemID || !_SUI_ItemMap.HasKey(itemID))
        return "itemID=" . itemID . " missing=1"

    item := _SUI_ItemMap[itemID]
    currentState := TV_Get(itemID, "Check") ? 1 : 0
    prevState := _SUI_CheckStateMap.HasKey(itemID) ? _SUI_CheckStateMap[itemID] : "?"

    return "itemID=" . itemID
        . " var=" . item.Var
        . " isParent=" . item.IsParent
        . " parentID=" . item.ParentID
        . " prev=" . prevState
        . " cur=" . currentState
}

SUI_DebugLog(event, extra := "") {
    global SUI_DebugEnabled, SUI_DebugLogPath

    if (!SUI_DebugEnabled)
        return

    SUI_DebugEnsureLogDir()
    SUI_DebugRotateIfNeeded()

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " extra=" . SUI_DebugSanitize(extra)
    line .= " " . SUI_DebugFlagsText()
    FileAppend, % line . "`n", %SUI_DebugLogPath%, UTF-8
}

SUI_DebugOpenLog() {
    global SUI_DebugLogPath

    SUI_DebugEnsureLogDir()
    if !FileExist(SUI_DebugLogPath)
        FileAppend,, %SUI_DebugLogPath%, UTF-8
    Run, notepad.exe "%SUI_DebugLogPath%"
}

SUI_RegisterMessageHandlers() {
    static isRegistered := false

    if (isRegistered)
        return

    OnMessage(0x0010, "SUI_HandleWmClose")
    isRegistered := true
}

SUI_HandleWmClose(wParam, lParam, msg, hwnd) {
    global SUI_SettingsGuiHwnd, SUI_SubSettingsGuiHwnd

    if (hwnd = SUI_SettingsGuiHwnd) {
        Settings_Close()
        return 0
    }

    if (hwnd = SUI_SubSettingsGuiHwnd) {
        Gui, SubSettings:Destroy
        SUI_SubSettingsGuiHwnd := 0
        return 0
    }
}

class SettingsUI {
    static EditorType := 1

    Init() {
        Global StartupShortcutPath, TargetScriptPath
        TargetScriptPath := A_ScriptDir . "\main.ahk"
        StartupShortcutPath := A_Startup . "\ahk_main_shorcut.lnk"

        Menu, Tray, Add
        Menu, Tray, Add, スタートアップで実行する, Startup_Toggle
        Menu, Tray, Add, 機能設定 (Settings), Settings_Open
        Menu, Tray, Add, 設定ログを開く, SUI_DebugOpenLog
        Menu, Tray, Add
        Menu, Tray, Add, 右クリック状態を記録, MG_DebugSnapshotMenu
        Menu, Tray, Add, 右クリックログを開く, MG_DebugOpenLog

        IfExist, %StartupShortcutPath%
            Menu, Tray, Check, スタートアップで実行する

        SUI_InitHelpData()
    }

    Show() {
        Global SUI_SettingsGuiHwnd, SettingsTree, SettingsLV
        Gui, Settings:Destroy
        Gui, Settings:New, +AlwaysOnTop +HwndhSettingsGui, 機能設定
        SUI_SettingsGuiHwnd := hSettingsGui
        Gui, Settings:Font, s9, Segoe UI

        Gui, Settings:Add, TreeView, x10 y10 w190 h360 vSettingsTree gSUI_TreeHandler Checked -0x4
        Gui, Settings:Add, ListView, x210 y10 w400 h360 vSettingsLV Grid NoSortHdr, ホットキー|説明
        LV_ModifyCol(1, 130)
        LV_ModifyCol(2, 260)

        SUI_BuildTree()
        SUI_SnapshotCheckStates()

        firstID := TV_GetNext()
        if (firstID) {
            TV_Modify(firstID, "Select Vis")
            SUI_RefreshLV(firstID)
        }

        fnDetail := ObjBindMethod(this, "ShowDetailWindow")
        Gui, Settings:Add, Button, x10 y380 w190 g%fnDetail%, エディタ設定...
        Gui, Settings:Show, w630 h420 xCenter yCenter
        SUI_DebugLog("settings_show")
    }

    ShowDetailWindow() {
        Global SUI_SubSettingsGuiHwnd, RadioNotepads, RadioStandard
        Gui, SubSettings:Destroy
        Gui, SubSettings:New, +OwnerSettings +AlwaysOnTop +ToolWindow +HwndhSubSettingsGui, エディタ選択
        SUI_SubSettingsGuiHwnd := hSubSettingsGui
        Gui, SubSettings:Font, s9, Segoe UI

        fnEditor := ObjBindMethod(this, "OnEditorChange")
        Gui, SubSettings:Add, GroupBox, xm ym w250 h80, デフォルトエディタ

        check1 := (this.EditorType = 1) ? "Checked" : ""
        check2 := (this.EditorType = 2) ? "Checked" : ""
        Gui, SubSettings:Add, Radio, xs+10 ys+25 vRadioNotepads g%fnEditor% %check1%, Notepads (UWP)
        Gui, SubSettings:Add, Radio, x+10 vRadioStandard g%fnEditor% %check2%, notepad.exe (標準)
        Gui, SubSettings:Show, AutoSize Center
    }

    OnEditorChange() {
        Global RadioNotepads, RadioStandard
        Gui, SubSettings:Submit, NoHide
        if (RadioNotepads = 1)
            this.EditorType := 1
        else
            this.EditorType := 2
    }
}

SUI_InitHelpData() {
    global _SUI_HelpData
    d := {}

    h := []
    h.Push({Key: "無変換 + Q", Desc: "IME → 英語"})
    h.Push({Key: "無変換 + W", Desc: "IME → 日本語"})
    h.Push({Key: "無変換 + J / K / I / L", Desc: "カーソル移動 (←↓↑→)"})
    h.Push({Key: "無変換 + U / O", Desc: "Home / End"})
    h.Push({Key: "無変換 + P", Desc: "リネーム (F2)"})
    h.Push({Key: "無変換 + 1", Desc: "Ctrl+Shift+6"})
    h.Push({Key: "無変換 + 2", Desc: "Ctrl+Shift+2"})
    h.Push({Key: "無変換 + N", Desc: "ペイント起動"})
    h.Push({Key: "無変換 + M", Desc: "テキストエディタ起動"})
    h.Push({Key: "無変換 + T", Desc: "日時挿入"})
    d["EnableNavLayer"] := h

    h := []
    h.Push({Key: "Ctrl+Win+B", Desc: "ウィンドウ情報取得"})
    h.Push({Key: "Shift+Win+K", Desc: "Bluetooth設定"})
    h.Push({Key: "Ctrl+Win+1~4", Desc: "右側プリセット配置"})
    h.Push({Key: "Ctrl+Shift+Win+1/2/4", Desc: "左側プリセット配置"})
    h.Push({Key: "Ctrl+Win+8", Desc: "高さ最大化 (上寄せ)"})
    h.Push({Key: "Ctrl+Shift+Win+8", Desc: "高さ最大化 (下寄せ)"})
    h.Push({Key: "Ctrl+Win+G", Desc: "Gridモード切替"})
    h.Push({Key: "Ctrl+Shift+Win+G", Desc: "Window Island 切替"})
    h.Push({Key: "Ctrl+Win+J/K/I/L", Desc: "Grid移動 (←↓↑→)"})
    h.Push({Key: "Ctrl+Shift+Win+J/K/I/L", Desc: "Gridリサイズ"})
    h.Push({Key: "Ctrl+Win+F11", Desc: "Downloadsフォルダ"})
    h.Push({Key: "Ctrl+Win+F12", Desc: "VSCode起動"})
    h.Push({Key: "Ctrl+Shift+Win+F12", Desc: "スクリプトリロード"})
    d["EnableWinPlace"] := h

    h := []
    h.Push({Key: "Win+Q", Desc: "左の仮想デスクトップへ"})
    h.Push({Key: "Win+W", Desc: "右の仮想デスクトップへ"})
    d["EnableVDesk"] := h

    h := []
    h.Push({Key: "F13 + O/K/L/;", Desc: "カーソル移動 (↑←↓→)"})
    h.Push({Key: "Ctrl+F13 + O/K/L/;", Desc: "グリッドジャンプ"})
    h.Push({Key: "F13 + I", Desc: "左クリック (押下/解放)"})
    h.Push({Key: "F13 + .", Desc: "中クリック"})
    h.Push({Key: "F13 + P", Desc: "右クリック (押下/解放)"})
    d["EnableMouseEmu"] := h

    h := []
    h.Push({Key: "F15", Desc: "Ctrl+V (貼り付け)"})
    h.Push({Key: "F16", Desc: "Ctrl+C (コピー)"})
    h.Push({Key: "F17", Desc: "Ctrl+W (タブ閉じ)"})
    h.Push({Key: "XButton1", Desc: "戻る"})
    h.Push({Key: "XButton2", Desc: "進む"})
    h.Push({Key: "F15 + MButton", Desc: "メディア再生/一時停止"})
    h.Push({Key: "XButton1 + Wheel", Desc: "横スクロール"})
    h.Push({Key: "XButton2 + Wheel", Desc: "ズーム (拡大/縮小)"})
    h.Push({Key: "F15 + Wheel", Desc: "音量 (上げ/下げ)"})
    h.Push({Key: "F16 + Wheel", Desc: "Alt+Tab (前/次)"})
    d["EnableMouseBtn"] := h

    h := []
    h.Push({Key: "右ドラッグ", Desc: "ジェスチャー認識 (8方向)"})
    h.Push({Key: "右 + WheelUp", Desc: "Ctrl+Home (先頭へ)"})
    h.Push({Key: "右 + WheelDown", Desc: "Ctrl+End (末尾へ)"})
    d["EnableGestures"] := h

    h := []
    h.Push({Key: "Ctrl+\", Desc: "PDFズーム切替"})
    h.Push({Key: "F1", Desc: "サイト固有キー"})
    h.Push({Key: "F2", Desc: "サイト固有キー"})
    h.Push({Key: "Ctrl+Shift+C", Desc: "プレーンURLコピー"})
    h.Push({Key: "F8", Desc: "全タブURL取得"})
    d["EnableBrowser"] := h

    h := []
    h.Push({Key: "Ctrl+Alt+J/L/I/K", Desc: "左/右/上/下揃え"})
    h.Push({Key: "Ctrl+Alt+U/O", Desc: "水平/垂直中央揃え"})
    h.Push({Key: "Ctrl+Alt+M", Desc: "水平等間隔"})
    h.Push({Key: "Ctrl+Alt+.", Desc: "垂直等間隔"})
    h.Push({Key: "Ctrl+Alt+G/H", Desc: "グループ化/解除"})
    h.Push({Key: "Ctrl+Shift+Alt+G/H", Desc: "前面/背面"})
    h.Push({Key: "Alt+1", Desc: "テキストのみ貼り付け"})
    h.Push({Key: "Alt+2", Desc: "枠線色"})
    h.Push({Key: "Alt+3", Desc: "枠線太さ"})
    h.Push({Key: "Alt+4", Desc: "書式設定パネル"})
    h.Push({Key: "Ctrl+V / F15", Desc: "画像メタデータ付き貼付け"})
    h.Push({Key: "Ctrl+Alt+E", Desc: "ソースエクスポート"})
    h.Push({Key: "Ctrl+Alt+Q", Desc: "ソース情報表示"})
    d["EnablePPT"] := h

    h := []
    h.Push({Key: "Ctrl+Tab", Desc: "次のシート"})
    h.Push({Key: "Ctrl+Shift+Tab", Desc: "前のシート"})
    d["EnableExcel"] := h

    _SUI_HelpData := d
}

SUI_BuildTree() {
    global _SUI_ItemMap, _SUI_ParentIDs
    Gui, Settings:Default
    _SUI_ItemMap := {}
    _SUI_ParentIDs := []

    SUI_AddLeaf("キーボード拡張", "EnableNavLayer", 0)
    SUI_AddLeaf("ウィンドウ配置", "EnableWinPlace", 0)
    SUI_AddLeaf("仮想デスクトップ", "EnableVDesk", 0)
    SUI_AddLeaf("キーボードマウス", "EnableMouseEmu", 0)
    SUI_AddLeaf("ボタン・ホイール", "EnableMouseBtn", 0)
    SUI_AddLeaf("マウスジェスチャー", "EnableGestures", 0)
    SUI_AddLeaf("ブラウザ", "EnableBrowser", 0)
    SUI_AddLeaf("PowerPoint", "EnablePPT", 0)
    SUI_AddLeaf("Excel", "EnableExcel", 0)
}

SUI_AddParent(name) {
    global _SUI_ItemMap, _SUI_ParentIDs
    pID := TV_Add(name, 0, "Expand Bold")
    _SUI_ItemMap[pID] := {Var: "", IsParent: true, ParentID: 0, ChildIDs: []}
    _SUI_ParentIDs.Push(pID)
    return pID
}

SUI_AddLeaf(name, varName, parentID) {
    global _SUI_ItemMap
    val := SUI_GetFlagValue(varName)
    opts := ""
    if (val)
        opts .= " Check"
    leafID := TV_Add(name, parentID, opts)
    _SUI_ItemMap[leafID] := {Var: varName, IsParent: false, ParentID: parentID}
    if (parentID && _SUI_ItemMap.HasKey(parentID))
        _SUI_ItemMap[parentID].ChildIDs.Push(leafID)
    return leafID
}

SUI_FinalizeParent(parentID) {
    global _SUI_ItemMap
    if (!_SUI_ItemMap.HasKey(parentID))
        return
    SUI_SyncParent(parentID)
}

SUI_TreeHandler() {
    global _SUI_PendingID
    Gui, Settings:Default
    evt := A_GuiEvent
    info := A_EventInfo
    currentSelID := TV_GetSelection()
    targetID := (evt = "Normal" && info) ? info : currentSelID

    if (evt = "Normal") {
        if (info && info != currentSelID)
            TV_Modify(info, "Select Vis")
        else if (info)
            SUI_RefreshLV(info)

        _SUI_PendingID := info
        fn := Func("SUI_AfterClick")
        SetTimer, %fn%, -30
    } else if (evt = "S") {
        SUI_RefreshLV(info)
    } else if (evt = "K") {
        SUI_RefreshLV(currentSelID)
        if (info = 32) {
            _SUI_PendingID := currentSelID
            fn := Func("SUI_AfterClick")
            SetTimer, %fn%, -30
        }
    }

    SUI_DebugLog("tree_event"
        , "evt=" . evt
        . " info=" . info
        . " selID=" . currentSelID
        . " targetID=" . targetID
        . " " . SUI_DebugDescribeItem(targetID))
}

SUI_AfterClick() {
    global _SUI_PendingID

    clickedID := _SUI_PendingID
    _SUI_PendingID := 0
    if (!clickedID)
        return

    Gui, Settings:Default
    TV_Modify(clickedID, "Select Vis")
    SUI_RefreshLV(clickedID)
    SUI_ProcessClick(clickedID, "timer")
}

SUI_ProcessClick(clickedID, source := "manual") {
    global _SUI_ItemMap
    Gui, Settings:Default

    if (!clickedID || !_SUI_ItemMap.HasKey(clickedID))
        return false

    if !SUI_DidCheckStateChange(clickedID) {
        SUI_DebugLog("after_click_nochange"
            , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))
        return false
    }

    item := _SUI_ItemMap[clickedID]
    SUI_DebugLog("after_click_apply"
        , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))

    SUI_SyncVars()
    SUI_SnapshotCheckStates()
    SUI_DebugLog("after_click_done"
        , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))
    return true
}

SUI_FlushPendingChange(reason := "manual") {
    global SUI_SettingsGuiHwnd, _SUI_PendingID

    if !(SUI_SettingsGuiHwnd && DllCall("IsWindow", "Ptr", SUI_SettingsGuiHwnd))
        return

    Gui, Settings:Default
    if !SUI_ProcessClick(_SUI_PendingID, "flush-" . reason) {
        SUI_SyncVars()
        SUI_SnapshotCheckStates()
    }

    _SUI_PendingID := 0
    static timerFn := Func("SUI_AfterClick")
    SetTimer, %timerFn%, Off
    SUI_DebugLog("flush_done", "reason=" . reason)
}

SUI_RefreshLV(targetID) {
    global _SUI_ItemMap, _SUI_HelpData, SettingsLV
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsLV
    LV_Delete()

    if (!targetID || !_SUI_ItemMap.HasKey(targetID))
        return

    item := _SUI_ItemMap[targetID]
    vars := []

    if (item.Var != "") {
        vars.Push(item.Var)
    }

    for _, varName in vars {
        if (_SUI_HelpData.HasKey(varName)) {
            for _, entry in _SUI_HelpData[varName]
                LV_Add("", entry.Key, entry.Desc)
        }
    }

    LV_ModifyCol(1, 130)
    LV_ModifyCol(2, 260)
}

SUI_SyncVars() {
    global _SUI_ItemMap
    global EnableNavLayer, EnableWinPlace, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableBrowser, EnablePPT, EnableExcel
    Gui, Settings:Default

    for itemID, item in _SUI_ItemMap {
        if (item.IsParent || item.Var = "")
            continue

        v := TV_Get(itemID, "Check") ? 1 : 0
        if (item.Var = "EnableNavLayer")
            EnableNavLayer := v
        else if (item.Var = "EnableWinPlace")
            EnableWinPlace := v
        else if (item.Var = "EnableVDesk")
            EnableVDesk := v
        else if (item.Var = "EnableMouseEmu")
            EnableMouseEmu := v
        else if (item.Var = "EnableMouseBtn")
            EnableMouseBtn := v
        else if (item.Var = "EnableGestures")
            EnableGestures := v
        else if (item.Var = "EnableBrowser")
            EnableBrowser := v
        else if (item.Var = "EnablePPT")
            EnablePPT := v
        else if (item.Var = "EnableExcel")
            EnableExcel := v
    }

    SUI_DebugLog("sync_vars")
}

SUI_SyncAllParents() {
    global _SUI_ParentIDs

    for _, parentID in _SUI_ParentIDs
        SUI_SyncParent(parentID)
}

SUI_SyncParent(parentID) {
    global _SUI_ItemMap

    if (!_SUI_ItemMap.HasKey(parentID))
        return

    parent := _SUI_ItemMap[parentID]
    allChecked := true
    for _, childID in parent.ChildIDs {
        if !TV_Get(childID, "Check") {
            allChecked := false
            break
        }
    }

    if (allChecked)
        TV_Modify(parentID, "Check")
    else
        TV_Modify(parentID, "-Check")
}

SUI_GetFlagValue(varName) {
    global EnableNavLayer, EnableWinPlace, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableBrowser, EnablePPT, EnableExcel

    if (varName = "EnableNavLayer")
        return EnableNavLayer
    if (varName = "EnableWinPlace")
        return EnableWinPlace
    if (varName = "EnableVDesk")
        return EnableVDesk
    if (varName = "EnableMouseEmu")
        return EnableMouseEmu
    if (varName = "EnableMouseBtn")
        return EnableMouseBtn
    if (varName = "EnableGestures")
        return EnableGestures
    if (varName = "EnableBrowser")
        return EnableBrowser
    if (varName = "EnablePPT")
        return EnablePPT
    if (varName = "EnableExcel")
        return EnableExcel
    return 0
}

SUI_DidCheckStateChange(itemID) {
    global _SUI_ItemMap, _SUI_CheckStateMap

    if (!itemID || !_SUI_ItemMap.HasKey(itemID))
        return false

    currentState := TV_Get(itemID, "Check") ? 1 : 0
    if !_SUI_CheckStateMap.HasKey(itemID)
        return false

    return (_SUI_CheckStateMap[itemID] != currentState)
}

SUI_SnapshotCheckStates() {
    global _SUI_ItemMap, _SUI_CheckStateMap

    _SUI_CheckStateMap := {}
    for itemID, item in _SUI_ItemMap
        _SUI_CheckStateMap[itemID] := TV_Get(itemID, "Check") ? 1 : 0
}

Startup_Toggle(ItemName, ItemPos := "", MenuName := "") {
    Global StartupShortcutPath, TargetScriptPath
    if (ItemName = "")
        return
    IfNotExist, %TargetScriptPath%
    {
        MsgBox, 16, エラー, 同一フォルダに main.ahk が見つかりません。`n%TargetScriptPath%
        return
    }
    IfExist, %StartupShortcutPath%
    {
        FileDelete, %StartupShortcutPath%
        if (ErrorLevel = 0) {
            Menu, Tray, Uncheck, %ItemName%
            MsgBox, 64, 設定変更, スタートアップから削除しました。
        } else {
            MsgBox, 16, エラー, 削除に失敗しました。`n%StartupShortcutPath%
        }
    }
    Else
    {
        FileCreateShortcut, %TargetScriptPath%, %StartupShortcutPath%, %A_ScriptDir%
        if (ErrorLevel = 0) {
            Menu, Tray, Check, %ItemName%
            MsgBox, 64, 設定変更, スタートアップに登録しました。
        } else {
            MsgBox, 16, エラー, 作成に失敗しました。
        }
    }
}
