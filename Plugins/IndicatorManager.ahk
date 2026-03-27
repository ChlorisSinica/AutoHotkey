; ==============================================================================
; Indicator / settings UI
; ListView (checkboxes + labels) + ListView (hotkey help)
; ==============================================================================
global _SUI_ItemMap := {}
global _SUI_HelpData := {}
global _SUI_CheckStateMap := {}
global SUI_SettingsGuiHwnd := 0
global SUI_SubSettingsGuiHwnd := 0
global SettingsItemsLV := ""
global SettingsLV := ""
global RadioNotepads := 0
global RadioStandard := 0
global SUI_IsInitializing := false
global _SUI_PendingCheckItemID := 0
global _SUI_PendingCheckSource := ""
global SUI_DebugEnabled := true
global SUI_DebugLogDir := A_ScriptDir . "\.claude"
global SUI_DebugLogPath := SUI_DebugLogDir . "\indicator_manager_debug.log"
global SUI_DebugMaxBytes := 262144
global SUI_ConfigPath := A_ScriptDir . "\Plugins\indicator_settings.ini"

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
    global SUI_SettingsGuiHwnd, SUI_SubSettingsGuiHwnd

    SUI_FlushPendingChange("close")
    SUI_DebugLog("settings_close")
    Gui, Settings:Destroy
    Gui, SubSettings:Destroy
    SUI_SettingsGuiHwnd := 0
    SUI_SubSettingsGuiHwnd := 0
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
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel

    return "EnableNavLayer=" . EnableNavLayer
        . " EnableWinPlace=" . EnableWinPlace
        . " EnableWinIsland=" . EnableWinIsland
        . " EnableVDesk=" . EnableVDesk
        . " EnableMouseEmu=" . EnableMouseEmu
        . " EnableMouseBtn=" . EnableMouseBtn
        . " EnableGestures=" . EnableGestures
        . " EnableAlt=" . EnableAlt
        . " EnableOthers=" . EnableOthers
        . " EnableBrowser=" . EnableBrowser
        . " EnablePPT=" . EnablePPT
        . " EnableExcel=" . EnableExcel
}

SUI_DebugDescribeItem(itemID) {
    global _SUI_ItemMap, _SUI_CheckStateMap

    if (!itemID || !_SUI_ItemMap.HasKey(itemID))
        return "itemID=" . itemID . " missing=1"

    item := _SUI_ItemMap[itemID]
    currentState := SUI_IsItemChecked(itemID) ? 1 : 0
    prevState := _SUI_CheckStateMap.HasKey(itemID) ? _SUI_CheckStateMap[itemID] : "?"

    return "itemID=" . itemID
        . " var=" . item.Var
        . " row=" . item.Row
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

SUI_NormalizeBool(value, defaultValue := 0) {
    value := Trim(value)
    if (value = "")
        return defaultValue ? 1 : 0
    if (value ~= "i)^(1|true|on|yes)$")
        return 1
    if (value ~= "i)^(0|false|off|no)$")
        return 0
    return defaultValue ? 1 : 0
}

SUI_NormalizeEditorType(value, defaultValue := 1) {
    value := Trim(value)
    if (value = "1" || value = "2")
        return value + 0
    return (defaultValue = 2) ? 2 : 1
}

SUI_LoadConfig() {
    global SUI_ConfigPath
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel

    IniRead, navLayerRaw, %SUI_ConfigPath%, Indicators, EnableNavLayer, %EnableNavLayer%
    IniRead, winPlaceRaw, %SUI_ConfigPath%, Indicators, EnableWinPlace, %EnableWinPlace%
    IniRead, winIslandRaw, %SUI_ConfigPath%, Indicators, EnableWinIsland, %EnableWinIsland%
    IniRead, vdeskRaw, %SUI_ConfigPath%, Indicators, EnableVDesk, %EnableVDesk%
    IniRead, mouseEmuRaw, %SUI_ConfigPath%, Indicators, EnableMouseEmu, %EnableMouseEmu%
    IniRead, mouseBtnRaw, %SUI_ConfigPath%, Indicators, EnableMouseBtn, %EnableMouseBtn%
    IniRead, gesturesRaw, %SUI_ConfigPath%, Indicators, EnableGestures, %EnableGestures%
    IniRead, altRaw, %SUI_ConfigPath%, Indicators, EnableAlt, %EnableAlt%
    IniRead, othersRaw, %SUI_ConfigPath%, Indicators, EnableOthers, %EnableOthers%
    IniRead, browserRaw, %SUI_ConfigPath%, Indicators, EnableBrowser, %EnableBrowser%
    IniRead, pptRaw, %SUI_ConfigPath%, Indicators, EnablePPT, %EnablePPT%
    IniRead, excelRaw, %SUI_ConfigPath%, Indicators, EnableExcel, %EnableExcel%

    EnableNavLayer := SUI_NormalizeBool(navLayerRaw, EnableNavLayer)
    EnableWinPlace := SUI_NormalizeBool(winPlaceRaw, EnableWinPlace)
    EnableWinIsland := SUI_NormalizeBool(winIslandRaw, EnableWinIsland)
    EnableVDesk := SUI_NormalizeBool(vdeskRaw, EnableVDesk)
    EnableMouseEmu := SUI_NormalizeBool(mouseEmuRaw, EnableMouseEmu)
    EnableMouseBtn := SUI_NormalizeBool(mouseBtnRaw, EnableMouseBtn)
    EnableGestures := SUI_NormalizeBool(gesturesRaw, EnableGestures)
    EnableAlt := SUI_NormalizeBool(altRaw, EnableAlt)
    EnableOthers := SUI_NormalizeBool(othersRaw, EnableOthers)
    EnableBrowser := SUI_NormalizeBool(browserRaw, EnableBrowser)
    EnablePPT := SUI_NormalizeBool(pptRaw, EnablePPT)
    EnableExcel := SUI_NormalizeBool(excelRaw, EnableExcel)

    IniRead, editorTypeRaw, %SUI_ConfigPath%, SettingsUI, EditorType, % SettingsUI.EditorType
    SettingsUI.EditorType := SUI_NormalizeEditorType(editorTypeRaw, SettingsUI.EditorType)

    SUI_DebugLog("config_load", "path=" . SUI_ConfigPath)
}

SUI_SaveConfig() {
    global SUI_ConfigPath
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel

    IniWrite, % EnableNavLayer ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableNavLayer
    IniWrite, % EnableWinPlace ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableWinPlace
    IniWrite, % EnableWinIsland ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableWinIsland
    IniWrite, % EnableVDesk ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableVDesk
    IniWrite, % EnableMouseEmu ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableMouseEmu
    IniWrite, % EnableMouseBtn ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableMouseBtn
    IniWrite, % EnableGestures ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableGestures
    IniWrite, % EnableAlt ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableAlt
    IniWrite, % EnableOthers ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableOthers
    IniWrite, % EnableBrowser ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableBrowser
    IniWrite, % EnablePPT ? 1 : 0, %SUI_ConfigPath%, Indicators, EnablePPT
    IniWrite, % EnableExcel ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableExcel
    IniWrite, % SettingsUI.EditorType, %SUI_ConfigPath%, SettingsUI, EditorType

    SUI_DebugLog("config_save", "path=" . SUI_ConfigPath)
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
        Menu, Tray, Add, PPT 間隔ログを開く, PPT_SpacingOpenLog
        Menu, Tray, Add, PPT キャプションログを開く, PPT_CaptionOpenLog
        Menu, Tray, Add
        Menu, Tray, Add, 右クリック状態を記録, MG_DebugSnapshotMenu
        Menu, Tray, Add, 右クリックログを開く, MG_DebugOpenLog

        IfExist, %StartupShortcutPath%
            Menu, Tray, Check, スタートアップで実行する

        SUI_InitHelpData()
    }

    Show() {
        Global SUI_SettingsGuiHwnd, SettingsItemsLV, SettingsLV, SUI_IsInitializing
        SUI_IsInitializing := true
        Gui, Settings:Destroy
        Gui, Settings:New, +AlwaysOnTop +HwndhSettingsGui, 機能設定
        SUI_SettingsGuiHwnd := hSettingsGui
        Gui, Settings:Font, s9, Segoe UI

        Gui, Settings:Add, ListView, x10 y10 w190 h360 vSettingsItemsLV gSUI_ItemsHandler Checked AltSubmit -Multi -Hdr +LV0x20, |機能
        Gui, Settings:Add, ListView, x210 y10 w400 h360 vSettingsLV gSUI_HelpHandler Grid NoSortHdr -Multi -TabStop, ホットキー|説明

        SUI_BuildItemList()
        Gui, Settings:ListView, SettingsItemsLV
        LV_ModifyCol(1, 28)
        LV_ModifyCol(2, 138)

        Gui, Settings:ListView, SettingsLV
        LV_ModifyCol(1, 130)
        LV_ModifyCol(2, 260)
        SUI_SnapshotCheckStates()

        Gui, Settings:ListView, SettingsItemsLV
        firstID := LV_GetCount() ? 1 : 0
        if (firstID) {
            LV_Modify(firstID, "Select Focus Vis")
            SUI_RefreshLV(firstID)
        }

        fnDetail := ObjBindMethod(this, "ShowDetailWindow")
        Gui, Settings:Add, Button, x10 y380 w190 g%fnDetail%, エディタ設定...
        Gui, Settings:Show, w630 h420 xCenter yCenter
        SUI_IsInitializing := false
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
        SUI_SaveConfig()
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
    h.Push({Key: "無変換 + T", Desc: "日時挿入 (yyyy/MM/dd (ddd) HH:mm)"})
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
    h.Push({Key: "【基本】", Desc: ""})
    h.Push({Key: "右ドラッグ", Desc: "8 方向ジェスチャー"})
    h.Push({Key: "右 + WheelUp", Desc: "Ctrl+Home (先頭へ)"})
    h.Push({Key: "右 + WheelDown", Desc: "Ctrl+End (末尾へ)"})
    h.Push({Key: "", Desc: ""})
    h.Push({Key: "【Browser】", Desc: ""})
    h.Push({Key: "↗", Desc: "WinMinimize, A"})
    h.Push({Key: "↙", Desc: "Send, ^+t"})
    h.Push({Key: "↖", Desc: "Send, ^1"})
    h.Push({Key: "↘", Desc: "Send, ^9"})
    h.Push({Key: "→", Desc: "Send, ^{Tab}"})
    h.Push({Key: "←", Desc: "Send, ^+{Tab}"})
    h.Push({Key: "↓", Desc: "Send, ^w"})
    h.Push({Key: "↑", Desc: "Send, ^t"})
    h.Push({Key: "", Desc: ""})
    h.Push({Key: "【Explorer】", Desc: ""})
    h.Push({Key: "↗", Desc: "WinMinimize, A"})
    h.Push({Key: "↙", Desc: "Send, ^z"})
    h.Push({Key: "↖", Desc: "Send, ^1"})
    h.Push({Key: "↘", Desc: "Send, ^1^+{Tab}"})
    h.Push({Key: "→", Desc: "Send, ^{Tab}"})
    h.Push({Key: "←", Desc: "Send, ^+{Tab}"})
    h.Push({Key: "↓", Desc: "Send, ^w"})
    h.Push({Key: "↑", Desc: "Send, ^t"})
    h.Push({Key: "", Desc: ""})
    h.Push({Key: "【Editor】", Desc: ""})
    h.Push({Key: "→", Desc: "Send, ^{Tab}"})
    h.Push({Key: "←", Desc: "Send, ^+{Tab}"})
    h.Push({Key: "↓", Desc: "Send, ^w"})
    h.Push({Key: "↑", Desc: "Send, ^t"})
    h.Push({Key: "other", Desc: "Map_Default"})
    h.Push({Key: "", Desc: ""})
    h.Push({Key: "【Pycharm】", Desc: ""})
    h.Push({Key: "→", Desc: "Send, !{Right}"})
    h.Push({Key: "←", Desc: "Send, !{Left}"})
    h.Push({Key: "↓", Desc: "Send, ^{F4}"})
    h.Push({Key: "↑", Desc: "Send, ^!{Insert}"})
    h.Push({Key: "other", Desc: "Map_Default"})
    h.Push({Key: "", Desc: ""})
    h.Push({Key: "【Default】", Desc: ""})
    h.Push({Key: "↗", Desc: "WinMinimize, A"})
    d["EnableGestures"] := h

    h := []
    h.Push({Key: "Alt+W", Desc: "ウィンドウを閉じる"})
    h.Push({Key: "Ctrl+Alt+C", Desc: "選択内の \\ を / に置換"})
    h.Push({Key: "Ctrl+Alt+N", Desc: "選択ファイルをペイントで開く"})
    h.Push({Key: "Ctrl+Alt+M", Desc: "選択ファイルをエディタで開く"})
    h.Push({Key: "Alt+Backspace", Desc: "Delete"})
    d["EnableAlt"] := h

    h := []
    h.Push({Key: "ScrollLock", Desc: "無効化"})
    h.Push({Key: "\", Desc: "_ を入力"})
    h.Push({Key: "Shift+\", Desc: "\ を入力"})
    h.Push({Key: "無変換 + Z", Desc: "N 長押しトグル"})
    h.Push({Key: "無変換 + X", Desc: "N 長押し解除"})
    d["EnableOthers"] := h

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
    h.Push({Key: "Ctrl+Alt+1/2/3/4", Desc: "上/下/左/右キャプションの設置/削除"})
    h.Push({Key: "Ctrl+Alt+5/6", Desc: "上下キャプション gap 微調整"})
    h.Push({Key: "Ctrl+Alt+7/8", Desc: "左右キャプション gap 微調整"})
    h.Push({Key: "Ctrl+Shift+Alt+5/7", Desc: "キャプション gap 直接設定"})
    h.Push({Key: "Alt+1", Desc: "テキストのみ貼り付け"})
    h.Push({Key: "Alt+2", Desc: "枠線色"})
    h.Push({Key: "Alt+3", Desc: "枠線太さ"})
    h.Push({Key: "Alt+4", Desc: "書式設定パネル開閉"})
    h.Push({Key: "Shift+Alt+4", Desc: "書式設定パネルを閉じる"})
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

SUI_BuildItemList() {
    global _SUI_ItemMap, SettingsItemsLV
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsItemsLV
    LV_Delete()
    _SUI_ItemMap := {}

    SUI_AddLeaf("キーボード拡張", "EnableNavLayer")
    SUI_AddLeaf("ウィンドウ配置", "EnableWinPlace")
    SUI_AddLeaf("仮想デスクトップ", "EnableVDesk")
    SUI_AddLeaf("キーボードマウス", "EnableMouseEmu")
    SUI_AddLeaf("ボタン・ホイール", "EnableMouseBtn")
    SUI_AddLeaf("マウスジェスチャー", "EnableGestures")
    SUI_AddLeaf("Alt", "EnableAlt")
    SUI_AddLeaf("その他", "EnableOthers")
    SUI_AddLeaf("ブラウザ", "EnableBrowser")
    SUI_AddLeaf("PowerPoint", "EnablePPT")
    SUI_AddLeaf("Excel", "EnableExcel")
}

SUI_AddLeaf(name, varName) {
    global _SUI_ItemMap, SettingsItemsLV
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsItemsLV
    val := SUI_GetFlagValue(varName)
    opts := ""
    if (val)
        opts := "Check"
    row := LV_Add(opts, "", name)
    _SUI_ItemMap[row] := {Var: varName, Row: row, Name: name}
    return row
}

SUI_IsItemChecked(itemID) {
    global SettingsItemsLV

    if (!itemID)
        return false

    Gui, Settings:Default
    Gui, Settings:ListView, SettingsItemsLV
    return (LV_GetNext(itemID - 1, "Checked") = itemID)
}

SUI_GetSelectedItemID() {
    global SettingsItemsLV

    Gui, Settings:Default
    Gui, Settings:ListView, SettingsItemsLV
    itemID := LV_GetNext(0, "Focused")
    if (!itemID)
        itemID := LV_GetNext()
    return itemID
}

SUI_QueueCheckSync(itemID, source := "manual") {
    global _SUI_ItemMap, _SUI_PendingCheckItemID, _SUI_PendingCheckSource
    static applyPendingCheckFn := Func("SUI_ApplyPendingCheckChange")

    if (!itemID || !_SUI_ItemMap.HasKey(itemID))
        return

    _SUI_PendingCheckItemID := itemID
    _SUI_PendingCheckSource := source
    SUI_DebugLog("item_check_queue"
        , "source=" . source . " " . SUI_DebugDescribeItem(itemID))
    ; In included files, a top-level label + bare return can terminate auto-execute.
    SetTimer, % applyPendingCheckFn, -10
}

SUI_ApplyPendingCheckChange() {
    global _SUI_PendingCheckItemID, _SUI_PendingCheckSource

    itemID := _SUI_PendingCheckItemID
    source := _SUI_PendingCheckSource
    _SUI_PendingCheckItemID := 0
    _SUI_PendingCheckSource := ""

    if (!itemID)
        return

    SUI_ProcessItemCheckChange(itemID, source)
}

SUI_QueueHelpSelectionClear() {
    static clearHelpSelectionFn := Func("SUI_ClearHelpSelection")
    SetTimer, % clearHelpSelectionFn, -10
}

SUI_ClearHelpSelection() {
    global SettingsLV

    Gui, Settings:Default
    Gui, Settings:ListView, SettingsLV
    LV_Modify(0, "-Select -Focus")
}

SUI_ItemsHandler() {
    global SUI_IsInitializing

    if (SUI_IsInitializing) {
        SUI_DebugLog("list_event_ignored_init")
        return
    }

    evt := A_GuiEvent
    info := A_EventInfo
    flags := ErrorLevel
    targetID := info ? info : SUI_GetSelectedItemID()
    selectedID := SUI_GetSelectedItemID()

    if (selectedID)
        SUI_RefreshLV(selectedID)
    else if (targetID)
        SUI_RefreshLV(targetID)

    if ((evt = "I" && info && (InStr(flags, "C") || InStr(flags, "c")))
    ||  (evt = "C" && targetID)) {
        changedID := info ? info : targetID
        SUI_QueueCheckSync(changedID, "evt=" . evt)
    }

    SUI_DebugLog("list_event"
        , "evt=" . evt
        . " info=" . info
        . " flags=" . flags
        . " selID=" . selectedID
        . " targetID=" . targetID
        . " " . SUI_DebugDescribeItem(targetID))
}

SUI_HelpHandler() {
    global SUI_IsInitializing

    if (SUI_IsInitializing)
        return

    SUI_QueueHelpSelectionClear()
}

SUI_ProcessItemCheckChange(clickedID, source := "manual") {
    global _SUI_ItemMap

    if (!clickedID || !_SUI_ItemMap.HasKey(clickedID))
        return false

    if !SUI_DidCheckStateChange(clickedID) {
        SUI_DebugLog("item_check_nochange"
            , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))
        return false
    }

    SUI_DebugLog("item_check_apply"
        , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))

    SUI_SyncVars()
    SUI_SaveConfig()
    SUI_SnapshotCheckStates()
    SUI_DebugLog("item_check_done"
        , "source=" . source . " " . SUI_DebugDescribeItem(clickedID))
    return true
}

SUI_FlushPendingChange(reason := "manual") {
    global SUI_SettingsGuiHwnd

    if !(SUI_SettingsGuiHwnd && DllCall("IsWindow", "Ptr", SUI_SettingsGuiHwnd))
        return

    SUI_SyncVars()
    SUI_SaveConfig()
    SUI_SnapshotCheckStates()
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
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    Gui, Settings:Default

    for itemID, item in _SUI_ItemMap {
        if (item.Var = "")
            continue

        v := SUI_IsItemChecked(itemID) ? 1 : 0
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
        else if (item.Var = "EnableAlt")
            EnableAlt := v
        else if (item.Var = "EnableOthers")
            EnableOthers := v
        else if (item.Var = "EnableBrowser")
            EnableBrowser := v
        else if (item.Var = "EnablePPT")
            EnablePPT := v
        else if (item.Var = "EnableExcel")
            EnableExcel := v
    }

    SUI_DebugLog("sync_vars")
}

SUI_GetFlagValue(varName) {
    global EnableNavLayer, EnableWinPlace, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel

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
    if (varName = "EnableAlt")
        return EnableAlt
    if (varName = "EnableOthers")
        return EnableOthers
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

    currentState := SUI_IsItemChecked(itemID) ? 1 : 0
    if !_SUI_CheckStateMap.HasKey(itemID)
        return false

    return (_SUI_CheckStateMap[itemID] != currentState)
}

SUI_SnapshotCheckStates() {
    global _SUI_ItemMap, _SUI_CheckStateMap

    _SUI_CheckStateMap := {}
    for itemID, item in _SUI_ItemMap
        _SUI_CheckStateMap[itemID] := SUI_IsItemChecked(itemID) ? 1 : 0
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
