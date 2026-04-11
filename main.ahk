#NoEnv
#SingleInstance, Force
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
SetBatchLines, -1

; ==========================================================
; --- https://github.com/Descolada/UIAutomation ---
; ==========================================================
#Include %A_ScriptDir%\lib\UIA_Interface.ahk
#Include %A_ScriptDir%\lib\UIA_Browser.ahk
#Include %A_ScriptDir%\lib\DebugUtil.ahk
#Include %A_ScriptDir%\lib\FeatureState.ahk
#Include %A_ScriptDir%\lib\HotkeyRegistry.ahk

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
global CG_SameEventThreshold      := 50
global CG_CrossEventThreshold     := 30
global EnableMouseCursorMode      := 0

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
#If WinActive("機能設定")
    Escape::Settings_Close()
#If

; ==========================================================
; ----- vk1C(Convert) -----
; ==========================================================
#If Cursor_CanUseKeyboardMode()
    vk1C & 1::IME_ToEnglish()
    vk1C & 2::IME_ToJapanese()
    vk1C & 3::Send,{Blind}^+2
    vk1C & 4::Send,{Blind}^+6
    vk1C & n::OpenTextEditor(GetKeyState("Ctrl", "P") ? 1 : 0)
    vk1C & p::OpenWithMspaint(GetKeyState("Ctrl", "P") ? 1 : 0)
    vk1C & t::InsertDateTime("yyyy/MM/dd (ddd) HH:mm ")
#If

#If (EnableNavLayer || EnableMouseEmu)
    vk1C & sc027::
        if Cursor_CanToggleModes()
            Cursor_ToggleModeHotkey()
    return

    vk1C & i::
        if Cursor_IsMouseMode() {
            if GetKeyState("Ctrl", "P") {
                if GetKeyState("Alt", "P")
                    Cursor_MoveEdgeByDirection("Up")
                else
                    Cursor_MoveJumpByDirection("Up")
            } else if GetKeyState("Alt", "P") {
                Cursor_GridMoveByDirection("Up")
            } else {
                Cursor_KeyDown("Up")
            }
        } else if Cursor_IsKeyboardMode() {
            Send,{Blind}{Up}
        }
    return

    vk1C & j::
        if Cursor_IsMouseMode() {
            if GetKeyState("Ctrl", "P") {
                if GetKeyState("Alt", "P")
                    Cursor_MoveEdgeByDirection("Left")
                else
                    Cursor_MoveJumpByDirection("Left")
            } else if GetKeyState("Alt", "P") {
                Cursor_GridMoveByDirection("Left")
            } else {
                Cursor_KeyDown("Left")
            }
        } else if Cursor_IsKeyboardMode() {
            Send,{Blind}{Left}
        }
    return

    vk1C & k::
        if Cursor_IsMouseMode() {
            if GetKeyState("Ctrl", "P") {
                if GetKeyState("Alt", "P")
                    Cursor_MoveEdgeByDirection("Down")
                else
                    Cursor_MoveJumpByDirection("Down")
            } else if GetKeyState("Alt", "P") {
                Cursor_GridMoveByDirection("Down")
            } else {
                Cursor_KeyDown("Down")
            }
        } else if Cursor_IsKeyboardMode() {
            Send,{Blind}{Down}
        }
    return

    vk1C & l::
        if Cursor_IsMouseMode() {
            if GetKeyState("Ctrl", "P") {
                if GetKeyState("Alt", "P")
                    Cursor_MoveEdgeByDirection("Right")
                else
                    Cursor_MoveJumpByDirection("Right")
            } else if GetKeyState("Alt", "P") {
                Cursor_GridMoveByDirection("Right")
            } else {
                Cursor_KeyDown("Right")
            }
        } else if Cursor_IsKeyboardMode() {
            Send,{Blind}{Right}
        }
    return

    vk1C & u::
        if Cursor_IsMouseMode()
            Cursor_LeftClickDown()
        else if Cursor_IsKeyboardMode()
            Send,{Blind}{Home}
    return

    vk1C & o::
        if Cursor_IsMouseMode()
            Cursor_MiddleClick()
        else if Cursor_IsKeyboardMode()
            Send,{Blind}{End}
    return

    vk1C & sc033::
        if Cursor_IsMouseMode()
            Cursor_RightClickDown()
    return

    vk1C & m::
        if Cursor_IsMouseMode()
            Cursor_ScrollStart("Down")
        else if Cursor_IsKeyboardMode()
            Send,{Blind}{PgUp}
    return

    vk1C & sc034::
        if Cursor_IsMouseMode()
            Cursor_ScrollStart("Up")
        else if Cursor_IsKeyboardMode()
            Send,{Blind}{PgDn}
    return

    vk1C & /::
        if Cursor_IsKeyboardMode()
            Send,{Blind}{F2}
    return
#If

#If (EnableMouseEmu && EnableMouseCursorMode)
    vk1C & i Up::Cursor_KeyUp("Up")
    vk1C & j Up::Cursor_KeyUp("Left")
    vk1C & k Up::Cursor_KeyUp("Down")
    vk1C & l Up::Cursor_KeyUp("Right")
    vk1C & u Up::Cursor_LeftClickUp()
    vk1C & sc033 Up::Cursor_RightClickUp()
    vk1C & m Up::Cursor_ScrollStop()
    vk1C & sc034 Up::Cursor_ScrollStop()
    *vk1C Up::Cursor_MoveHotkeyModifierUp()
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
    ^!#Backspace::  CapsLock_SetState(false)
    ^!#Delete::     CapsLock_SetState(true)
#If

#If WoWs_CanUseManageNHold()
    vk1C & z::      WoWs_ToggleNHold()
    vk1C & x::      WoWs_StopNHold()
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
    !1::    PPT_PasteTextOnly()
    !2::    PPT_CycleBlackBorder()
    !3::    PPT_FocusWidthField()
    !4::    PPT_OpenFormatObject()
    +!4::   PPT_CloseFormatObject()
    ^v::    PPT_PasteImageWithMetadata()
    F15::   PPT_PasteImageWithMetadata()
    ^!e::   PPT_ExportSources()
    ^!q::   PPT_ShowSourcePath()
    ^!s::   PPT_ScanAndTagSources()
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
