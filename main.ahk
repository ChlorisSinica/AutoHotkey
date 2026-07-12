#NoEnv
#SingleInstance, Force
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
SetBatchLines, -1

; ==========================================================
; --- https://github.com/Descolada/UIAutomation ---
; ==========================================================
#Include %A_ScriptDir%\Lib\UIA_Interface.ahk
#Include %A_ScriptDir%\Lib\UIA_Browser.ahk
#Include %A_ScriptDir%\Lib\DebugUtil.ahk
#Include %A_ScriptDir%\Lib\FeatureState.ahk
#Include %A_ScriptDir%\Lib\HotkeyRegistry.ahk
#Include %A_ScriptDir%\Plugins\OCRCapture.ahk

; ==========================================================
; --- Pluginsファイルの読み込み ---
; ==========================================================
#Include %A_ScriptDir%\Plugins\UIA_Utils.ahk
#Include %A_ScriptDir%\Plugins\Application.ahk
#Include %A_ScriptDir%\Plugins\AppInit.ahk
#Include %A_ScriptDir%\Plugins\Browser.ahk
#Include %A_ScriptDir%\Plugins\GetAuth.ahk
#Include %A_ScriptDir%\Plugins\Hotstring.ahk
#Include %A_ScriptDir%\Plugins\IndicatorManager.ahk
#Include %A_ScriptDir%\Plugins\MouseCursor.ahk
#Include %A_ScriptDir%\Plugins\MouseWheel.ahk
#Include %A_ScriptDir%\Plugins\MouseGesture.ahk
#Include %A_ScriptDir%\Plugins\MouseGestureMap.ahk
#Include %A_ScriptDir%\Plugins\PowerPoint.ahk
#Include %A_ScriptDir%\Plugins\WoWsProfile.ahk
#Include %A_ScriptDir%\Plugins\WindowManager.ahk
#Include %A_ScriptDir%\Plugins\WindowGrid.ahk
#Include %A_ScriptDir%\Plugins\ChatterGuard.ahk

; ==========================================================
; ----- Indicator用変数 -----
; ==========================================================
global EnableNavLayer             := 0
global EnableWinPlace             := 0
global EnableWinIsland            := 0
global EnableVDesk                := 0
global EnableMouseEmu             := 0
global EnableMouseBtn             := 0
global EnableGestures             := 0
global EnableAlt                  := 0
global EnableOthers               := 0
global EnableBrowser              := 0
global EnablePPT                  := 0
global EnableExcel                := 0
global EnableChatterGuard         := 0
global CG_SameEventThreshold      := 120
global CG_CrossEventThreshold     := 50
global CG_MinPressThreshold       := 30
global EnableMouseCursorMode      := 0
global MouseBtn_XB1SuppressSingle := false
global MouseBtn_XB2SuppressSingle := false
global MouseBtn_ReleaseSettleMs   := 80

; ==========================================================
; --- 初期化処理 ---
; ==========================================================
App_Init()

; ==========================================================
; --- 初期化処理 ---
; ==========================================================
vk1C & F1::Settings_Open()
vk1C & F2::App_DebugStatus()
vk1C & F3::MG_DebugSnapshot("manual-hotkey")
vk1C & F4::Debug_DumpToClipboard()
vk1C & F5::OCR_CaptureAndRead()
vk1C & F6::OCR_ReadClipboard()
*^+!Esc::Emergency_ReleaseAllInputs()
#If WinActive("機能設定")
    Escape::Settings_Close()
#If

; ==========================================================
; ----- vk1C(Convert) -----
; ==========================================================
#If EnableNavLayer
    vk1C & 1::IME_ToEnglish()
    vk1C & 2::IME_ToJapanese()
    vk1C & 3::Send,{Blind}^+2
    vk1C & 4::Send,{Blind}^+6
    vk1C & n::OpenTextEditor(GetKeyState("Ctrl", "P") ? 1 : 0)
    vk1C & p::OpenWithMspaint(GetKeyState("Ctrl", "P") ? 1 : 0)
    vk1C & t::InsertDateTime("yyyy/MM/dd (ddd) HH:mm ")
    ^+#n::    TextEditor_ToggleProvider()
#If

#If (EnableNavLayer && EnableMouseEmu)
    vk1C & sc027::Main_ToggleCursorMode()
#If

#If (EnableNavLayer && (!EnableMouseEmu || !EnableMouseCursorMode))
    vk1C & i::      Send,{Blind}{Up}
    vk1C & j::      Send,{Blind}{Left}
    vk1C & k::      Send,{Blind}{Down}
    vk1C & l::      Send,{Blind}{Right}
    vk1C & u::      Send,{Blind}{Home}
    vk1C & o::      Send,{Blind}{End}
    vk1C & m::      Send,{Blind}{PgUp}
    vk1C & sc034::  Send,{Blind}{PgDn}
    vk1C & /::      Send,{Blind}{F2}
#If

#If (EnableMouseEmu && EnableMouseCursorMode)
    vk1C & i::         Main_HandleVk1cMove("Up")
    vk1C & j::         Main_HandleVk1cMove("Left")
    vk1C & k::         Main_HandleVk1cMove("Down")
    vk1C & l::         Main_HandleVk1cMove("Right")
    vk1C & u::         Main_HandleVk1cClick("Left")
    vk1C & o::         Main_HandleVk1cClick("Middle")
    vk1C & sc033::     Main_HandleVk1cClick("Right")
    vk1C & m::         Cursor_ScrollStart("UP")
    vk1C & sc034::     Cursor_ScrollStart("Down")
    vk1C & i Up::      Cursor_KeyUp("Up")
    vk1C & j Up::      Cursor_KeyUp("Left")
    vk1C & k Up::      Cursor_KeyUp("Down")
    vk1C & l Up::      Cursor_KeyUp("Right")
    vk1C & u Up::      Cursor_LeftClickUp()
    vk1C & sc033 Up::  Cursor_RightClickUp()
    vk1C & m Up::      Cursor_ScrollStop()
    vk1C & sc034 Up::  Cursor_ScrollStop()
    *vk1C Up::         Main_HandleVk1cModifierUp()
#If

; ==========================================================
; ----- Function-Key (for Mouse) -----
; ==========================================================
#If (EnableMouseBtn && !WinActive("ahk_exe POWERPNT.EXE"))
    F15::                   Send ^v                         ; 　　（手前側）
#If (EnableMouseBtn)
    $XButton1 Up::          MouseBtn_SendSingleOnRelease("XButton1") ; 戻る（手前側）
    $XButton2 Up::          MouseBtn_SendSingleOnRelease("XButton2") ; 進む（　奥側）
    F16::                   Send ^c                         ; 　　（　奥側）
    F17::                   Send ^w                         ; タブを閉じる
    F15 & MButton::         SendInput {Media_Play_Pause}    ;
    XButton1 & WheelUp::    MouseBtn_XButtonWheel("XButton1", "Left")  ; 左スクロール
    XButton1 & WheelDown::  MouseBtn_XButtonWheel("XButton1", "Right") ; 右スクロール
    XButton2 & WheelUp::    MouseBtn_XButtonWheel("XButton2", "In")    ; ウィンドウ拡大
    XButton2 & WheelDown::  MouseBtn_XButtonWheel("XButton2", "Out")   ; ウィンドウ縮小
    F15 & WheelUp::         Send, {Volume_Up}               ; 音量アップ
    F15 & WheelDown::       Send, {Volume_Down}             ; 音量ダウン
    F16 & WheelDown::       AltTabAction("Next")
    F16 & WheelUp::         AltTabAction("Prev")
    *F16 Up::               CloseAltTabMenu()
#If

MouseBtn_SendSingleOnRelease(button) {
    global MouseBtn_XB1SuppressSingle, MouseBtn_XB2SuppressSingle
    global MouseBtn_ReleaseSettleMs

    Sleep, %MouseBtn_ReleaseSettleMs%
    if GetKeyState(button)
        return

    if (button = "XButton1") {
        if (MouseBtn_XB1SuppressSingle) {
            MouseBtn_XB1SuppressSingle := false
            return
        }
    } else if (button = "XButton2") {
        if (MouseBtn_XB2SuppressSingle) {
            MouseBtn_XB2SuppressSingle := false
            return
        }
    }

    SendInput % "{" . button . "}"
}

MouseBtn_XButtonWheel(button, action) {
    global MouseBtn_XB1SuppressSingle, MouseBtn_XB2SuppressSingle

    if (button = "XButton1") {
        MouseBtn_XB1SuppressSingle := true
        MouseWheel_HScroll(action)
        return
    }

    if (button = "XButton2") {
        MouseBtn_XB2SuppressSingle := true
        MouseWheel_Zoom(action)
        return
    }
}

MouseBtn_ResetState() {
    global MouseBtn_XB1SuppressSingle, MouseBtn_XB2SuppressSingle
    MouseBtn_XB1SuppressSingle := false
    MouseBtn_XB2SuppressSingle := false
}

; ==========================================================
; ----- Virtual Desktop -----
; ==========================================================
#If (EnableVDesk)
    #q::Send {LWin Down}{Ctrl Down}{Left}{LWin Up}{Ctrl Up}
    #w::Send {LWin Down}{Ctrl Down}{Right}{LWin Up}{Ctrl Up}
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
    ^#0::       MoveWindowFullscreen("A")
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
#If

; ==========================================================
; ----- Others -----
; ==========================================================
#If (EnableOthers)
    scrolllock::    Return
    $sc073::        Send, +{sc073}  ; \ → _
    $+sc073::       Send, {sc073}  ; _ → \
    $sc056::        Send, +{sc073}  ; Moonlight backslash key -> underscore
    $+sc056::       Send, {sc073}  ; Moonlight Shift+backslash key -> backslash
    ^!#Backspace::  CapsLock_SetState(false)
    ^!#Delete::     CapsLock_SetState(true)
#If

#If (EnableOthers && !WinActive("ahk_exe Moonlight.exe"))
    $F18::          SendInput, {Text}\  ; Moonlight JIS yen/backslash bridge -> backslash
    $F19::          SendInput, {Text}|  ; Moonlight JIS yen/backslash bridge -> pipe
#If

#If (EnableOthers && WinActive("ahk_exe Moonlight.exe"))
    $sc07D::        SendInput, {F18}  ; Send JIS yen/backslash through Moonlight
    $+sc07D::       SendInput, {F19}  ; Send JIS Shift+yen/backslash through Moonlight
#If

#If WoWs_CanUseManageNHold()
    vk1C & z::      WoWs_ToggleNHold()
    vk1C & x::      WoWs_StopNHold()
#If

#If (EnableBrowser)
    ~$^sc073 Up::  Browser_LogCtrlSc073Probe()
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
    ^!l::   PPT_SetRight()
    ^!j::   PPT_SetLeft()
    ^!i::   PPT_SetTop()
    ^!k::   PPT_SetBottom()
    ^!g::   PPT_GroupSet()
    ^+!g::  PPT_GroupRelease()
    ^!u::   PPT_SetHorizontalCenter()
    ^!o::   PPT_SetVerticalCenter()
    ^!m::   PPT_SetHorizontalSpacer()
    ^!.::   PPT_SetVerticalSpace()
    ^!h::   PPT_SetFront()
    ^+!h::  PPT_SetBack()
    ^+!l::  PPT_SpacingRepeatStart("H",  1, "l")
    ^+!j::  PPT_SpacingRepeatStart("H", -1, "j")
    ^+!i::  PPT_SpacingRepeatStart("V",  1, "i")
    ^+!k::  PPT_SpacingRepeatStart("V", -1, "k")
    ^+!u::  PPT_AlignCenterToSmallest("H")
    ^+!o::  PPT_AlignCenterToSmallest("V")
    ^+!m::  PPT_GridRepeatStart("H", "m")
    ^+!.::  PPT_GridRepeatStart("V", ".")
    ^!0::   PPT_CycleCaptionPreset()
    ^!1::   PPT_AddEdgeCaption("Bottom")
    ^!2::   PPT_AddEdgeCaption("Top")
    ^!3::   PPT_AddEdgeCaption("Left")
    ^!4::   PPT_AddEdgeCaption("Right")
    ^!5::   PPT_CaptionAdjustGap("H", -0.25)
    ^!6::   PPT_CaptionAdjustGap("H",  0.25)
    ^!7::   PPT_CaptionAdjustGap("V", -0.25)
    ^!8::   PPT_CaptionAdjustGap("V",  0.25)
    ^+!5::  PPT_CaptionPromptGap("H")
    ^+!7::  PPT_CaptionPromptGap("V")
    !1::    PPT_PasteTextOnly()
    !2::    PPT_CycleBlackBorder()
    !3::    PPT_FocusWidthField()
    !4::    PPT_OpenFormatObject()
    +!4::   PPT_CloseFormatObject()
    ^v::    PPT_PasteImageWithMetadata()
    F15::   PPT_PasteImageWithMetadata()
    ^!e::   PPT_OpenSourceManager("view")
    ^!q::   PPT_ShowSourcePath()
    ^!F1::  PPT_ShowSourceCommands()
#If

; ==========================================================
; ----- Excel -----
; ==========================================================
#If (EnableExcel && WinActive("ahk_exe EXCEL.EXE"))
    ^Tab::  Send ^{PgDn}
    ^+Tab:: Send ^{PgUp}
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
    WheelUp::   MG_ScrollAction("Up")
    WheelDown:: MG_ScrollAction("Down")
#If

; ==========================================================
; ----- Toggle Function -----
; ==========================================================
Main_ToggleCursorMode() {
    global EnableNavLayer, EnableMouseEmu, EnableMouseCursorMode
    if !(EnableNavLayer && EnableMouseEmu)
        return false
    return Cursor_SetMode(!EnableMouseCursorMode, "toggle", true)
}

Main_HandleVk1cMove(direction) {
    ctrl := GetKeyState("Ctrl", "P"), alt := GetKeyState("Alt", "P")

    switch true {
    case (ctrl && alt):
        Cursor_MoveEdgeByDirection(direction)
    case ctrl:
        Cursor_MoveJumpByDirection(direction)
    case alt:
        Cursor_GridMoveByDirection(direction)
    default:
        Cursor_KeyDown(direction)
    }
}

Main_HandleVk1cClick(button) {
    switch button {
    case "Left":
        Cursor_LeftClickDown()
    case "Middle":
        Cursor_MiddleClick()
    case "Right":
        Cursor_RightClickDown()
    }
}

Main_HandleVk1cModifierUp() {
    Cursor_MoveHotkeyModifierUp()
}
