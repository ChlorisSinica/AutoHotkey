#NoEnv
#SingleInstance, Force
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
SetBatchLines, -1

; ==========================================================
; --- https://github.com/Descolada/UIAutomation ---
; ==========================================================
#Include %A_ScriptDir%\Plugins\UIA_Interface.ahk
#Include %A_ScriptDir%\Plugins\UIA_Browser.ahk

; ==========================================================
; --- Pluginsファイルの読み込み ---
; ==========================================================
#Include %A_ScriptDir%\Plugins\UIA_Utils.ahk
#Include %A_ScriptDir%\Plugins\Application.ahk
#Include %A_ScriptDir%\Plugins\Browser.ahk
#Include %A_ScriptDir%\Plugins\GetAuth.ahk
#Include %A_ScriptDir%\Plugins\Hotstring.ahk
#Include %A_ScriptDir%\Plugins\IndicatorManager.ahk
#Include %A_ScriptDir%\Plugins\MouseCursor.ahk
#Include %A_ScriptDir%\Plugins\MouseWheel.ahk
#Include %A_ScriptDir%\Plugins\MouseGesture.ahk
#Include %A_ScriptDir%\Plugins\MouseGestureMap.ahk
#Include %A_ScriptDir%\Plugins\PowerPoint.ahk
#Include %A_ScriptDir%\Plugins\TextEditor.ahk
#Include %A_ScriptDir%\Plugins\WindowManager.ahk
#Include %A_ScriptDir%\Plugins\WindowGrid.ahk
#Include %A_ScriptDir%\lib\CSharpUIA\UiaIntegration.ahk
#Include %A_ScriptDir%\Plugins\ChatterGuard.ahk

; ==========================================================
; ----- Indicator用変数 -----
; ==========================================================
global EnableNavLayer   := 1
global EnableWinPlace   := 1
global EnableWinIsland  := 0
global EnableVDesk      := 1
global EnableMouseEmu   := 1
global EnableMouseBtn   := 1
global EnableGestures   := 1
global EnableAlt        := 1
global EnableOthers     := 1
global EnableBrowser    := 1
global EnablePPT        := 1
global EnableExcel      := 1

; ==========================================================
; --- 初期化処理 ---
; ==========================================================
DllCall("SetThreadDpiAwarenessContext", "ptr", -4)
EnvGet, profilePath, USERPROFILE

Indicator_Init()
TrayTip, AutoHotkey, Script Reloaded, 2 ;

SUI_LoadConfig()
CG_Init(70, ["XButton1", "XButton2"])
OnExit("CG_Cleanup")
UiaInit()
OnExit("UiaCleanup")

MG_DebugInit()
Cursor_RegisterHotkeys(Cursor_GetHotkeyConfig())
PPT_SpacingLog("startup", "script=" . A_ScriptFullPath)
PPT_CaptionInit()

vk1C & F1::Settings_Open()
vk1C & F2::MG_DebugSnapshot("manual-hotkey")
vk1C & F3::
    ToolTip, % "UiaIsEditable=" . UiaIsEditable() . " UiaHasSel=" . UiaHasSelection() . " UiaCtrl=" . UiaControlType()
    SetTimer, CloseToolTip, -3000
return
#If WinActive("機能設定") && SUI_HasHelpSelection()
    ^c::SUI_CopySelectedHelpRow()
#If
#If WinActive("機能設定")
    Escape::Settings_Close()
#If

; ==========================================================
; ----- vk1C(Non-Convert) -----
; ==========================================================
#If (EnableNavLayer)
    vk1C & 1::IME_ToEnglish()
    vk1C & 2::IME_ToJapanese()
    vk1C & 3::Send,{Blind}^+6
    vk1C & 4::Send,{Blind}^+2
    vk1C & j::Send,{Blind}{Left}
    vk1C & k::Send,{Blind}{Down}
    vk1C & i::Send,{Blind}{Up}
    vk1C & l::Send,{Blind}{Right}
    vk1C & u::Send,{Blind}{Home}
    vk1C & o::Send,{Blind}{End}
    vk1C & p::Send,{Blind}{F2}
    vk1C & n::OpenWithMspaint(0)
    vk1C & m::OpenTextEditor(0)
    vk1C & t::InsertDateTime("yyyy/MM/dd (ddd) HH:mm ")
#If

; ==========================================================
; ----- Mouse Cursor -----
; ==========================================================
Cursor_GetHotkeyConfig() {
    return {Modifier: "F13"
        , Move: {o: "Up", k: "Left", l: "Down", sc027: "Right"}
        , Grid: {o: "Up", k: "Left", l: "Down", sc027: "Right"}}
}
#If (EnableMouseEmu)
    F13 & i::Click, Down
    F13 & .::Click, Middle
    F13 & p::Click, Right, Down
    F13 & i Up::Click, Up
    F13 & p Up::Click, Right, Up
#If

; ==========================================================
; ----- Function-Key (for Mouse) -----
; ==========================================================
#If (EnableMouseBtn && !WinActive("ahk_exe POWERPNT.EXE"))
    F15::                   Send ^v                         ; 　　（手前側）
#If (EnableMouseBtn)
    XButton1::              XButton1                        ; 戻る（手前側）
    XButton2::              XButton2                        ; 進む（　奥側）
    F16::                   Send ^c                         ; 　　（　奥側）
    F17::                   Send ^w                         ; タブを閉じる
    F15 & MButton::         SendInput {Media_Play_Pause}    ;
    XButton1 & WheelUp::    MouseWheel_HScroll("Left")      ; 左スクロール
    XButton1 & WheelDown::  MouseWheel_HScroll("Right")     ; 右スクロール
    XButton2 & WheelUp::    MouseWheel_Zoom("In")           ; ウィンドウ拡大
    XButton2 & WheelDown::  MouseWheel_Zoom("Out")          ; ウィンドウ縮小
    F15 & WheelUp::         Send, {Volume_Up}               ; 音量アップ
    F15 & WheelDown::       Send, {Volume_Down}             ; 音量ダウン
    F16 & WheelDown::       AltTabAction("Next")
    F16 & WheelUp::         AltTabAction("Prev")
    *F16 Up::               CloseAltTabMenu()
#If

; ==========================================================
; ----- Virtual Desktop -----
; ==========================================================
#If (EnableVDesk)
    #q::    Send {LWin Down}{Ctrl Down}{Left}{LWin Up}{Ctrl Up}
    #w::    Send {LWin Down}{Ctrl Down}{Right}{LWin Up}{Ctrl Up}
#If

; ==========================================================
; ----- Window Placement -----
; ==========================================================
#If (EnableWinPlace)
    ^#b::       GetActiveWindowInfo()
    +#k::       Run, ms-settings:bluetooth
    ^#1::       MoveWindowRatio("A", 0.503, 0.206, 0.360, 0.470)
    ^#2::       MoveWindowRatio("A", 0.503, 0.216, 0.404, 0.766)
    ^#3::       MoveWindowRatio("A", 0.503, 0.240, 0.456, 0.742)
    ^#8::       MoveWindowMaxHeightKeepWidth("A", "Top")
    ^#9::       MoveWindowRatio("A", 0.000, 0.030, 1.000, 0.970)
    ^+#1::      MoveWindowRatio("A", 0.003, 0.206, 0.360, 0.470)
    ^+#2::      MoveWindowRatio("A", 0.003, 0.216, 0.404, 0.766)
    ^+#3::      MoveWindowRatio("A", 0.003, 0.240, 0.456, 0.742)
    ^+#8::      MoveWindowMaxHeightKeepWidth("A", "Bottom")
    ^#F11::     OpenMoveExplorer(profilePath . "\Downloads", 0.180, 0.000, 0.320, 1.000)
    ^#F12::     OpenVSCode()
    ^+#F12::    Reload

    ^#g::       Grid_ToggleMode()
    ^+#g::      WindowIsland_Toggle()
    ^#j::       Grid_Move(-1,  0) ; Left
    ^#l::       Grid_Move( 1,  0) ; Right
    ^#i::       Grid_Move( 0, -1) ; Up
    ^#k::       Grid_Move( 0,  1) ; Down
    ^+#j::      Grid_Resize("Width",  -1) ; 幅縮小
    ^+#l::      Grid_Resize("Width",   1) ; 幅拡大
    ^+#i::      Grid_Resize("Height", -1) ; 高さ縮小
    ^+#k::      Grid_Resize("Height",  1) ; 高さ拡大
#If

; ==========================================================
; ----- Alt -----
; ==========================================================
#If (EnableAlt)
    !Backspace::    Send,{Del}
    !w::            Send, !{F4}
    ^!c::           ReplaceEscapeToSlash()
    ^!n::           OpenWithMspaint(1)
#If
#If (EnableAlt && !WinActive("ahk_exe POWERPNT.EXE"))
    ^!m::           OpenTextEditor(1)
#If

; ==========================================================
; ----- Others -----
; ==========================================================
#If (EnableOthers)
    scrolllock::        Return
    $sc073::            Send, +{sc073}  ; \ → _
    $+sc073::           Send, {sc073}  ; _ → \
    vk1C & z::          Manage_N_Hold("Toggle")
    vk1C & x::          Manage_N_Hold("Off")
    ^!#Backspace::      CapsLock_SetState(false)
    ^!#Delete::         CapsLock_SetState(true)
#If

; ==========================================================
; ----- Browser -----
; ==========================================================
#If (EnableBrowser && WinActive("ahk_group BrowserGroup"))
    ^+c::       CopyPlaneURL()
    $^sc073::   TogglePDFZoom()
    F1::        RunSiteSpecificKey("{F1}", KeyActions["F1"])
    F2::        RunSiteSpecificKey("{F2}", KeyActions["F2"])
    F8::        GetAllEdgeURLs(false)
#If

; ==========================================================
; ----- Power Point -----
; ==========================================================
#If (EnablePPT && WinActive("ahk_exe POWERPNT.EXE"))
    ^!l::   SetRight()
    ^!j::   SetLeft()
    ^!i::   SetTop()
    ^!k::   SetBottom()
    ^!g::   GroupSet()
    ^+!g::  GroupRelease()
    ^!u::   SetHorizontalCenter()
    ^!o::   SetVerticalCenter()
    ^!m::   SetHorizontalSpacer()
    ^!.::   SetVerticalSpace()
    ^!h::   SetFront()
    ^+!h::  SetBack()
    ^+!l::  PPT_SpacingRepeatStart("H",  1, "l")
    ^+!j::  PPT_SpacingRepeatStart("H", -1, "j")
    ^+!i::  PPT_SpacingRepeatStart("V",  1, "i")
    ^+!k::  PPT_SpacingRepeatStart("V", -1, "k")
    ^+!u::  PPT_AlignCenterToSmallest("H")
    ^+!o::  PPT_AlignCenterToSmallest("V")
    ^+!m::  PPT_GridRepeatStart("H", "m")
    ^+!.::  PPT_GridRepeatStart("V", ".")
    ^!1::   PPT_AddEdgeCaption("Top")
    ^!2::   PPT_AddEdgeCaption("Bottom")
    ^!3::   PPT_AddEdgeCaption("Left")
    ^!4::   PPT_AddEdgeCaption("Right")
    ^!5::   PPT_CaptionAdjustGap("H", -0.25)
    ^!6::   PPT_CaptionAdjustGap("H",  0.25)
    ^!7::   PPT_CaptionAdjustGap("V", -0.25)
    ^!8::   PPT_CaptionAdjustGap("V",  0.25)
    ^+!5::  PPT_CaptionPromptGap("H")
    ^+!7::  PPT_CaptionPromptGap("V")
    !1::    PasteTextOnly()
    !2::    PPT_CycleBlackBorder()
    !3::    SetFrameSize()
    !4::    OpenFormatObject()
    +!4::   CloseFormatObject()
    ^v::    PasteImageWithMetadata()
    F15::   PasteImageWithMetadata()
    ^!e::   PPT_ExportSources()
    ^!q::   PPT_ShowSourcePath()
#If

; ==========================================================
; ----- Excel -----
; ==========================================================
#If (EnableExcel && WinActive("ahk_exe EXCEL.EXE"))
    ^Tab::Send ^{PgDn}
    ^+Tab::Send ^{PgUp}
#If

; ==========================================================
; ----- Mouse Gesture -----
; ==========================================================
#If (EnableGestures && MouseIsOverTarget())
    $RButton::
        MouseGetPos, , , startWinID
        MG_DebugLog("RButton_hotkey_start", "startWinID=" . startWinID)
        gesture := MG_RecognizeGesture()
        MG_DebugLog("RButton_hotkey_end", "startWinID=" . startWinID . " gesture=" . gesture)
        MG_ExecuteAction(gesture, startWinID)
    return
#If

#If (EnableGestures && MG_IsActive && MouseIsOverTarget())
    WheelUp::MG_ScrollAction("Up")
    WheelDown::MG_ScrollAction("Down")
#If

