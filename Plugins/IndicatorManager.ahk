; ==============================================================================
; Indicator / settings UI
; ListView (checkboxes + labels) + ListView (hotkey help) + Edit (details)
; ==============================================================================
global _SUI_ItemMap                        := {}
global _SUI_HelpData                       := {}
global _SUI_HelpRowMap                     := {}
global _SUI_Theme                          := {}
global _SUI_ThemeBrushMap                  := {}
global _SUI_CheckStateMap                  := {}
global SUI_SettingsGuiHwnd                 := 0
global SUI_SettingsTabHwnd                 := 0
global SUI_SettingsItemsLabelHwnd          := 0
global SUI_SettingsItemsLVHwnd             := 0
global SUI_SettingsHelpLabelHwnd           := 0
global SUI_SettingsLVHwnd                  := 0
global SUI_CodePreviewLabelHwnd            := 0
global SUI_CodePreviewEditHwnd             := 0
global SettingsItemsLV                     := ""
global SettingsLV                          := ""
global SettingsCodePreviewLabel            := ""
global SettingsCodePreviewEdit             := ""
global SettingsEditorProvider              := ""
global SettingsEditorCustomPath            := ""
global SettingsEditorArgs                  := ""
global SettingsAuthSaveDir                 := ""
global SettingsAuthOutputPath              := ""
global SettingsBrowserUrlExportPath        := ""
global SettingsPPTCaptionGapH              := ""
global SettingsPPTCaptionGapV              := ""
global SettingsBrowserPdfZoomShortcutFirst := ""
global SettingsMouseWheelExplorerRepeat    := ""
global SettingsCursorBaseSpeed             := ""
global SettingsCursorMaxSpeed              := ""
global SettingsCursorAcceleration          := ""
global SettingsCursorTimerInterval         := ""
global SettingsCursorGridCols              := ""
global SettingsCursorGridRows              := ""
global SettingsCursorEdgeInset             := ""
global SettingsIndicatorDebug              := ""
global SettingsMouseGestureDebug           := ""
global SettingsMouseWheelDebug             := ""
global SettingsBrowserPdfZoomDebug         := ""
global SettingsPPTSpacingDebug             := ""
global SettingsPPTCaptionDebug             := ""
global SettingsValidationHint              := ""
global _SUI_CodePreviewCachePath           := ""
global _SUI_CodePreviewCacheLines          := ""
global SUI_IsInitializing                  := false
global SUI_SelectedItemID                  := 0
global _SUI_LastHelpRow                    := 0
global _SUI_HelpRefreshPending             := false
global _SUI_IsRebuildingHelpList           := false
global _SUI_ItemRefreshPending             := false
global _SUI_PendingCheckItemID             := 0
global _SUI_PendingCheckSource             := ""
global SUI_DebugEnabled                    := true
global SUI_DebugLogDir                     := A_ScriptDir . "\.claude"
global SUI_DebugLogPath                    := SUI_DebugLogDir . "\indicator_manager_debug.log"
global SUI_DebugMaxBytes                   := 262144
global SUI_ConfigDir                       := A_ScriptDir . "\config"
global SUI_LegacyConfigPath                := A_ScriptDir . "\Plugins\indicator_settings.ini"
global SUI_ConfigPath                      := SUI_ConfigDir . "\indicator_settings.ini"

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
    global SUI_SettingsGuiHwnd, SUI_SettingsItemsLabelHwnd, SUI_SettingsItemsLVHwnd
    global SUI_SettingsHelpLabelHwnd, SUI_SettingsLVHwnd
    global SUI_CodePreviewLabelHwnd, SUI_CodePreviewEditHwnd
    global SUI_SettingsTabHwnd
    global SUI_SelectedItemID, _SUI_LastHelpRow, SUI_IsInitializing

    if (SUI_SettingsGuiHwnd && !SUI_IsInitializing)
        SUI_SaveAdvancedSettingsFromGui("close")
    SUI_FlushPendingChange("close")
    SUI_DebugLog("settings_close")
    Gui, Settings:Destroy
    SUI_ClearThemeBrushes()
    SUI_SettingsGuiHwnd       := 0
    SUI_SettingsTabHwnd       := 0
    SUI_SettingsItemsLabelHwnd:= 0
    SUI_SettingsItemsLVHwnd   := 0
    SUI_SettingsHelpLabelHwnd := 0
    SUI_SettingsLVHwnd        := 0
    SUI_CodePreviewLabelHwnd  := 0
    SUI_CodePreviewEditHwnd   := 0
    SUI_SelectedItemID        := 0
    _SUI_LastHelpRow          := 0
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
    global EnableChatterGuard

    return "EnableNavLayer="  . EnableNavLayer
        . " EnableWinPlace="  . EnableWinPlace
        . " EnableWinIsland=" . EnableWinIsland
        . " EnableVDesk="     . EnableVDesk
        . " EnableMouseEmu="  . EnableMouseEmu
        . " EnableMouseBtn="  . EnableMouseBtn
        . " EnableGestures="  . EnableGestures
        . " EnableAlt="       . EnableAlt
        . " EnableOthers="    . EnableOthers
        . " EnableBrowser="   . EnableBrowser
        . " EnablePPT="       . EnablePPT
        . " EnableExcel="     . EnableExcel
        . " EnableChatterGuard=" . EnableChatterGuard
}

SUI_DebugDescribeItem(itemID) {
    global _SUI_ItemMap, _SUI_CheckStateMap

    if (!itemID || !_SUI_ItemMap.HasKey(itemID))
        return "itemID=" . itemID . " missing=1"

    item := _SUI_ItemMap[itemID]
    currentState := SUI_IsItemChecked(itemID) ? 1 : 0
    prevState := _SUI_CheckStateMap.HasKey(itemID) ? _SUI_CheckStateMap[itemID] : "?"

    return "itemID=" . itemID
        . " var="    . item.Var
        . " row="    . item.Row
        . " prev="   . prevState
        . " cur="    . currentState
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

SUI_CreateDefaultTheme() {
    ; Keep the entire settings window on a single MouseGestureL-like palette.
    ; Base it on the white/black ExNavi colors rather than a dark editor theme.
    theme := {Name:         "mousegesture-light"
        , ForegroundHex:    "000000"
        , MutedHex:         "7F7F7F"
        , WindowHex:        "F3F3F3"
        , PanelHex:         "FFFFFF"
        , ListHex:          "FFFFFF"
        , EditorHex:        "FAFAFA"
        , EditorForegroundHex: "1E1E1E"
        , TitleHex:         "F3F3F3"
        , BorderHex:        "C8C8C8"
        , AccentHex:        "7F7F7F"}
    SUI_FinalizeTheme(theme)
    return theme
}

SUI_FinalizeTheme(theme) {
    theme.ForegroundRGB  := theme.ForegroundHex
    theme.MutedRGB       := theme.MutedHex
    theme.WindowRGB      := theme.WindowHex
    theme.PanelRGB       := theme.PanelHex
    theme.ListRGB        := theme.ListHex
    theme.EditorRGB      := theme.EditorHex
    theme.EditorForegroundRGB := theme.EditorForegroundHex
    theme.TitleRGB       := theme.TitleHex
    theme.BorderRGB      := theme.BorderHex
    theme.AccentRGB      := theme.AccentHex

    theme.ForegroundColor  := SUI_HexToColorRef(theme.ForegroundHex)
    theme.MutedColor       := SUI_HexToColorRef(theme.MutedHex)
    theme.WindowColor      := SUI_HexToColorRef(theme.WindowHex)
    theme.PanelColor       := SUI_HexToColorRef(theme.PanelHex)
    theme.ListColor        := SUI_HexToColorRef(theme.ListHex)
    theme.EditorColor      := SUI_HexToColorRef(theme.EditorHex)
    theme.EditorForegroundColor := SUI_HexToColorRef(theme.EditorForegroundHex)
    theme.TitleColor       := SUI_HexToColorRef(theme.TitleHex)
    theme.BorderColor      := SUI_HexToColorRef(theme.BorderHex)
    theme.AccentColor      := SUI_HexToColorRef(theme.AccentHex)
}

SUI_HexToColorRef(hex) {
    hex := StrReplace(hex, "#")
    if (StrLen(hex) != 6)
        return 0

    r := "0x" . SubStr(hex, 1, 2)
    g := "0x" . SubStr(hex, 3, 2)
    b := "0x" . SubStr(hex, 5, 2)
    return r + (g << 8) + (b << 16)
}

SUI_LoadTheme() {
    global _SUI_Theme

    _SUI_Theme := SUI_CreateDefaultTheme()
    SUI_DebugLog("theme_load", "name=" . _SUI_Theme.Name . " panel=#" . _SUI_Theme.PanelHex . " editor=#" . _SUI_Theme.EditorHex)
}

SUI_GetThemeBrush(colorRef) {
    global _SUI_ThemeBrushMap

    key := colorRef . ""
    if !_SUI_ThemeBrushMap.HasKey(key)
        _SUI_ThemeBrushMap[key] := DllCall("CreateSolidBrush", "UInt", colorRef, "Ptr")
    return _SUI_ThemeBrushMap[key]
}

SUI_ClearThemeBrushes() {
    global _SUI_ThemeBrushMap

    for _, brush in _SUI_ThemeBrushMap {
        if (brush)
            DllCall("DeleteObject", "Ptr", brush)
    }
    _SUI_ThemeBrushMap := {}
}

SUI_ApplyListViewTheme(hwnd, bgColor, textColor) {
    static LVM_SETBKCOLOR     := 0x1001
    static LVM_SETTEXTCOLOR   := 0x1024
    static LVM_SETTEXTBKCOLOR := 0x1026

    ; Disable the Windows theme for these ListViews so our monochrome palette
    ; is actually used instead of themed drawing colors.
    DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "WStr", "", "Ptr", 0)
    SendMessage, %LVM_SETBKCOLOR%,      0, %bgColor%,   , ahk_id %hwnd%
    SendMessage, %LVM_SETTEXTBKCOLOR%,  0, %bgColor%,   , ahk_id %hwnd%
    SendMessage, %LVM_SETTEXTCOLOR%,    0, %textColor%, , ahk_id %hwnd%
}

SUI_ApplyThemeToControls() {
    global _SUI_Theme, SUI_SettingsGuiHwnd, SUI_SettingsItemsLVHwnd
    global SUI_SettingsLVHwnd

    if !IsObject(_SUI_Theme)
        return

    Gui, Settings:Default
    Gui, Settings:Color, % _SUI_Theme.WindowRGB, % _SUI_Theme.WindowRGB

    if (SUI_SettingsItemsLVHwnd)
        SUI_ApplyListViewTheme(SUI_SettingsItemsLVHwnd, _SUI_Theme.ListColor, _SUI_Theme.ForegroundColor)

    if (SUI_SettingsLVHwnd)
        SUI_ApplyListViewTheme(SUI_SettingsLVHwnd, _SUI_Theme.ListColor, _SUI_Theme.ForegroundColor)

    if (SUI_SettingsGuiHwnd)
        DllCall("RedrawWindow", "Ptr", SUI_SettingsGuiHwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0401)
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

SUI_NormalizeTextEditorProvider(value, defaultValue := "Notepads") {
    value := Trim(value)
    if (value = "Notepads" || value = "Notepad" || value = "VSCode" || value = "Custom")
        return value
    return defaultValue
}

SUI_NormalizeZoomMode(value, defaultValue := "CtrlNumpad") {
    value := Trim(value)
    if (value = "CtrlWheel" || value = "CtrlNumpad")
        return value
    return defaultValue
}

SUI_NormalizeInt(value, defaultValue, minValue := "", maxValue := "") {
    value := Trim(value)
    if !RegExMatch(value, "^-?\d+$")
        value := defaultValue + 0
    else
        value := value + 0

    if (minValue != "" && value < minValue)
        value := minValue
    if (maxValue != "" && value > maxValue)
        value := maxValue
    return value + 0
}

SUI_NormalizeFloat(value, defaultValue, minValue := "", maxValue := "", decimals := 2) {
    value := Trim(value)
    if !RegExMatch(value, "^-?\d+(\.\d+)?$")
        value := defaultValue + 0
    else
        value := value + 0

    if (minValue != "" && value < minValue)
        value := minValue
    if (maxValue != "" && value > maxValue)
        value := maxValue
    return Round(value, decimals)
}

SUI_NormalizeText(value, defaultValue := "") {
    value := Trim(value)
    return (value = "") ? defaultValue : value
}

SUI_FormatNumber(value, decimals := 2) {
    if (value = "")
        return ""

    formatPattern := "{:." . decimals . "f}"
    text := Format(formatPattern, value + 0)
    text := RTrim(text, "0")
    text := RTrim(text, ".")
    return (text = "") ? "0" : text
}

SUI_IsNotepadsAvailable() {
    if IsFunc("IsNotepadsAvailable")
        return IsNotepadsAvailable()

    EnvGet, localAppData, LOCALAPPDATA
    return FileExist(localAppData . "\Microsoft\WindowsApps\Notepads.exe") ? 1 : 0
}

SUI_EnsureConfigPath() {
    global SUI_ConfigDir, SUI_ConfigPath, SUI_LegacyConfigPath

    if !InStr(FileExist(SUI_ConfigDir), "D")
        FileCreateDir, %SUI_ConfigDir%

    if FileExist(SUI_ConfigPath)
        return

    if FileExist(SUI_LegacyConfigPath) {
        FileMove, %SUI_LegacyConfigPath%, %SUI_ConfigPath%, 0
        if (ErrorLevel) {
            FileCopy, %SUI_LegacyConfigPath%, %SUI_ConfigPath%, 0
            if (ErrorLevel)
                return
        }

        SUI_DebugLog("config_migrated", "from=" . SUI_LegacyConfigPath . " to=" . SUI_ConfigPath)
        return
    }
}

SUI_LoadConfig() {
    global SUI_ConfigPath
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    global EnableChatterGuard
    global TextEditorProvider, TextEditorCustomPath, TextEditorArgsTemplate
    global SaveDir, OutputFileName, Browser_URLExportPath
    global Browser_PDFZoomTryShortcutFirst
    global MouseWheel_ExplorerScrollBarRepeat
    global MouseWheel_DefaultZoomMode, MouseWheel_CtrlWheelApps
    global CursorConfig, CursorGridConfig
    global SUI_DebugEnabled, MG_DebugEnabled, MouseWheel_DebugEnabled
    global Browser_PDFZoomDebugEnabled, PPT_SpacingLogEnabled, PPT_CaptionLogEnabled
    global CG_SameEventThreshold, CG_CrossEventThreshold

    SUI_EnsureConfigPath()

    IniRead, navLayerRaw,       %SUI_ConfigPath%, Indicators, EnableNavLayer,      %EnableNavLayer%
    IniRead, winPlaceRaw,       %SUI_ConfigPath%, Indicators, EnableWinPlace,      %EnableWinPlace%
    IniRead, winIslandRaw,      %SUI_ConfigPath%, Indicators, EnableWinIsland,     %EnableWinIsland%
    IniRead, vdeskRaw,          %SUI_ConfigPath%, Indicators, EnableVDesk,         %EnableVDesk%
    IniRead, mouseEmuRaw,       %SUI_ConfigPath%, Indicators, EnableMouseEmu,      %EnableMouseEmu%
    IniRead, mouseBtnRaw,       %SUI_ConfigPath%, Indicators, EnableMouseBtn,      %EnableMouseBtn%
    IniRead, gesturesRaw,       %SUI_ConfigPath%, Indicators, EnableGestures,      %EnableGestures%
    IniRead, altRaw,            %SUI_ConfigPath%, Indicators, EnableAlt,           %EnableAlt%
    IniRead, othersRaw,         %SUI_ConfigPath%, Indicators, EnableOthers,        %EnableOthers%
    IniRead, browserRaw,        %SUI_ConfigPath%, Indicators, EnableBrowser,       %EnableBrowser%
    IniRead, pptRaw,            %SUI_ConfigPath%, Indicators, EnablePPT,           %EnablePPT%
    IniRead, excelRaw,          %SUI_ConfigPath%, Indicators, EnableExcel,         %EnableExcel%
    IniRead, chatterGuardRaw,   %SUI_ConfigPath%, Indicators, EnableChatterGuard,  %EnableChatterGuard%

    EnableNavLayer    := SUI_NormalizeBool(navLayerRaw, EnableNavLayer)
    EnableWinPlace    := SUI_NormalizeBool(winPlaceRaw, EnableWinPlace)
    EnableWinIsland   := SUI_NormalizeBool(winIslandRaw, EnableWinIsland)
    EnableVDesk       := SUI_NormalizeBool(vdeskRaw, EnableVDesk)
    EnableMouseEmu    := SUI_NormalizeBool(mouseEmuRaw, EnableMouseEmu)
    EnableMouseBtn    := SUI_NormalizeBool(mouseBtnRaw, EnableMouseBtn)
    EnableGestures    := SUI_NormalizeBool(gesturesRaw, EnableGestures)
    EnableAlt         := SUI_NormalizeBool(altRaw, EnableAlt)
    EnableOthers      := SUI_NormalizeBool(othersRaw, EnableOthers)
    EnableBrowser     := SUI_NormalizeBool(browserRaw, EnableBrowser)
    EnablePPT         := SUI_NormalizeBool(pptRaw, EnablePPT)
    EnableExcel       := SUI_NormalizeBool(excelRaw, EnableExcel)
    EnableChatterGuard := SUI_NormalizeBool(chatterGuardRaw, EnableChatterGuard)

    IniRead, editorProviderRaw,    %SUI_ConfigPath%, TextEditor, Provider, %TextEditorProvider%
    IniRead, editorCustomPathRaw,  %SUI_ConfigPath%, TextEditor, CustomPath, __EMPTY__
    IniRead, editorArgsRaw,        %SUI_ConfigPath%, TextEditor, CustomArgs, __EMPTY__
    if (Trim(editorProviderRaw) = "") {
        IniRead, editorTypeRaw, %SUI_ConfigPath%, SettingsUI, EditorType, % SettingsUI.EditorType
        SettingsUI.EditorType := SUI_NormalizeEditorType(editorTypeRaw, SettingsUI.EditorType)
        TextEditorProvider := (SettingsUI.EditorType = 1) ? "Notepads" : "Notepad"
    } else {
        TextEditorProvider := SUI_NormalizeTextEditorProvider(editorProviderRaw, TextEditorProvider)
        SettingsUI.EditorType := (TextEditorProvider = "Notepads") ? 1 : 2
    }
    if (editorCustomPathRaw = "__EMPTY__" || editorCustomPathRaw = "ERROR")
        editorCustomPathRaw := ""
    if (editorArgsRaw = "__EMPTY__" || editorArgsRaw = "ERROR")
        editorArgsRaw := ""
    TextEditorCustomPath := Trim(editorCustomPathRaw)
    TextEditorArgsTemplate := editorArgsRaw

    IniRead, cookieSaveDirRaw,     %SUI_ConfigPath%, Paths, CookieSaveDir, %SaveDir%
    IniRead, authOutputPathRaw,    %SUI_ConfigPath%, Paths, AuthOutputPath, %OutputFileName%
    IniRead, browserExportPathRaw, %SUI_ConfigPath%, Paths, BrowserUrlExportPath, %Browser_URLExportPath%
    SaveDir := Trim(cookieSaveDirRaw)
    OutputFileName := Trim(authOutputPathRaw)
    Browser_URLExportPath := Trim(browserExportPathRaw)

    IniRead, browserTryShortcutRaw, %SUI_ConfigPath%, Browser, PDFZoomTryShortcutFirst, %Browser_PDFZoomTryShortcutFirst%
    Browser_PDFZoomTryShortcutFirst := SUI_NormalizeBool(browserTryShortcutRaw, Browser_PDFZoomTryShortcutFirst)

    IniRead, explorerRepeatRaw,       %SUI_ConfigPath%, MouseWheel, ExplorerScrollBarRepeat, %MouseWheel_ExplorerScrollBarRepeat%
    IniRead, defaultZoomModeRaw,      %SUI_ConfigPath%, MouseWheel, DefaultZoomMode, %MouseWheel_DefaultZoomMode%
    IniRead, ctrlWheelAppsRaw,        %SUI_ConfigPath%, MouseWheel, CtrlWheelApps, %MouseWheel_CtrlWheelApps%
    MouseWheel_ExplorerScrollBarRepeat := SUI_NormalizeInt(explorerRepeatRaw, MouseWheel_ExplorerScrollBarRepeat, 1, 20)
    MouseWheel_DefaultZoomMode := SUI_NormalizeZoomMode(defaultZoomModeRaw, MouseWheel_DefaultZoomMode)
    MouseWheel_CtrlWheelApps := Trim(ctrlWheelAppsRaw)
    if IsFunc("MouseWheel_RebuildZoomRules")
        MouseWheel_RebuildZoomRules()

    IniRead, cursorBaseSpeedRaw,    %SUI_ConfigPath%, Cursor, BaseSpeed, % CursorConfig.BaseSpeed
    IniRead, cursorMaxSpeedRaw,     %SUI_ConfigPath%, Cursor, MaxSpeed, % CursorConfig.MaxSpeed
    IniRead, cursorAccelRaw,        %SUI_ConfigPath%, Cursor, Acceleration, % CursorConfig.Acceleration
    IniRead, cursorTimerRaw,        %SUI_ConfigPath%, Cursor, TimerInterval, % CursorConfig.TimerInterval
    IniRead, cursorGridColsRaw,     %SUI_ConfigPath%, Cursor, GridCols, % CursorGridConfig.DefaultCols
    IniRead, cursorGridRowsRaw,     %SUI_ConfigPath%, Cursor, GridRows, % CursorGridConfig.DefaultRows
    IniRead, cursorEdgeInsetRaw,    %SUI_ConfigPath%, Cursor, EdgeInset, % CursorGridConfig.EdgeInset
    CursorConfig.BaseSpeed := SUI_NormalizeFloat(cursorBaseSpeedRaw, CursorConfig.BaseSpeed, 0.25, 50, 2)
    CursorConfig.MaxSpeed := SUI_NormalizeFloat(cursorMaxSpeedRaw, CursorConfig.MaxSpeed, CursorConfig.BaseSpeed, 200, 2)
    CursorConfig.Acceleration := SUI_NormalizeFloat(cursorAccelRaw, CursorConfig.Acceleration, 1.01, 5, 2)
    CursorConfig.TimerInterval := SUI_NormalizeInt(cursorTimerRaw, CursorConfig.TimerInterval, 1, 100)
    CursorGridConfig.DefaultCols := SUI_NormalizeInt(cursorGridColsRaw, CursorGridConfig.DefaultCols, 1, 12)
    CursorGridConfig.DefaultRows := SUI_NormalizeInt(cursorGridRowsRaw, CursorGridConfig.DefaultRows, 1, 12)
    CursorGridConfig.EdgeInset := SUI_NormalizeInt(cursorEdgeInsetRaw, CursorGridConfig.EdgeInset, 0, 100)

    IniRead, suiDebugRaw,           %SUI_ConfigPath%, Debug, IndicatorManager, %SUI_DebugEnabled%
    IniRead, mgDebugRaw,            %SUI_ConfigPath%, Debug, MouseGesture, %MG_DebugEnabled%
    IniRead, mouseWheelDebugRaw,    %SUI_ConfigPath%, Debug, MouseWheel, %MouseWheel_DebugEnabled%
    IniRead, browserDebugRaw,       %SUI_ConfigPath%, Debug, BrowserPDFZoom, %Browser_PDFZoomDebugEnabled%
    IniRead, pptSpacingDebugRaw,    %SUI_ConfigPath%, Debug, PowerPointSpacing, %PPT_SpacingLogEnabled%
    IniRead, pptCaptionDebugRaw,    %SUI_ConfigPath%, Debug, PowerPointCaption, %PPT_CaptionLogEnabled%
    SUI_DebugEnabled := SUI_NormalizeBool(suiDebugRaw, SUI_DebugEnabled)
    MG_DebugEnabled := SUI_NormalizeBool(mgDebugRaw, MG_DebugEnabled)
    MouseWheel_DebugEnabled := SUI_NormalizeBool(mouseWheelDebugRaw, MouseWheel_DebugEnabled)
    Browser_PDFZoomDebugEnabled := SUI_NormalizeBool(browserDebugRaw, Browser_PDFZoomDebugEnabled)
    PPT_SpacingLogEnabled := SUI_NormalizeBool(pptSpacingDebugRaw, PPT_SpacingLogEnabled)
    PPT_CaptionLogEnabled := SUI_NormalizeBool(pptCaptionDebugRaw, PPT_CaptionLogEnabled)

    ; [ChatterGuard] 閾値読込み
    IniRead, sameThreshRaw, %SUI_ConfigPath%, ChatterGuard, SameEventThreshold, %CG_SameEventThreshold%
    IniRead, crossThreshRaw, %SUI_ConfigPath%, ChatterGuard, CrossEventThreshold, %CG_CrossEventThreshold%
    CG_SameEventThreshold := SUI_NormalizeInt(sameThreshRaw, 50, 10, 200)
    CG_CrossEventThreshold := SUI_NormalizeInt(crossThreshRaw, 30, 5, 100)

    SUI_DebugLog("config_load", "path=" . SUI_ConfigPath)
}

SUI_SaveConfig() {
    global SUI_ConfigPath
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    global EnableChatterGuard
    global TextEditorProvider, TextEditorCustomPath, TextEditorArgsTemplate
    global SaveDir, OutputFileName, Browser_URLExportPath
    global Browser_PDFZoomTryShortcutFirst
    global MouseWheel_ExplorerScrollBarRepeat
    global MouseWheel_DefaultZoomMode, MouseWheel_CtrlWheelApps
    global CursorConfig, CursorGridConfig
    global SUI_DebugEnabled, MG_DebugEnabled, MouseWheel_DebugEnabled
    global Browser_PDFZoomDebugEnabled, PPT_SpacingLogEnabled, PPT_CaptionLogEnabled
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical

    SUI_EnsureConfigPath()

    IniWrite, % EnableNavLayer      ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableNavLayer
    IniWrite, % EnableWinPlace      ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableWinPlace
    IniWrite, % EnableWinIsland     ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableWinIsland
    IniWrite, % EnableVDesk         ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableVDesk
    IniWrite, % EnableMouseEmu      ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableMouseEmu
    IniWrite, % EnableMouseBtn      ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableMouseBtn
    IniWrite, % EnableGestures      ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableGestures
    IniWrite, % EnableAlt           ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableAlt
    IniWrite, % EnableOthers        ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableOthers
    IniWrite, % EnableBrowser       ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableBrowser
    IniWrite, % EnablePPT           ? 1 : 0, %SUI_ConfigPath%, Indicators, EnablePPT
    IniWrite, % EnableChatterGuard  ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableChatterGuard
    IniWrite, % EnableExcel         ? 1 : 0, %SUI_ConfigPath%, Indicators, EnableExcel
    SettingsUI.EditorType := (TextEditorProvider = "Notepads") ? 1 : 2
    IniWrite, % SettingsUI.EditorType, %SUI_ConfigPath%, SettingsUI, EditorType

    IniWrite, %TextEditorProvider%, %SUI_ConfigPath%, TextEditor, Provider
    IniWrite, %TextEditorCustomPath%, %SUI_ConfigPath%, TextEditor, CustomPath
    IniWrite, %TextEditorArgsTemplate%, %SUI_ConfigPath%, TextEditor, CustomArgs

    IniWrite, %SaveDir%, %SUI_ConfigPath%, Paths, CookieSaveDir
    IniWrite, %OutputFileName%, %SUI_ConfigPath%, Paths, AuthOutputPath
    IniWrite, %Browser_URLExportPath%, %SUI_ConfigPath%, Paths, BrowserUrlExportPath

    IniWrite, % Browser_PDFZoomTryShortcutFirst ? 1 : 0, %SUI_ConfigPath%, Browser, PDFZoomTryShortcutFirst

    IniWrite, %MouseWheel_ExplorerScrollBarRepeat%, %SUI_ConfigPath%, MouseWheel, ExplorerScrollBarRepeat
    IniWrite, %MouseWheel_DefaultZoomMode%, %SUI_ConfigPath%, MouseWheel, DefaultZoomMode
    IniWrite, %MouseWheel_CtrlWheelApps%, %SUI_ConfigPath%, MouseWheel, CtrlWheelApps

    IniWrite, % SUI_FormatNumber(CursorConfig.BaseSpeed, 2), %SUI_ConfigPath%, Cursor, BaseSpeed
    IniWrite, % SUI_FormatNumber(CursorConfig.MaxSpeed, 2), %SUI_ConfigPath%, Cursor, MaxSpeed
    IniWrite, % SUI_FormatNumber(CursorConfig.Acceleration, 2), %SUI_ConfigPath%, Cursor, Acceleration
    IniWrite, % CursorConfig.TimerInterval, %SUI_ConfigPath%, Cursor, TimerInterval
    IniWrite, % CursorGridConfig.DefaultCols, %SUI_ConfigPath%, Cursor, GridCols
    IniWrite, % CursorGridConfig.DefaultRows, %SUI_ConfigPath%, Cursor, GridRows
    IniWrite, % CursorGridConfig.EdgeInset, %SUI_ConfigPath%, Cursor, EdgeInset

    IniWrite, % SUI_FormatNumber(PPT_CaptionVisualGapHorizontal, 2), %SUI_ConfigPath%, PowerPoint, CaptionHorizontalGap
    IniWrite, % SUI_FormatNumber(PPT_CaptionVisualGapVertical, 2), %SUI_ConfigPath%, PowerPoint, CaptionVerticalGap

    IniWrite, % SUI_DebugEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, IndicatorManager
    IniWrite, % MG_DebugEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, MouseGesture
    IniWrite, % MouseWheel_DebugEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, MouseWheel
    IniWrite, % Browser_PDFZoomDebugEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, BrowserPDFZoom
    IniWrite, % PPT_SpacingLogEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, PowerPointSpacing
    IniWrite, % PPT_CaptionLogEnabled ? 1 : 0, %SUI_ConfigPath%, Debug, PowerPointCaption

    SUI_DebugLog("config_save", "path=" . SUI_ConfigPath)
}

SUI_RegisterMessageHandlers() {
    static isRegistered := false

    if (isRegistered)
        return

    OnMessage(0x0010, "SUI_HandleWmClose")
    OnMessage(0x0201, "SUI_HandleLButtonDown")
    OnMessage(0x0210, "SUI_HandleParentNotify")
    OnMessage(0x004E, "SUI_HandleNotify")
    OnMessage(0x0133, "SUI_HandleCtlColorEdit")
    OnMessage(0x0135, "SUI_HandleCtlColorBtn")
    OnMessage(0x0136, "SUI_HandleCtlColorDlg")
    OnMessage(0x0138, "SUI_HandleCtlColorStatic")
    isRegistered := true
}

SUI_HandleWmClose(wParam, lParam, msg, hwnd) {
    global SUI_SettingsGuiHwnd

    if (SUI_SettingsGuiHwnd && hwnd = SUI_SettingsGuiHwnd) {
        Settings_Close()
        return 0
    }
}

SUI_HandleNotify(wParam, lParam, msg, hwnd) {
    global SUI_SettingsGuiHwnd, SUI_SettingsLVHwnd, SUI_SettingsItemsLVHwnd
    global _SUI_IsRebuildingHelpList
    global _SUI_ItemMap

    if (!SUI_SettingsGuiHwnd || hwnd != SUI_SettingsGuiHwnd)
        return

    hwndFrom := NumGet(lParam + 0, 0, "Ptr")
    code := NumGet(lParam + 0, A_PtrSize * 2, "Int")

    ; LVN_ITEMCHANGING (-100): disabled 行のチェックボックス変更をブロック
    if (code = -100 && hwndFrom = SUI_SettingsItemsLVHwnd) {
        static NMHDR_SIZE := (A_PtrSize = 8 ? 24 : 12)
        row := NumGet(lParam + 0, NMHDR_SIZE + 0, "Int") + 1
        uNewState := NumGet(lParam + 0, NMHDR_SIZE + 8, "UInt")
        uOldState := NumGet(lParam + 0, NMHDR_SIZE + 12, "UInt")
        uChanged := NumGet(lParam + 0, NMHDR_SIZE + 16, "UInt")
        if (uChanged & 0x0008) && ((uOldState ^ uNewState) & 0xF000) {
            if (_SUI_ItemMap.HasKey(row) && _SUI_ItemMap[row].Disabled)
                return 1
        }
    }

    if (hwndFrom != SUI_SettingsLVHwnd)
        return
    if (_SUI_IsRebuildingHelpList)
        return

    if (code = -101 || code = -2 || code = -3 || code = -155)
        SUI_QueueHelpRefresh("notify code=" . code)
}

SUI_GetWindowClassName(hwnd) {
    VarSetCapacity(className, 256, 0)
    DllCall("GetClassName", "Ptr", hwnd, "Str", className, "Int", 256)
    return className
}

SUI_IsGroupBoxHwnd(hwnd) {
    if !hwnd
        return false
    if (SUI_GetWindowClassName(hwnd) != "Button")
        return false
    style := DllCall(A_PtrSize = 8 ? "GetWindowLongPtr" : "GetWindowLong", "Ptr", hwnd, "Int", -16, "Ptr")
    return ((style & 0xF) = 0x7)
}

SUI_ShouldClearEditFocus(clickedHwnd) {
    global SUI_SettingsGuiHwnd

    if !clickedHwnd
        return true
    if (clickedHwnd = SUI_SettingsGuiHwnd)
        return true

    className := SUI_GetWindowClassName(clickedHwnd)
    if (className = "Static" || className = "SysTabControl32")
        return true
    if (className = "Button" && SUI_IsGroupBoxHwnd(clickedHwnd))
        return true
    return false
}

SUI_TryClearEditFocus(clickedHwnd := 0) {
    global SUI_SettingsGuiHwnd, SUI_SettingsTabHwnd

    if (!SUI_SettingsGuiHwnd || !SUI_SettingsTabHwnd)
        return

    focusHwnd := DllCall("GetFocus", "Ptr")
    if !focusHwnd
        return
    if (SUI_GetWindowClassName(focusHwnd) != "Edit")
        return

    if !clickedHwnd {
        MouseGetPos,,, mouseWin, clickedHwnd, 2
        if (mouseWin != SUI_SettingsGuiHwnd)
            return
    }

    if !SUI_ShouldClearEditFocus(clickedHwnd)
        return

    GuiControlGet, focusedControlName, Name, %focusHwnd%
    if (focusedControlName != "")
        SUI_ClampNumericControl(focusedControlName)

    DllCall("SetFocus", "Ptr", SUI_SettingsTabHwnd)
}

SUI_HandleLButtonDown(wParam, lParam, msg, hwnd) {
    global SUI_SettingsGuiHwnd

    if (!SUI_SettingsGuiHwnd)
        return
    if (hwnd != SUI_SettingsGuiHwnd && !DllCall("IsChild", "Ptr", SUI_SettingsGuiHwnd, "Ptr", hwnd))
        return
    SUI_TryClearEditFocus(hwnd)
}

SUI_HandleParentNotify(wParam, lParam, msg, hwnd) {
    global SUI_SettingsGuiHwnd

    if (!SUI_SettingsGuiHwnd || hwnd != SUI_SettingsGuiHwnd)
        return
    if ((wParam & 0xFFFF) != 0x0201)
        return
    SUI_TryClearEditFocus()
}

SUI_IsSettingsGuiCtlColor(hwnd) {
    global SUI_SettingsGuiHwnd
    return (SUI_SettingsGuiHwnd && hwnd = SUI_SettingsGuiHwnd)
}

SUI_IsTitleLabelHwnd(ctrlHwnd) {
    global SUI_SettingsItemsLabelHwnd, SUI_SettingsHelpLabelHwnd, SUI_CodePreviewLabelHwnd
    return (ctrlHwnd = SUI_SettingsItemsLabelHwnd
        || ctrlHwnd = SUI_SettingsHelpLabelHwnd
        || ctrlHwnd = SUI_CodePreviewLabelHwnd)
}

SUI_HandleCtlColorEdit(wParam, lParam, msg, hwnd) {
    global _SUI_Theme

    if (!IsObject(_SUI_Theme) || !SUI_IsSettingsGuiCtlColor(hwnd))
        return

    DllCall("SetTextColor", "Ptr", wParam, "UInt", _SUI_Theme.EditorForegroundColor)
    DllCall("SetBkColor", "Ptr", wParam, "UInt", _SUI_Theme.EditorColor)
    return SUI_GetThemeBrush(_SUI_Theme.EditorColor)
}

SUI_HandleCtlColorStatic(wParam, lParam, msg, hwnd) {
    global _SUI_Theme

    if (!IsObject(_SUI_Theme) || !SUI_IsSettingsGuiCtlColor(hwnd))
        return

    if (SUI_IsTitleLabelHwnd(lParam)) {
        DllCall("SetTextColor", "Ptr", wParam, "UInt", _SUI_Theme.ForegroundColor)
        DllCall("SetBkColor", "Ptr", wParam, "UInt", _SUI_Theme.TitleColor)
        DllCall("SetBkMode", "Ptr", wParam, "Int", 2)
        return SUI_GetThemeBrush(_SUI_Theme.TitleColor)
    }

    DllCall("SetTextColor", "Ptr", wParam, "UInt", _SUI_Theme.ForegroundColor)
    DllCall("SetBkColor", "Ptr", wParam, "UInt", _SUI_Theme.WindowColor)
    DllCall("SetBkMode", "Ptr", wParam, "Int", 1)
    return SUI_GetThemeBrush(_SUI_Theme.WindowColor)
}

SUI_HandleCtlColorBtn(wParam, lParam, msg, hwnd) {
    global _SUI_Theme

    if (!IsObject(_SUI_Theme) || !SUI_IsSettingsGuiCtlColor(hwnd))
        return

    DllCall("SetTextColor", "Ptr", wParam, "UInt", _SUI_Theme.ForegroundColor)
    DllCall("SetBkColor", "Ptr", wParam, "UInt", _SUI_Theme.WindowColor)
    DllCall("SetBkMode", "Ptr", wParam, "Int", 1)
    return SUI_GetThemeBrush(_SUI_Theme.WindowColor)
}

SUI_HandleCtlColorDlg(wParam, lParam, msg, hwnd) {
    global _SUI_Theme

    if (!IsObject(_SUI_Theme) || !SUI_IsSettingsGuiCtlColor(hwnd))
        return

    return SUI_GetThemeBrush(_SUI_Theme.WindowColor)
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
        Menu, Tray, Add, PPT 間隔ログを開く, PPT_SpacingOpenLog
        Menu, Tray, Add, PPT キャプションログを開く, PPT_CaptionOpenLog
        Menu, Tray, Add
        Menu, Tray, Add, 右クリック状態を記録, MG_DebugSnapshotMenu
        Menu, Tray, Add, 右クリックログを開く, MG_DebugOpenLog

        IfExist, %StartupShortcutPath%
            Menu, Tray, Check, スタートアップで実行する

        SUI_LoadTheme()
        SUI_InitHelpData()
    }

    Show() {
        Global SUI_SettingsGuiHwnd, SUI_SettingsItemsLabelHwnd, SUI_SettingsItemsLVHwnd
        Global SUI_SettingsHelpLabelHwnd, SUI_SettingsLVHwnd
        Global SUI_CodePreviewLabelHwnd, SUI_CodePreviewEditHwnd
        Global _SUI_Theme
        Global SettingsItemsLV, SettingsLV, SettingsCodePreviewLabel, SettingsCodePreviewEdit
        Global SettingsEditorProvider, SettingsEditorCustomPath, SettingsEditorArgs
        Global SettingsAuthSaveDir, SettingsAuthOutputPath, SettingsBrowserUrlExportPath
        Global SettingsPPTCaptionGapH, SettingsPPTCaptionGapV
        Global SettingsBrowserPdfZoomShortcutFirst, SettingsMouseWheelExplorerRepeat
        Global SettingsCursorBaseSpeed, SettingsCursorMaxSpeed, SettingsCursorAcceleration, SettingsCursorTimerInterval
        Global SettingsCursorGridCols, SettingsCursorGridRows, SettingsCursorEdgeInset
        Global SettingsIndicatorDebug, SettingsMouseGestureDebug, SettingsMouseWheelDebug
        Global SettingsBrowserPdfZoomDebug, SettingsPPTSpacingDebug, SettingsPPTCaptionDebug, SettingsValidationHint
        Global SettingsSameEvent, SettingsCrossEvent
        Global CG_SameEventThreshold, CG_CrossEventThreshold
        Global SUI_IsInitializing, SUI_SelectedItemID, _SUI_LastHelpRow
        SUI_IsInitializing := true
        SUI_SelectedItemID := 0
        _SUI_LastHelpRow := 0
        SUI_LoadTheme()
        Gui, Settings:Destroy
        Gui, Settings:New, +AlwaysOnTop +HwndhSettingsGui, 機能設定
        SUI_SettingsGuiHwnd := hSettingsGui
        Gui, Settings:Color, % _SUI_Theme.WindowRGB, % _SUI_Theme.WindowRGB
        Gui, Settings:Font, % "s9 c" . _SUI_Theme.ForegroundHex, Segoe UI

        ; =========================================
        ; --- タブコントロールの追加 ---
        ; =========================================
        Gui, Settings:Add, Tab3, x10 y10 w750 h520 HwndhSettingsTab, 基本設定|詳細設定
        SUI_SettingsTabHwnd := hSettingsTab

        ; -----------------------------------------
        ; ▼ 1つ目のタブ (基本設定) の内容
        ; -----------------------------------------
        Gui, Settings:Tab, 1
        Gui, Settings:Font, % "s9 c" . _SUI_Theme.ForegroundHex, Segoe UI
        Gui, Settings:Add, Text, x20 y44 w210 h20 HwndhSettingsItemsLabel +0x200, 機能
        SUI_SettingsItemsLabelHwnd := hSettingsItemsLabel
        Gui, Settings:Add, Text, x245 y44 w495 h20 HwndhSettingsHelpLabel +0x200, ホットキー / 説明
        SUI_SettingsHelpLabelHwnd := hSettingsHelpLabel
        Gui, Settings:Add, ListView, x20 y66 w210 h430 vSettingsItemsLV gSUI_ItemsHandler HwndhSettingsItemsLV Checked AltSubmit -Multi -Hdr +LV0x20 -0x100000, |機能
        SUI_SettingsItemsLVHwnd := hSettingsItemsLV
        Gui, Settings:Add, ListView, x245 y66 w495 h245 vSettingsLV gSUI_HelpHandler HwndhSettingsLV Grid AltSubmit -Hdr -Multi -TabStop +0x8 -0x100000, ホットキー|説明
        SUI_SettingsLVHwnd := hSettingsLV
        Gui, Settings:Font, % "s9 c" . _SUI_Theme.ForegroundHex, Segoe UI
        Gui, Settings:Add, Text, x245 y323 w495 h20 vSettingsCodePreviewLabel HwndhSettingsCodePreviewLabel +0x200, 詳細
        SUI_CodePreviewLabelHwnd := hSettingsCodePreviewLabel
        Gui, Settings:Font, % "s9 c" . _SUI_Theme.EditorForegroundHex, Consolas
        Gui, Settings:Add, Edit, x245 y345 w495 h151 vSettingsCodePreviewEdit HwndhSettingsCodePreviewEdit ReadOnly -Wrap -TabStop
        SUI_CodePreviewEditHwnd := hSettingsCodePreviewEdit
        Gui, Settings:Font, % "s9 c" . _SUI_Theme.ForegroundHex, Segoe UI

        ; -----------------------------------------
        ; ▼ 2つ目のタブ (詳細設定) の内容
        ; -----------------------------------------
        Gui, Settings:Tab, 2
        Gui, Settings:Add, GroupBox, x20 y45 w330 h116, Text Editor
        Gui, Settings:Add, Text, x35 y69 w68 h20 +0x200, Provider
        Gui, Settings:Add, DropDownList, x105 y67 w225 vSettingsEditorProvider gSUI_EditorProviderChanged, Notepads|Notepad|VSCode|Custom
        Gui, Settings:Add, Text, x35 y98 w68 h20 +0x200, Custom path
        Gui, Settings:Add, Edit, x105 y96 w225 h21 vSettingsEditorCustomPath
        Gui, Settings:Add, Text, x35 y123 w68 h20 +0x200, Custom args
        Gui, Settings:Add, Edit, x105 y121 w225 h21 vSettingsEditorArgs

        Gui, Settings:Add, GroupBox, x20 y171 w330 h136, Output Paths
        Gui, Settings:Add, Text, x35 y196 w68 h20 +0x200, Cookies dir
        Gui, Settings:Add, Edit, x105 y194 w225 h21 vSettingsAuthSaveDir
        Gui, Settings:Add, Text, x35 y231 w68 h20 +0x200, Auth json
        Gui, Settings:Add, Edit, x105 y229 w225 h21 vSettingsAuthOutputPath
        Gui, Settings:Add, Text, x35 y266 w68 h20 +0x200, URL export
        Gui, Settings:Add, Edit, x105 y264 w225 h21 vSettingsBrowserUrlExportPath

        Gui, Settings:Add, GroupBox, x20 y315 w330 h66, PowerPoint
        Gui, Settings:Add, Text, x35 y341 w70 h20 +0x200, Caption H
        Gui, Settings:Add, Edit, x105 y339 w70 h21 vSettingsPPTCaptionGapH gSUI_PositiveFloatEditChanged
        Gui, Settings:Add, Text, x190 y341 w70 h20 +0x200, Caption V
        Gui, Settings:Add, Edit, x260 y339 w70 h21 vSettingsPPTCaptionGapV gSUI_PositiveFloatEditChanged

        Gui, Settings:Add, GroupBox, x370 y45 w370 h82, Advanced
        Gui, Settings:Add, CheckBox, x388 y68 w190 h20 vSettingsBrowserPdfZoomShortcutFirst, PDF zoom: 先に Ctrl+\ を試す
        Gui, Settings:Add, Text, x388 y97 w112 h20 +0x200, Explorer repeat
        Gui, Settings:Add, Edit, x497 y95 w44 h21 Number vSettingsMouseWheelExplorerRepeat gSUI_NonNegativeIntEditChanged
        Gui, Settings:Add, Text, x560 y97 w36 h20 +0x200, Base
        Gui, Settings:Add, Edit, x597 y95 w46 h21 vSettingsCursorBaseSpeed gSUI_PositiveFloatEditChanged
        Gui, Settings:Add, Text, x651 y97 w30 h20 +0x200, Max
        Gui, Settings:Add, Edit, x682 y95 w40 h21 vSettingsCursorMaxSpeed gSUI_PositiveFloatEditChanged

        Gui, Settings:Add, GroupBox, x370 y134 w370 h82, Cursor
        Gui, Settings:Add, Text, x388 y159 w36 h20 +0x200, Accel
        Gui, Settings:Add, Edit, x425 y157 w46 h21 vSettingsCursorAcceleration gSUI_PositiveFloatEditChanged
        Gui, Settings:Add, Text, x479 y159 w26 h20 +0x200, ms
        Gui, Settings:Add, Edit, x506 y157 w39 h21 Number vSettingsCursorTimerInterval gSUI_NonNegativeIntEditChanged
        Gui, Settings:Add, Text, x560 y159 w34 h20 +0x200, Cols
        Gui, Settings:Add, Edit, x596 y157 w40 h21 Number vSettingsCursorGridCols gSUI_NonNegativeIntEditChanged
        Gui, Settings:Add, Text, x644 y159 w34 h20 +0x200, Rows
        Gui, Settings:Add, Edit, x680 y157 w42 h21 Number vSettingsCursorGridRows gSUI_NonNegativeIntEditChanged
        Gui, Settings:Add, Text, x388 y186 w36 h20 +0x200, Inset
        Gui, Settings:Add, Edit, x425 y184 w46 h21 Number vSettingsCursorEdgeInset gSUI_NonNegativeIntEditChanged

        Gui, Settings:Add, GroupBox, x370 y224 w370 h108, Debug
        Gui, Settings:Add, CheckBox, x388 y249 w145 h20 vSettingsIndicatorDebug, IndicatorManager
        Gui, Settings:Add, CheckBox, x548 y249 w145 h20 vSettingsMouseGestureDebug, MouseGesture
        Gui, Settings:Add, CheckBox, x388 y275 w145 h20 vSettingsMouseWheelDebug, MouseWheel
        Gui, Settings:Add, CheckBox, x548 y275 w145 h20 vSettingsBrowserPdfZoomDebug, Browser PDF
        Gui, Settings:Add, CheckBox, x388 y301 w145 h20 vSettingsPPTSpacingDebug, PPT spacing
        Gui, Settings:Add, CheckBox, x548 y301 w145 h20 vSettingsPPTCaptionDebug, PPT caption

        ; ChatterGuard
        Gui, Settings:Add, GroupBox, x370 y340 w370 h52, ChatterGuard
        Gui, Settings:Add, Text, x388 y360 w36 h20 +0x200, 同種
        Gui, Settings:Add, Edit, x426 y359 w40 h21 vSettingsSameEvent, %CG_SameEventThreshold%
        Gui, Settings:Add, Text, x470 y360 w18 h20 +0x200, ms
        Gui, Settings:Add, Text, x500 y360 w36 h20 +0x200, 交差
        Gui, Settings:Add, Edit, x538 y359 w40 h21 vSettingsCrossEvent, %CG_CrossEventThreshold%
        Gui, Settings:Add, Text, x582 y360 w18 h20 +0x200, ms

        Gui, Settings:Add, Button, x20 y393 w120 h27 gSUI_SaveAdvancedSettings, 詳細設定を保存
        Gui, Settings:Add, Button, x150 y393 w120 h27 gSUI_ResetAdvancedSettings, 保存済みを再読込
        Gui, Settings:Add, Text, x20 y423 w330 h18 vSettingsValidationHint,

        ; -----------------------------------------
        ; ▼ タブの配置指定を終了 (以降はタブ外の要素)
        ; -----------------------------------------
        Gui, Settings:Tab

        ; =========================================
        ; --- リストビュー等の初期化処理 ---
        ; =========================================
        SUI_BuildItemList()
        Gui, Settings:ListView, SettingsItemsLV
        LV_ModifyCol(1, 28)
        LV_ModifyCol(2, 170)

        Gui, Settings:ListView, SettingsLV
        LV_ModifyCol(1, 160)
        LV_ModifyCol(2, 315)
        SUI_LoadAdvancedSettingsIntoGui()
        SUI_ApplyThemeToControls()
        SUI_SnapshotCheckStates()
        SUI_SetDetailPane(SUI_DefaultDetailMessage())

        Gui, Settings:ListView, SettingsItemsLV
        firstID := LV_GetCount() ? 1 : 0
        if (firstID) {
            LV_Modify(firstID, "Select Focus Vis")
            SUI_RefreshLV(firstID)
        }

        ; 全体のウィンドウサイズを表示
        Gui, Settings:Show, w770 h550 xCenter yCenter
        SUI_IsInitializing := false
        SUI_DebugLog("settings_show")
    }

}

SUI_LoadAdvancedSettingsIntoGui() {
    global TextEditorProvider, TextEditorCustomPath, TextEditorArgsTemplate
    global SaveDir, OutputFileName, Browser_URLExportPath
    global Browser_PDFZoomTryShortcutFirst
    global MouseWheel_ExplorerScrollBarRepeat
    global CursorConfig, CursorGridConfig
    global SUI_DebugEnabled, MG_DebugEnabled, MouseWheel_DebugEnabled
    global Browser_PDFZoomDebugEnabled, PPT_SpacingLogEnabled, PPT_CaptionLogEnabled
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical
    global CG_SameEventThreshold, CG_CrossEventThreshold

    GuiControl, Settings:ChooseString, SettingsEditorProvider, %TextEditorProvider%
    GuiControl, Settings:, SettingsEditorCustomPath, %TextEditorCustomPath%
    GuiControl, Settings:, SettingsEditorArgs, %TextEditorArgsTemplate%

    GuiControl, Settings:, SettingsAuthSaveDir, %SaveDir%
    GuiControl, Settings:, SettingsAuthOutputPath, %OutputFileName%
    GuiControl, Settings:, SettingsBrowserUrlExportPath, %Browser_URLExportPath%

    GuiControl, Settings:, SettingsPPTCaptionGapH, % SUI_FormatNumber(PPT_CaptionVisualGapHorizontal, 2)
    GuiControl, Settings:, SettingsPPTCaptionGapV, % SUI_FormatNumber(PPT_CaptionVisualGapVertical, 2)

    GuiControl, Settings:, SettingsBrowserPdfZoomShortcutFirst, % Browser_PDFZoomTryShortcutFirst ? 1 : 0
    GuiControl, Settings:, SettingsMouseWheelExplorerRepeat, %MouseWheel_ExplorerScrollBarRepeat%

    GuiControl, Settings:, SettingsCursorBaseSpeed, % SUI_FormatNumber(CursorConfig.BaseSpeed, 2)
    GuiControl, Settings:, SettingsCursorMaxSpeed, % SUI_FormatNumber(CursorConfig.MaxSpeed, 2)
    GuiControl, Settings:, SettingsCursorAcceleration, % SUI_FormatNumber(CursorConfig.Acceleration, 2)
    GuiControl, Settings:, SettingsCursorTimerInterval, % CursorConfig.TimerInterval
    GuiControl, Settings:, SettingsCursorGridCols, % CursorGridConfig.DefaultCols
    GuiControl, Settings:, SettingsCursorGridRows, % CursorGridConfig.DefaultRows
    GuiControl, Settings:, SettingsCursorEdgeInset, % CursorGridConfig.EdgeInset

    GuiControl, Settings:, SettingsIndicatorDebug, % SUI_DebugEnabled ? 1 : 0
    GuiControl, Settings:, SettingsMouseGestureDebug, % MG_DebugEnabled ? 1 : 0
    GuiControl, Settings:, SettingsMouseWheelDebug, % MouseWheel_DebugEnabled ? 1 : 0
    GuiControl, Settings:, SettingsBrowserPdfZoomDebug, % Browser_PDFZoomDebugEnabled ? 1 : 0
    GuiControl, Settings:, SettingsPPTSpacingDebug, % PPT_SpacingLogEnabled ? 1 : 0
    GuiControl, Settings:, SettingsPPTCaptionDebug, % PPT_CaptionLogEnabled ? 1 : 0
    GuiControl, Settings:, SettingsSameEvent, %CG_SameEventThreshold%
    GuiControl, Settings:, SettingsCrossEvent, %CG_CrossEventThreshold%
    GuiControl, Settings:, SettingsValidationHint,

    SUI_RefreshEditorProviderControls()
}

SUI_RefreshEditorProviderControls() {
    GuiControlGet, editorProvider,, SettingsEditorProvider
    enableCustom := (editorProvider = "Custom")

    if (enableCustom) {
        GuiControl, Settings:Enable, SettingsEditorCustomPath
        GuiControl, Settings:Enable, SettingsEditorArgs
    } else {
        GuiControl, Settings:Disable, SettingsEditorCustomPath
        GuiControl, Settings:Disable, SettingsEditorArgs
    }
}

SUI_SanitizeNumericEditValue(value, allowFloat := false) {
    sanitized := ""
    dotSeen := false

    Loop, Parse, value
    {
        ch := A_LoopField
        if (ch >= "0" && ch <= "9") {
            sanitized .= ch
            continue
        }

        if (allowFloat && ch = "." && !dotSeen) {
            if (sanitized = "")
                sanitized := "0"
            sanitized .= "."
            dotSeen := true
        }
    }

    return sanitized
}

SUI_GetNumericControlSpec(controlName) {
    global CursorConfig

    if (controlName = "SettingsMouseWheelExplorerRepeat")
        return {Label: "Explorer repeat", Type: "int", Min: 1, Max: 20}
    if (controlName = "SettingsPPTCaptionGapH")
        return {Label: "Caption H", Type: "float", Min: 0, Max: 20, Decimals: 2}
    if (controlName = "SettingsPPTCaptionGapV")
        return {Label: "Caption V", Type: "float", Min: 0, Max: 20, Decimals: 2}
    if (controlName = "SettingsCursorBaseSpeed")
        return {Label: "Cursor Base", Type: "float", Min: 0.25, Max: 50, Decimals: 2}
    if (controlName = "SettingsCursorMaxSpeed") {
        GuiControlGet, currentBaseSpeed,, SettingsCursorBaseSpeed
        baseMin := SUI_NormalizeFloat(currentBaseSpeed, CursorConfig.BaseSpeed, 0.25, 50, 2)
        return {Label: "Cursor Max", Type: "float", Min: baseMin, Max: 200, Decimals: 2}
    }
    if (controlName = "SettingsCursorAcceleration")
        return {Label: "Cursor Accel", Type: "float", Min: 1.01, Max: 5, Decimals: 2}
    if (controlName = "SettingsCursorTimerInterval")
        return {Label: "Cursor ms", Type: "int", Min: 1, Max: 100}
    if (controlName = "SettingsCursorGridCols")
        return {Label: "Grid Cols", Type: "int", Min: 1, Max: 12}
    if (controlName = "SettingsCursorGridRows")
        return {Label: "Grid Rows", Type: "int", Min: 1, Max: 12}
    if (controlName = "SettingsCursorEdgeInset")
        return {Label: "Grid Inset", Type: "int", Min: 0, Max: 100}
    return ""
}

SUI_SetValidationHint(text := "") {
    GuiControl, Settings:, SettingsValidationHint, %text%
}

SUI_GetNumericHintText(spec) {
    if !IsObject(spec)
        return ""
    return spec.Label . ": " . spec.Min . " - " . spec.Max
}

SUI_ValidateNumericControl(controlName, value := "") {
    spec := SUI_GetNumericControlSpec(controlName)
    if !IsObject(spec)
        return ""

    if (value = "")
        GuiControlGet, value,, %controlName%

    value := Trim(value)
    if (value = "")
        return ""

    if (spec.Type = "int") {
        if !(value ~= "^\d+$")
            return SUI_GetNumericHintText(spec)
        numericValue := value + 0
    } else {
        if !(value ~= "^\d+(\.\d*)?$")
            return SUI_GetNumericHintText(spec)
        numericValue := value + 0
    }

    if (numericValue < spec.Min || numericValue > spec.Max)
        return SUI_GetNumericHintText(spec)
    return ""
}

SUI_ClampNumericControl(controlName) {
    spec := SUI_GetNumericControlSpec(controlName)
    if !IsObject(spec)
        return false

    GuiControlGet, currentValue,, %controlName%
    currentValue := Trim(currentValue)
    if (currentValue = "") {
        SUI_SetValidationHint("")
        return false
    }

    if (spec.Type = "int")
        normalizedValue := SUI_NormalizeInt(currentValue, spec.Min, spec.Min, spec.Max)
    else
        normalizedValue := SUI_NormalizeFloat(currentValue, spec.Min, spec.Min, spec.Max, spec.Decimals)

    if (spec.Type = "int")
        formattedValue := normalizedValue
    else
        formattedValue := SUI_FormatNumber(normalizedValue, spec.Decimals)

    if (currentValue != formattedValue)
        GuiControl, Settings:, %controlName%, %formattedValue%

    SUI_SetValidationHint("")
    return true
}

SUI_SanitizeNumericControl(allowFloat := false) {
    global SUI_IsInitializing
    static isUpdating := false

    if (SUI_IsInitializing || isUpdating || A_GuiControl = "")
        return

    GuiControlGet, currentValue,, %A_GuiControl%
    sanitizedValue := SUI_SanitizeNumericEditValue(currentValue, allowFloat)
    if (currentValue = sanitizedValue)
        return

    isUpdating := true
    GuiControl, Settings:, %A_GuiControl%, %sanitizedValue%
    isUpdating := false

    hintText := SUI_ValidateNumericControl(A_GuiControl, sanitizedValue)
    SUI_SetValidationHint(hintText)
}

SUI_PositiveFloatEditChanged() {
    SUI_SanitizeNumericControl(true)
}

SUI_NonNegativeIntEditChanged() {
    SUI_SanitizeNumericControl(false)
}

SUI_EditorProviderChanged() {
    global SUI_IsInitializing

    if (SUI_IsInitializing)
        return
    SUI_RefreshEditorProviderControls()
}

SUI_SaveAdvancedSettings() {
    SUI_SaveAdvancedSettingsFromGui("button")
}

SUI_ResetAdvancedSettings() {
    SUI_LoadConfig()
    PPT_CaptionInit()
    SUI_LoadAdvancedSettingsIntoGui()
    ToolTip, 詳細設定を再読込しました
    SetTimer, CloseToolTip, -1200
}



SUI_SaveAdvancedSettingsFromGui(reason := "manual") {
    global SUI_IsInitializing, SUI_SettingsGuiHwnd
    global TextEditorProvider, TextEditorCustomPath, TextEditorArgsTemplate
    global SaveDir, OutputFileName, Browser_URLExportPath
    global Browser_PDFZoomTryShortcutFirst
    global MouseWheel_ExplorerScrollBarRepeat
    global CursorConfig, CursorGridConfig
    global SUI_DebugEnabled, MG_DebugEnabled, MouseWheel_DebugEnabled
    global Browser_PDFZoomDebugEnabled, PPT_SpacingLogEnabled, PPT_CaptionLogEnabled
    global PPT_CaptionVisualGapHorizontal, PPT_CaptionVisualGapVertical
    global CG_SameEventThreshold, CG_CrossEventThreshold

    if (SUI_IsInitializing || !SUI_SettingsGuiHwnd)
        return false

    GuiControlGet, editorProvider,, SettingsEditorProvider
    GuiControlGet, editorCustomPath,, SettingsEditorCustomPath
    GuiControlGet, editorArgs,, SettingsEditorArgs
    GuiControlGet, authSaveDir,, SettingsAuthSaveDir
    GuiControlGet, authOutputPath,, SettingsAuthOutputPath
    GuiControlGet, browserUrlExportPath,, SettingsBrowserUrlExportPath
    GuiControlGet, pptCaptionGapH,, SettingsPPTCaptionGapH
    GuiControlGet, pptCaptionGapV,, SettingsPPTCaptionGapV
    GuiControlGet, browserTryShortcutFirst,, SettingsBrowserPdfZoomShortcutFirst
    GuiControlGet, wheelExplorerRepeat,, SettingsMouseWheelExplorerRepeat
    GuiControlGet, cursorBaseSpeed,, SettingsCursorBaseSpeed
    GuiControlGet, cursorMaxSpeed,, SettingsCursorMaxSpeed
    GuiControlGet, cursorAcceleration,, SettingsCursorAcceleration
    GuiControlGet, cursorTimerInterval,, SettingsCursorTimerInterval
    GuiControlGet, cursorGridCols,, SettingsCursorGridCols
    GuiControlGet, cursorGridRows,, SettingsCursorGridRows
    GuiControlGet, cursorEdgeInset,, SettingsCursorEdgeInset
    GuiControlGet, indicatorDebug,, SettingsIndicatorDebug
    GuiControlGet, mouseGestureDebug,, SettingsMouseGestureDebug
    GuiControlGet, mouseWheelDebug,, SettingsMouseWheelDebug
    GuiControlGet, browserPdfDebug,, SettingsBrowserPdfZoomDebug
    GuiControlGet, pptSpacingDebug,, SettingsPPTSpacingDebug
    GuiControlGet, pptCaptionDebug,, SettingsPPTCaptionDebug

    TextEditorProvider := SUI_NormalizeTextEditorProvider(editorProvider, TextEditorProvider)
    TextEditorCustomPath := Trim(editorCustomPath)
    TextEditorArgsTemplate := editorArgs
    SaveDir := SUI_NormalizeText(authSaveDir, SaveDir)
    OutputFileName := SUI_NormalizeText(authOutputPath, OutputFileName)
    Browser_URLExportPath := SUI_NormalizeText(browserUrlExportPath, Browser_URLExportPath)
    Browser_PDFZoomTryShortcutFirst := SUI_NormalizeBool(browserTryShortcutFirst, Browser_PDFZoomTryShortcutFirst)

    MouseWheel_ExplorerScrollBarRepeat := SUI_NormalizeInt(wheelExplorerRepeat, MouseWheel_ExplorerScrollBarRepeat, 1, 20)
    if IsFunc("MouseWheel_RebuildZoomRules")
        MouseWheel_RebuildZoomRules()

    CursorConfig.BaseSpeed := SUI_NormalizeFloat(cursorBaseSpeed, CursorConfig.BaseSpeed, 0.25, 50, 2)
    CursorConfig.MaxSpeed := SUI_NormalizeFloat(cursorMaxSpeed, CursorConfig.MaxSpeed, CursorConfig.BaseSpeed, 200, 2)
    CursorConfig.Acceleration := SUI_NormalizeFloat(cursorAcceleration, CursorConfig.Acceleration, 1.01, 5, 2)
    CursorConfig.TimerInterval := SUI_NormalizeInt(cursorTimerInterval, CursorConfig.TimerInterval, 1, 100)
    CursorGridConfig.DefaultCols := SUI_NormalizeInt(cursorGridCols, CursorGridConfig.DefaultCols, 1, 12)
    CursorGridConfig.DefaultRows := SUI_NormalizeInt(cursorGridRows, CursorGridConfig.DefaultRows, 1, 12)
    CursorGridConfig.EdgeInset := SUI_NormalizeInt(cursorEdgeInset, CursorGridConfig.EdgeInset, 0, 100)

    PPT_CaptionVisualGapHorizontal := SUI_NormalizeFloat(pptCaptionGapH, PPT_CaptionVisualGapHorizontal, 0, 20, 2)
    PPT_CaptionVisualGapVertical := SUI_NormalizeFloat(pptCaptionGapV, PPT_CaptionVisualGapVertical, 0, 20, 2)

    SUI_DebugEnabled := SUI_NormalizeBool(indicatorDebug, SUI_DebugEnabled)
    MG_DebugEnabled := SUI_NormalizeBool(mouseGestureDebug, MG_DebugEnabled)
    MouseWheel_DebugEnabled := SUI_NormalizeBool(mouseWheelDebug, MouseWheel_DebugEnabled)
    Browser_PDFZoomDebugEnabled := SUI_NormalizeBool(browserPdfDebug, Browser_PDFZoomDebugEnabled)
    PPT_SpacingLogEnabled := SUI_NormalizeBool(pptSpacingDebug, PPT_SpacingLogEnabled)
    PPT_CaptionLogEnabled := SUI_NormalizeBool(pptCaptionDebug, PPT_CaptionLogEnabled)

    ; ChatterGuard 閾値
    GuiControlGet, sameThresh, Settings:, SettingsSameEvent
    GuiControlGet, crossThresh, Settings:, SettingsCrossEvent
    CG_SameEventThreshold := SUI_NormalizeInt(sameThresh, 50, 10, 200)
    CG_CrossEventThreshold := SUI_NormalizeInt(crossThresh, 30, 5, 100)
    IniWrite, %CG_SameEventThreshold%, %SUI_ConfigPath%, ChatterGuard, SameEventThreshold
    IniWrite, %CG_CrossEventThreshold%, %SUI_ConfigPath%, ChatterGuard, CrossEventThreshold

    SUI_SaveConfig()
    SUI_LoadAdvancedSettingsIntoGui()
    SUI_DebugLog("advanced_settings_save", "reason=" . reason)
    return true
}

SUI_DefaultDetailMessage() {
    return "機能を選ぶと、対応するホットキーの詳細を表示します。"
}

SUI_SetDetailPane(text, header := "詳細") {
    global SettingsCodePreviewEdit

    GuiControl, Settings:, SettingsCodePreviewLabel, %header%
    text := StrReplace(text, "`r`n", "`n")
    text := StrReplace(text, "`r", "`n")
    GuiControl, Settings:, SettingsCodePreviewEdit, %text%
}

SUI_MakePreviewSpec(match, before := 2, after := 2, sourceFile := "") {
    if (sourceFile = "")
        sourceFile := A_ScriptDir . "\main.ahk"
    return {Match: match, Before: before, After: after, SourceFile: sourceFile}
}

SUI_HelpItem(key, desc, action := "", when := "", note := "", sourceMatch := "", previewBefore := 1, previewAfter := 2, sourceFile := "") {
    if (sourceFile = "")
        sourceFile := A_ScriptDir . "\main.ahk"

    return {Kind: "item"
        , Key: key
        , Desc: desc
        , Action: action
        , When: when
        , Note: note
        , SourceMatch: sourceMatch
        , PreviewBefore: previewBefore
        , PreviewAfter: previewAfter
        , SourceFile: sourceFile}
}

SUI_HelpSection(title, note := "", when := "", sourceMatch := "", previewBefore := 0, previewAfter := 6, sourceFile := "") {
    if (sourceFile = "")
        sourceFile := A_ScriptDir . "\main.ahk"

    return {Kind: "section"
        , Key: title
        , Desc: ""
        , Action: ""
        , When: when
        , Note: note
        , SourceMatch: sourceMatch
        , PreviewBefore: previewBefore
        , PreviewAfter: previewAfter
        , SourceFile: sourceFile}
}

SUI_HelpSpacer() {
    return {Kind: "spacer"
        , Key: ""
        , Desc: ""
        , Action: ""
        , When: ""
        , Note: ""
        , SourceMatch: ""
        , PreviewBefore: ""
        , PreviewAfter: ""
        , SourceFile: ""}
}

SUI_GetHelpEntryValue(entry, fieldName, defaultValue := "") {
    if (IsObject(entry) && entry.HasKey(fieldName))
        return entry[fieldName]
    return defaultValue
}

SUI_EntryHasPreview(entry) {
    return (Trim(SUI_GetHelpEntryValue(entry, "SourceMatch")) != "")
}

SUI_BuildEntryPreviewSpec(entry) {
    if !SUI_EntryHasPreview(entry)
        return ""

    before := SUI_GetHelpEntryValue(entry, "PreviewBefore", 1)
    after := SUI_GetHelpEntryValue(entry, "PreviewAfter", 2)
    sourceFile := SUI_GetHelpEntryValue(entry, "SourceFile", "")

    if (before = "")
        before := 1
    if (after = "")
        after := 2
    return SUI_MakePreviewSpec(SUI_GetHelpEntryValue(entry, "SourceMatch"), before, after, sourceFile)
}

SUI_AppendDetailSection(ByRef text, title, body, preserveIndent := false) {
    if (preserveIndent) {
        if (Trim(body) = "")
            return
        bodyText := RTrim(body, "`r`n")
    } else {
        bodyText := Trim(body)
        if (bodyText = "")
            return
    }

    if (bodyText = "")
        return

    if (text != "")
        text .= "`r`n`r`n"
    text .= title . "`r`n" . bodyText
}

SUI_BuildHelpDetailText(entry, ByRef headerText := "") {
    kind := SUI_GetHelpEntryValue(entry, "Kind", "item")
    key := Trim(SUI_GetHelpEntryValue(entry, "Key"))
    desc := Trim(SUI_GetHelpEntryValue(entry, "Desc"))
    action := Trim(SUI_GetHelpEntryValue(entry, "Action"))
    whenText := Trim(SUI_GetHelpEntryValue(entry, "When"))
    note := Trim(SUI_GetHelpEntryValue(entry, "Note"))
    text := ""

    headerText := "詳細"
    if (key != "")
        headerText .= " (" . key . ")"

    if (kind = "spacer")
        return "区切り行です。"

    if (kind = "section") {
        if (note != "")
            SUI_AppendDetailSection(text, "概要", note)
        if (whenText != "")
            SUI_AppendDetailSection(text, "条件", whenText)
    } else {
        if (desc != "")
            SUI_AppendDetailSection(text, "説明", desc)
        if (action != "")
            SUI_AppendDetailSection(text, "動作", action)
        if (whenText != "")
            SUI_AppendDetailSection(text, "条件", whenText)
        if (note != "")
            SUI_AppendDetailSection(text, "補足", note)
    }

    if (SUI_EntryHasPreview(entry)) {
        spec := SUI_BuildEntryPreviewSpec(entry)
        sourceFile := spec.SourceFile
        SplitPath, sourceFile, fileName
        SUI_AppendDetailSection(text, "定義", fileName . " -> " . spec.Match)

        previewText := SUI_BuildPreviewText(spec, previewHeader)
        if (previewText != "")
            SUI_AppendDetailSection(text, previewHeader, previewText, true)
    }

    if (text = "") {
        if (kind = "section")
            text := "このセクションの項目を選ぶと詳細を表示します。"
        else
            text := "この行の追加情報はありません。"
    }
    return text
}

SUI_GetPreviewLines(path) {
    global _SUI_CodePreviewCachePath, _SUI_CodePreviewCacheLines

    if (_SUI_CodePreviewCachePath != path || !IsObject(_SUI_CodePreviewCacheLines)) {
        FileRead, fileText, %path%
        if (ErrorLevel)
            return ""
        fileText := StrReplace(fileText, "`r`n", "`n")
        fileText := StrReplace(fileText, "`r", "`n")
        _SUI_CodePreviewCacheLines := StrSplit(fileText, "`n")
        _SUI_CodePreviewCachePath := path
    }
    return _SUI_CodePreviewCacheLines
}

SUI_FindPreviewLine(lines, match) {
    if !IsObject(lines)
        return 0

    for lineNo, lineText in lines {
        if InStr(lineText, match)
            return lineNo
    }
    return 0
}

SUI_PadLeft(value, width) {
    text := value . ""
    while (StrLen(text) < width)
        text := " " . text
    return text
}

SUI_BuildPreviewText(spec, ByRef headerText := "") {
    lines := SUI_GetPreviewLines(spec.SourceFile)
    sourcePath := spec.SourceFile
    SplitPath, sourcePath, fileName

    if !IsObject(lines) {
        headerText := "コード抜粋 (" . fileName . ")"
        return "; 抜粋元ファイルを読み込めませんでした。"
    }

    matchLine := SUI_FindPreviewLine(lines, spec.Match)
    if (!matchLine) {
        headerText := "コード抜粋 (" . fileName . ")"
        return "; 対応するコード行が見つかりませんでした。`r`n; match: " . spec.Match
    }

    startLine := matchLine - spec.Before
    if (startLine < 1)
        startLine := 1
    endLine := matchLine + spec.After
    maxLine := lines.MaxIndex()
    if (endLine > maxLine)
        endLine := maxLine

    width := StrLen(endLine . "")
    previewText := ""
    Loop % endLine - startLine + 1 {
        currentLine := startLine + A_Index - 1
        marker := (currentLine = matchLine) ? " >" : " |"
        previewText .= marker . " " . SUI_PadLeft(currentLine, width) . " | " . lines[currentLine]
        if (currentLine < endLine)
            previewText .= "`r`n"
    }

    headerText := "コード抜粋 (" . fileName . ":" . matchLine . ")"
    return previewText
}

SUI_GetSelectedHelpRow() {
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsLV
    row := LV_GetNext()
    if (!row)
        row := LV_GetNext(0, "Focused")
    return row
}

SUI_GetRememberedHelpRow() {
    global _SUI_LastHelpRow

    row := SUI_GetSelectedHelpRow()
    if (row)
        return row
    return _SUI_LastHelpRow
}

SUI_FindInitialHelpRow() {
    global _SUI_HelpRowMap
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsLV
    rowCount := LV_GetCount()

    Loop %rowCount% {
        row := A_Index
        if !_SUI_HelpRowMap.HasKey(row)
            continue
        if (SUI_GetHelpEntryValue(_SUI_HelpRowMap[row].Entry, "Kind", "item") = "item")
            return row
    }

    return rowCount ? 1 : 0
}

SUI_IsSettingsWindowActive() {
    global SUI_SettingsGuiHwnd

    return (SUI_SettingsGuiHwnd && WinActive("ahk_id " . SUI_SettingsGuiHwnd))
}

SUI_HasHelpSelection() {
    return !!SUI_GetRememberedHelpRow()
}

SUI_QueueHelpRefresh(reason := "") {
    global _SUI_HelpRefreshPending
    static refreshHelpFn := Func("SUI_RefreshSelectedHelpRow")

    if (_SUI_HelpRefreshPending)
        return

    _SUI_HelpRefreshPending := true
    if (reason != "")
        SUI_DebugLog("help_refresh_queue", reason)
    SetTimer, % refreshHelpFn, -10
}

SUI_RefreshSelectedHelpRow() {
    global _SUI_HelpRefreshPending, _SUI_IsRebuildingHelpList

    _SUI_HelpRefreshPending := false
    if (_SUI_IsRebuildingHelpList || !SUI_IsSettingsWindowActive())
        return

    selectedRow := SUI_GetSelectedHelpRow()
    if (selectedRow)
        SUI_RefreshHelpDetails(selectedRow)
    SUI_DebugLog("help_refresh_apply", "row=" . selectedRow)
}

SUI_RefreshHelpDetails(helpRow := 0) {
    global _SUI_HelpRowMap, _SUI_LastHelpRow

    if (!helpRow)
        helpRow := SUI_GetRememberedHelpRow()

    if (!helpRow || !_SUI_HelpRowMap.HasKey(helpRow)) {
        _SUI_LastHelpRow := 0
        SUI_SetDetailPane(SUI_DefaultDetailMessage())
        return
    }

    _SUI_LastHelpRow := helpRow
    rowData := _SUI_HelpRowMap[helpRow]
    detailText := SUI_BuildHelpDetailText(rowData.Entry, headerText)
    SUI_SetDetailPane(detailText, headerText)
}

SUI_FormatHelpCopyText(entry) {
    key := Trim(entry.Key)
    desc := Trim(entry.Desc)

    if (key = "" && desc = "")
        return ""
    if (desc = "")
        return key
    if (key = "")
        return desc
    return key . "    " . desc
}

SUI_CopySelectedHelpRow() {
    global _SUI_HelpRowMap

    row := SUI_GetRememberedHelpRow()
    if (!row || !_SUI_HelpRowMap.HasKey(row))
        return false

    copyText := SUI_FormatHelpCopyText(_SUI_HelpRowMap[row].Entry)
    if (copyText = "")
        return false

    ClipboardWrite(copyText)
    SUI_DebugLog("help_copy", "row=" . row . " text=" . copyText)
    return true
}

SUI_IsHelpListFocused() {
    global SUI_SettingsGuiHwnd, SUI_SettingsLVHwnd

    if !(SUI_SettingsGuiHwnd && SUI_SettingsLVHwnd)
        return false
    if !WinActive("ahk_id " . SUI_SettingsGuiHwnd)
        return false
    return (DllCall("GetFocus", "Ptr") = SUI_SettingsLVHwnd)
}

SUI_InitHelpData() {
    global _SUI_HelpData
    d := {}
    mainFile := A_ScriptDir . "\main.ahk"
    browserFile := A_ScriptDir . "\Plugins\Browser.ahk"
    gestureMapFile := A_ScriptDir . "\Plugins\MouseGestureMap.ahk"

    navWhen := "EnableNavLayer = ON"
    winWhen := "EnableWinPlace = ON"
    winIslandWhen := "EnableWinPlace = ON かつ Window Island を使用"
    vdeskWhen := "EnableVDesk = ON"
    mouseEmuWhen := "EnableMouseEmu = ON"
    mouseBtnWhen := "EnableMouseBtn = ON"
    mouseBtnExceptPptWhen := "EnableMouseBtn = ON かつ POWERPNT.EXE 以外"
    gestureWhen := "EnableGestures = ON かつ GestureTargetGroup 上"
    browserWhen := "EnableBrowser = ON かつ BrowserGroup がアクティブ"
    pptWhen := "EnablePPT = ON かつ POWERPNT.EXE がアクティブ"
    excelWhen := "EnableExcel = ON かつ EXCEL.EXE がアクティブ"
    altWhen := "EnableAlt = ON"
    altExceptPptWhen := "EnableAlt = ON かつ POWERPNT.EXE 以外"
    othersWhen := "EnableOthers = ON"

    h := []
    h.Push(SUI_HelpItem("変換 + 1", "IME → 英語", "IME_ToEnglish()", navWhen, "", "vk1C & 1::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + 2", "IME → 日本語", "IME_ToJapanese()", navWhen, "", "vk1C & 2::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + 3", "Ctrl+Shift+6", "Send {Blind}^+6", navWhen, "", "vk1C & 3::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + 4", "Ctrl+Shift+2", "Send {Blind}^+2", navWhen, "", "vk1C & 4::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + J / K / I / L", "カーソル移動 (←↓↑→)", "Send {Blind}{Left/Down/Up/Right}", navWhen, "", "vk1C & j::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("変換 + U / O", "Home / End", "Send {Blind}{Home/End}", navWhen, "", "vk1C & u::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + P", "リネーム (F2)", "Send {Blind}{F2}", navWhen, "", "vk1C & p::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + N", "ペイント起動", "OpenWithMspaint(0)", navWhen, "", "vk1C & n::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + M", "テキストエディタ起動", "OpenTextEditor(0)", navWhen, "", "vk1C & m::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + T", "日時挿入 (yyyy/MM/dd (ddd) HH:mm)", "InsertDateTime(...)", navWhen, "", "vk1C & t::", 1, 1, mainFile))
    d["EnableNavLayer"] := h

    h := []
    h.Push(SUI_HelpItem("Win+Ctrl+B", "ウィンドウ情報取得", "GetActiveWindowInfo()", winWhen, "", "^#b::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Shift+K", "Bluetooth設定", "Run ms-settings:bluetooth", winWhen, "", "+#k::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+1/2/3", "右側プリセット配置", "MoveWindowRatio(...)", winWhen, "", "^#1::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Shift+1/2/3", "左側プリセット配置", "MoveWindowRatio(...)", winWhen, "", "^+#1::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+8", "高さ最大化 (上寄せ)", "MoveWindowMaxHeightKeepWidth(""A"", ""Top"")", winWhen, "", "^#8::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Shift+8", "高さ最大化 (下寄せ)", "MoveWindowMaxHeightKeepWidth(""A"", ""Bottom"")", winWhen, "", "^+#8::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+9", "横幅最大化 (下寄せ)", "MoveWindowRatio(...)", winWhen, "", "^#9::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+G", "Gridモード切替", "Grid_ToggleMode()", winWhen, "", "^#g::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Shift+G", "Window Island 切替", "WindowIsland_Toggle()", winWhen, "", "^+#g::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+J/K/I/L", "Grid移動 (←↓↑→)", "Grid_Move(dx, dy)", winWhen, "", "^#j::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Shift+J/K/I/L", "Gridリサイズ", "Grid_Resize(...)", winWhen, "", "^+#j::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+F11", "Downloadsフォルダ", "OpenMoveExplorer(profilePath . ""\Downloads"", ...)", winWhen, "", "^#F11::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+F12", "VSCode起動", "OpenVSCode()", winWhen, "", "^#F12::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Shift+F12", "スクリプトリロード", "Reload", winWhen, "", "^+#F12::", 1, 1, mainFile))
    h.Push(SUI_HelpSection("【Window Island】", "配置計算時に monitor 端とセル間へ余白を入れます。MoveWindowRatio / WindowGrid / CursorGrid に反映されます。", winIslandWhen, "WindowIsland_Toggle() {", 0, 4, A_ScriptDir . "\Plugins\WindowManager.ahk"))
    d["EnableWinPlace"] := h

    h := []
    h.Push(SUI_HelpItem("Win+Q", "左の仮想デスクトップへ", "Send Win+Ctrl+Left", vdeskWhen, "", "#q::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+W", "右の仮想デスクトップへ", "Send Win+Ctrl+Right", vdeskWhen, "", "#w::", 1, 1, mainFile))
    d["EnableVDesk"] := h

    h := []
    h.Push(SUI_HelpItem("F13 + O/K/L/;", "カーソル移動 (↑←↓→)", "Cursor_MoveHotkeyDown() -> Cursor_StartContinuous()", mouseEmuWhen, "キー割当は Cursor_GetHotkeyConfig() で定義", "Cursor_GetHotkeyConfig() {", 0, 4, mainFile))
    h.Push(SUI_HelpItem("F13 + Ctrl + O/K/L/;", "グリッドジャンプ", "Cursor_MoveHotkeyGrid() -> Cursor_GridMoveByDirection()", mouseEmuWhen, "Ctrl 同時押しでグリッドモード", "Cursor_MoveHotkeyGrid() {", 0, 4, A_ScriptDir . "\Plugins\MouseCursor.ahk"))
    h.Push(SUI_HelpItem("F13 + I", "左クリック (押下/解放)", "Click Down / Click Up", mouseEmuWhen, "", "F13 & i::Click, Down", 1, 3, mainFile))
    h.Push(SUI_HelpItem("F13 + .", "中クリック", "Click, Middle", mouseEmuWhen, "", "F13 & .::Click, Middle", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F13 + P", "右クリック (押下/解放)", "Click, Right, Down / Up", mouseEmuWhen, "", "F13 & p::Click, Right, Down", 1, 2, mainFile))
    d["EnableMouseEmu"] := h

    h := []
    h.Push(SUI_HelpItem("F15", "Ctrl+V (貼り付け)", "Send ^v", mouseBtnExceptPptWhen, "", "F15::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F16", "Ctrl+C (コピー)", "Send ^c", mouseBtnWhen, "", "F16::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F17", "Ctrl+W (タブ閉じ)", "Send ^w", mouseBtnWhen, "", "F17::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("XButton1", "戻る", "XButton1", mouseBtnWhen, "", "XButton1::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("XButton2", "進む", "XButton2", mouseBtnWhen, "", "XButton2::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F15 + MButton", "メディア再生/一時停止", "SendInput {Media_Play_Pause}", mouseBtnWhen, "", "F15 & MButton::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("XButton1 + Wheel", "横スクロール", "MouseWheel_HScroll(""Left/Right"")", mouseBtnWhen, "", "XButton1 & WheelUp::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("XButton2 + Wheel", "ズーム (拡大/縮小)", "MouseWheel_Zoom(""In/Out"")", mouseBtnWhen, "", "XButton2 & WheelUp::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F15 + Wheel", "音量 (上げ/下げ)", "Send {Volume_Up/Volume_Down}", mouseBtnWhen, "", "F15 & WheelUp::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F16 + Wheel", "Alt+Tab (前/次)", "AltTabAction(""Prev/Next"")", mouseBtnWhen, "", "F16 & WheelDown::", 1, 2, mainFile))
    d["EnableMouseBtn"] := h

    h := []
    h.Push(SUI_HelpSection("【基本】", "右ボタン押下中に 8 方向ジェスチャを認識します。対象: Browser / Explorer / Editor / Office / Pycharm。", gestureWhen, "$RButton::", 1, 5, mainFile))
    h.Push(SUI_HelpItem("右ドラッグ", "8 方向ジェスチャー", "MG_RecognizeGesture() -> MG_ExecuteAction()", gestureWhen, "", "$RButton::", 1, 5, mainFile))
    h.Push(SUI_HelpItem("右 + WheelUp", "Ctrl+Home (先頭へ)", "MG_ScrollAction(""Up"")", gestureWhen, "右ボタン押下中のホイールで実行", "WheelUp::MG_ScrollAction(""Up"")", 1, 1, mainFile))
    h.Push(SUI_HelpItem("右 + WheelDown", "Ctrl+End (末尾へ)", "MG_ScrollAction(""Down"")", gestureWhen, "右ボタン押下中のホイールで実行", "WheelDown::MG_ScrollAction(""Down"")", 1, 1, mainFile))
    h.Push(SUI_HelpSpacer())

    h.Push(SUI_HelpSection("【Browser】", "BrowserGroup 用のジェスチャ割当です。", "BrowserGroup 上でジェスチャ実行", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↗", "WinMinimize, A", "WinMinimize, A", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↙", "Send, ^+t", "Send, ^+t", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↖", "Send, ^1", "Send, ^1", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↘", "Send, ^9", "Send, ^9", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("→", "Send, ^{Tab}", "Send, ^{Tab}", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("←", "Send, ^+{Tab}", "Send, ^+{Tab}", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↓", "Send, ^w", "Send, ^w", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↑", "Send, ^t", "Send, ^t", "BrowserGroup 上でジェスチャ実行", "", "Map_Browser(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpSpacer())

    h.Push(SUI_HelpSection("【Explorer】", "ExplorerGroup 用のジェスチャ割当です。", "ExplorerGroup 上でジェスチャ実行", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↗", "WinMinimize, A", "WinMinimize, A", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↙", "Send, ^z", "Send, ^z", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↖", "Send, ^1", "Send, ^1", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↘", "Send, ^1^+{Tab}", "Send, ^1^+{Tab}", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("→", "Send, ^{Tab}", "Send, ^{Tab}", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("←", "Send, ^+{Tab}", "Send, ^+{Tab}", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↓", "Send, ^w", "Send, ^w", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpItem("↑", "Send, ^t", "Send, ^t", "ExplorerGroup 上でジェスチャ実行", "", "Map_Explorer(g) {", 0, 10, gestureMapFile))
    h.Push(SUI_HelpSpacer())

    h.Push(SUI_HelpSection("【Editor】", "EditorGroup 用のジェスチャ割当です。", "EditorGroup 上でジェスチャ実行", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("→", "Send, ^{Tab}", "Send, ^{Tab}", "EditorGroup 上でジェスチャ実行", "", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("←", "Send, ^+{Tab}", "Send, ^+{Tab}", "EditorGroup 上でジェスチャ実行", "", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("↓", "Send, ^w", "Send, ^w", "EditorGroup 上でジェスチャ実行", "", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("↑", "Send, ^t", "Send, ^t", "EditorGroup 上でジェスチャ実行", "", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("other", "Map_Default", "Default: Map_Default(g)", "EditorGroup 上でジェスチャ実行", "", "Map_Editor(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpSpacer())

    h.Push(SUI_HelpSection("【Pycharm】", "JetBrains / Pycharm 用のジェスチャ割当です。", "pycharm64.exe 上でジェスチャ実行", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("→", "Send, !{Right}", "Send, !{Right}", "pycharm64.exe 上でジェスチャ実行", "", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("←", "Send, !{Left}", "Send, !{Left}", "pycharm64.exe 上でジェスチャ実行", "", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("↓", "Send, ^{F4}", "Send, ^{F4}", "pycharm64.exe 上でジェスチャ実行", "", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("↑", "Send, ^!{Insert}", "Send, ^!{Insert}", "pycharm64.exe 上でジェスチャ実行", "", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpItem("other", "Map_Default", "Default: Map_Default(g)", "pycharm64.exe 上でジェスチャ実行", "", "Map_Pycharm(g) {", 0, 9, gestureMapFile))
    h.Push(SUI_HelpSpacer())

    h.Push(SUI_HelpSection("【Default】", "共通フォールバックのジェスチャ割当です。", "個別マップで未定義のとき", "Map_Default(g) {", 0, 5, gestureMapFile))
    h.Push(SUI_HelpItem("↗", "WinMinimize, A", "WinMinimize, A", "個別マップで未定義のとき", "", "Map_Default(g) {", 0, 5, gestureMapFile))
    d["EnableGestures"] := h

    cgWhen := "EnableChatterGuard = ON"
    cgFile := A_ScriptDir . "\Plugins\ChatterGuard.ahk"
    h := []
    h.Push(SUI_HelpSection("【チャタリング防止】", "WH_MOUSE_LL フックで XButton1/XButton2 の誤連打を抑制します。閾値は設定画面の ChatterGuard セクションで調整可能。", cgWhen, "CG_LowLevelMouseProc()", 0, 0, cgFile))
    h.Push(SUI_HelpItem("XButton1", "DOWN/UP デバウンス", "CG_LowLevelMouseProc()", cgWhen, "SameEvent=" . CG_SameEventThreshold . "ms / CrossEvent=" . CG_CrossEventThreshold . "ms", "WH_MOUSE_LL", 0, 0, cgFile))
    h.Push(SUI_HelpItem("XButton2", "DOWN/UP デバウンス", "CG_LowLevelMouseProc()", cgWhen, "SameEvent=" . CG_SameEventThreshold . "ms / CrossEvent=" . CG_CrossEventThreshold . "ms", "WH_MOUSE_LL", 0, 0, cgFile))
    d["EnableChatterGuard"] := h

    h := []
    h.Push(SUI_HelpItem("Alt+W", "ウィンドウを閉じる", "Send !{F4}", altWhen, "", "!w::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+C", "選択内の \\ を / に置換", "ReplaceEscapeToSlash()", altWhen, "", "^!c::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+N", "選択ファイルをペイントで開く", "OpenWithMspaint(1)", altWhen, "", "^!n::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+M", "選択ファイルをエディタで開く", "OpenTextEditor(1)", altExceptPptWhen, "", "^!m::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Alt+Backspace", "Delete", "Send {Del}", altWhen, "", "!Backspace::", 1, 1, mainFile))
    d["EnableAlt"] := h

    h := []
    h.Push(SUI_HelpItem("ScrollLock", "無効化", "Return", othersWhen, "", "scrolllock::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("\", "_ を入力", "Send +{sc073}", othersWhen, "", "$sc073::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Shift+\", "\ を入力", "Send {sc073}", othersWhen, "", "$+sc073::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + Z", "N 長押しトグル", "Manage_N_Hold(""Toggle"")", othersWhen, "", "vk1C & z::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("変換 + X", "N 長押し解除", "Manage_N_Hold(""Off"")", othersWhen, "", "vk1C & x::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Alt+Backspace", "CapsLock OFF", "CapsLock_SetState(false)", othersWhen, "", "^!#Backspace::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Win+Ctrl+Alt+Delete", "CapsLock ON", "CapsLock_SetState(true)", othersWhen, "", "^!#Delete::", 1, 1, mainFile))
    d["EnableOthers"] := h

    h := []
    h.Push(SUI_HelpItem("Ctrl+\", "PDFズーム切替", "TogglePDFZoom()", browserWhen, "", "$^sc073::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F1", "サイト固有キー", "RunSiteSpecificKey(""{F1}"", KeyActions[""F1""])", browserWhen, "", "$F1 Up::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F2", "サイト固有キー", "RunSiteSpecificKey(F2)", browserWhen, "", "F2::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Shift+C", "プレーンURLコピー", "CopyPlaneURL()", browserWhen, "", "^+c::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("F8", "全タブURL取得", "GetAllEdgeURLs(false)", browserWhen, "", "F8::", 1, 1, mainFile))
    d["EnableBrowser"] := h

    h := []
    h.Push(SUI_HelpItem("Ctrl+Alt+J/L/I/K", "左/右/上/下揃え", "SetLeft() / SetRight() / SetTop() / SetBottom()", pptWhen, "", "^!l::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+U/O", "水平/垂直中央揃え", "SetHorizontalCenter() / SetVerticalCenter()", pptWhen, "", "^!u::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+M", "水平等間隔", "SetHorizontalSpacer()", pptWhen, "", "^!m::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+.", "垂直等間隔", "SetVerticalSpace()", pptWhen, "", "^!.::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+G/H", "グループ化/解除", "GroupSet() / GroupRelease()", pptWhen, "", "^!g::", 1, 6, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Shift+Alt+G/H", "前面/背面", "SetFront() / SetBack()", pptWhen, "", "^!h::", 1, 2, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+0", "キャプション preset 切替", "PPT_CycleCaptionPreset()", pptWhen, "", "^!0::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+1/2/3/4", "上/下/左/右キャプションの設置/削除", "PPT_AddEdgeCaption(edge)", pptWhen, "", "^!1::", 1, 3, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+5/6", "上下キャプション gap 微調整", "PPT_CaptionAdjustGap(""H"", delta)", pptWhen, "", "^!5::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+7/8", "左右キャプション gap 微調整", "PPT_CaptionAdjustGap(""V"", delta)", pptWhen, "", "^!7::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Shift+Alt+5/7", "キャプション gap 直接設定", "PPT_CaptionPromptGap(axis)", pptWhen, "", "^+!5::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Alt+1", "テキストのみ貼り付け", "PasteTextOnly()", pptWhen, "", "!1::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Alt+2", "枠線色", "PPT_CycleBlackBorder()", pptWhen, "", "!2::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Alt+3", "幅フォーカス", "FocusWidthField()", pptWhen, "", "!3::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Alt+4", "書式設定パネル開閉", "OpenFormatObject()", pptWhen, "", "!4::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Shift+Alt+4", "書式設定パネルを閉じる", "CloseFormatObject()", pptWhen, "", "+!4::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+V / F15", "画像メタデータ付き貼付け", "PasteImageWithMetadata()", pptWhen, "同じ機能を F15 にも割当", "^v::", 1, 2, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+E", "ソースエクスポート", "PPT_ExportSources()", pptWhen, "", "^!e::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Alt+Q", "ソース情報表示", "PPT_ShowSourcePath()", pptWhen, "", "^!q::", 1, 1, mainFile))
    d["EnablePPT"] := h

    h := []
    h.Push(SUI_HelpItem("Ctrl+Tab", "次のシート", "Send ^{PgDn}", excelWhen, "", "^Tab::", 1, 1, mainFile))
    h.Push(SUI_HelpItem("Ctrl+Shift+Tab", "前のシート", "Send ^{PgUp}", excelWhen, "", "^+Tab::", 1, 1, mainFile))
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
    SUI_AddLeaf("チャタリング防止", "EnableChatterGuard")
    SUI_AddLeaf("Alt", "EnableAlt")
    SUI_AddLeaf("その他", "EnableOthers")
    SUI_AddLeaf("ブラウザ", "EnableBrowser")
    SUI_AddLeaf("PowerPoint", "EnablePPT")
    SUI_AddLeaf("Excel", "EnableExcel")
}

SUI_AddLeaf(name, varName, disabled := false) {
    global _SUI_ItemMap, SettingsItemsLV, SUI_SettingsItemsLVHwnd
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsItemsLV

    displayName := disabled ? name . " (UIA未接続)" : name
    val := disabled ? 0 : SUI_GetFlagValue(varName)
    opts := ""
    if (val)
        opts := "Check"
    row := LV_Add(opts, "", displayName)
    _SUI_ItemMap[row] := {Var: varName, Row: row, Name: name, Disabled: disabled}

    if (disabled && SUI_SettingsItemsLVHwnd) {
        ; LVM_SETITEMSTATE (0x102B): wParam = item index, lParam = &LVITEM
        VarSetCapacity(lvi, 60, 0)
        NumPut(0, lvi, 12, "UInt")           ; state = 0 (no state image)
        NumPut(0xF000, lvi, 16, "UInt")      ; stateMask = LVIS_STATEIMAGEMASK
        SendMessage, 0x102B, % (row - 1), % &lvi,, ahk_id %SUI_SettingsItemsLVHwnd%
    }

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

SUI_QueueItemRefresh(reason := "") {
    global _SUI_ItemRefreshPending
    static refreshItemFn := Func("SUI_RefreshSelectedItem")

    _SUI_ItemRefreshPending := true
    if (reason != "")
        SUI_DebugLog("item_refresh_queue", reason)
    SetTimer, % refreshItemFn, Off
    SetTimer, % refreshItemFn, -15
}

SUI_RefreshSelectedItem() {
    global _SUI_ItemRefreshPending, SUI_SelectedItemID, _SUI_ItemMap

    _SUI_ItemRefreshPending := false
    if !SUI_IsSettingsWindowActive()
        return

    selectedID := SUI_GetSelectedItemID()
    if (!selectedID || !_SUI_ItemMap.HasKey(selectedID))
        return

    if (selectedID != SUI_SelectedItemID) {
        SUI_SelectedItemID := selectedID
        SUI_RefreshLV(selectedID)
    }

    SUI_DebugLog("item_refresh_apply", SUI_DebugDescribeItem(selectedID))
}

SUI_ItemsHandler() {
    global SUI_IsInitializing, SUI_SelectedItemID, _SUI_ItemMap

    if (SUI_IsInitializing) {
        SUI_DebugLog("list_event_ignored_init")
        return
    }

    evt        := A_GuiEvent
    info       := A_EventInfo
    flags      := ErrorLevel
    targetID   := (info && _SUI_ItemMap.HasKey(info)) ? info : SUI_GetSelectedItemID()
    selectedID := SUI_GetSelectedItemID()
    shouldRefresh := false

    if (evt = "K" || evt = "Normal" || evt = "F" || evt = "f")
        shouldRefresh := true
    else if (evt = "I" && info && _SUI_ItemMap.HasKey(info)
        && (InStr(flags, "S") || InStr(flags, "s") || InStr(flags, "F") || InStr(flags, "f")))
        shouldRefresh := true

    if (shouldRefresh)
        SUI_QueueItemRefresh("evt=" . evt . " info=" . info . " flags=" . flags)
    else if (!SUI_SelectedItemID && selectedID) {
        SUI_SelectedItemID := selectedID
    }

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
    global SUI_IsInitializing, _SUI_IsRebuildingHelpList

    if (SUI_IsInitializing || _SUI_IsRebuildingHelpList)
        return

    selectedRow := A_EventInfo ? A_EventInfo : SUI_GetSelectedHelpRow()

    SUI_RefreshHelpDetails(selectedRow)
    SUI_DebugLog("help_event"
        , "evt=" . A_GuiEvent
        . " info=" . A_EventInfo
        . " flags=" . ErrorLevel
        . " row=" . selectedRow)
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
    global _SUI_ItemMap, _SUI_HelpData, _SUI_HelpRowMap, SettingsLV
    global _SUI_LastHelpRow, _SUI_HelpRefreshPending, _SUI_IsRebuildingHelpList
    Gui, Settings:Default
    Gui, Settings:ListView, SettingsLV
    _SUI_IsRebuildingHelpList := true
    _SUI_LastHelpRow := 0
    _SUI_HelpRefreshPending := false
    LV_Delete()
    _SUI_HelpRowMap := {}

    if (!targetID || !_SUI_ItemMap.HasKey(targetID)) {
        SUI_SetDetailPane(SUI_DefaultDetailMessage())
        _SUI_IsRebuildingHelpList := false
        return
    }

    item := _SUI_ItemMap[targetID]
    vars := []

    if (item.Var != "") {
        vars.Push(item.Var)
    }

    for _, varName in vars {
        if (_SUI_HelpData.HasKey(varName)) {
            for _, entry in _SUI_HelpData[varName] {
                row := LV_Add("", entry.Key, entry.Desc)
                _SUI_HelpRowMap[row] := {Var: varName, Entry: entry}
            }
        }
    }

    LV_ModifyCol(1, 160)
    LV_ModifyCol(2, 315)

    firstRow := SUI_FindInitialHelpRow()
    if (firstRow) {
        LV_Modify(firstRow, "Select Focus Vis")
        SUI_RefreshHelpDetails(firstRow)
    } else {
        SUI_SetDetailPane("この機能に対応する詳細はありません。")
    }
    _SUI_IsRebuildingHelpList := false
}

SUI_SyncVars() {
    global _SUI_ItemMap
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    global EnableChatterGuard
    Gui, Settings:Default

    for itemID, item in _SUI_ItemMap {
        if (item.Var = "" || item.Disabled)
            continue

        v := SUI_IsItemChecked(itemID) ? 1 : 0
        if (item.Var = "EnableNavLayer")
            EnableNavLayer := v
        else if (item.Var = "EnableWinPlace")
            EnableWinPlace := v
        else if (item.Var = "EnableWinIsland")
            EnableWinIsland := v
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
        else if (item.Var = "EnableChatterGuard") {
            EnableChatterGuard := v
            if (v)
                CG_Init(["XButton1", "XButton2"])
            else
                CG_Cleanup()
        }
    }

    SUI_DebugLog("sync_vars")
}

SUI_GetFlagValue(varName) {
    global EnableNavLayer, EnableWinPlace, EnableWinIsland, EnableVDesk
    global EnableMouseEmu, EnableMouseBtn, EnableGestures
    global EnableAlt, EnableOthers, EnableBrowser, EnablePPT, EnableExcel
    global EnableChatterGuard

    if (varName = "EnableNavLayer")
        return EnableNavLayer
    if (varName = "EnableWinPlace")
        return EnableWinPlace
    if (varName = "EnableWinIsland")
        return EnableWinIsland
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
    if (varName = "EnableChatterGuard")
        return EnableChatterGuard
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
