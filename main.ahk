#NoEnv
#SingleInstance, Force
MsgBox, Reloading Script
EnvGet, profilePath, USERPROFILE
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
SetBatchLines, -1
#Include %A_ScriptDir%\Plugins\UIA_Interface.ahk
#Include %A_ScriptDir%\Plugins\UIA_Browser.ahk
#Include %A_ScriptDir%\Plugins\UIA_Utils.ahk
; from [https://github.com/Descolada/UIAutomation]
#Include %A_ScriptDir%\Plugins\Application.ahk
#Include %A_ScriptDir%\Plugins\TextEditor.ahk
#Include %A_ScriptDir%\Plugins\Browser.ahk
#Include %A_ScriptDir%\Plugins\GestureMap.ahk
#Include %A_ScriptDir%\Plugins\PowerPoint.ahk
#Include %A_ScriptDir%\Plugins\MyGesture.ahk
#Include %A_ScriptDir%\Plugins\Hotstring.ahk
#Include %A_ScriptDir%\Plugins\GetAuth.ahk

; ==========================================================
; ----- vk1C(Non-Convert) -----
; ==========================================================
vk1C & j::Send,{Blind}{Left}
vk1C & k::Send,{Blind}{Down}
vk1C & i::Send,{Blind}{Up}
vk1C & l::Send,{Blind}{Right}
vk1C & u::Send,{Blind}{Home}
vk1C & o::Send,{Blind}{End}
vk1C & p::Send,{Blind}{F2}
vk1C & 1::Send,{Blind}^+6
vk1C & 2::Send,{Blind}^+2
vk1C & n::Run, mspaint.exe
vk1C & m::Run, Notepads
vk1C & t::InsertDateTime("yyyy/MM/dd (ddd) HH:mm ")

; ==========================================================
; ----- Alt -----
; ==========================================================
!w::Send, !{F4}
^!c::ReplaceEscapeToSlash()
^!n::OpenWithMspaint()
^!m::OpenWithNotePad()

; ==========================================================
; ----- Window-key -----
; ==========================================================
#q::Send {LWin Down}{Ctrl Down}{Left}{LWin Up}{Ctrl Up}
#w::Send {LWin Down}{Ctrl Down}{Right}{LWin Up}{Ctrl Up}
^#b::GetActiveWindowPos()
^#e::GetApplicationName()
^#1::MoveWindow("A", 1930,  430, 1380,  980)
^#2::MoveWindow("A", 1930,  450, 1550, 1600)
^#3::MoveWindow("A",    0,  470, 3840, 1620)
^#4::MoveWindow("A", 1930,  500, 1750, 1550)
^+#1::MoveWindow("A",   10,  430, 1380,  980)
^+#2::MoveWindow("A",   10,  450, 1550, 1600)
^+#4::MoveWindow("A",   10,  500, 1750, 1550)
^#F11::OpenMoveExplorer(profilePath . "\Downloads", 700, 0, 1230, 2100)
^#F12::OpenVSCode()
^+#F12::Reload

; ==========================================================
; ----- Function-Key (for Mouse) -----
; ==========================================================
F13::XButton1   ; 戻る（手前側）
F14::XButton2   ; 進む（　奥側）
F15::Send ^v   ; 　　（手前側）
F16::Send ^c   ; 　　（　奥側）
F17::Send ^w
F13 & F17::SendInput {Media_Play_Pause}
F15 & F17::Send !{F4}
F13 & WheelUp::Send, {Volume_Up}    ; 音量アップ
F13 & WheelDown::Send, {Volume_Down} ; 音量ダウン
F15 & WheelUp::Send, {WheelLeft}   ; F13 + 上スクロール → 左へ
F15 & WheelDown::Send, {WheelRight} ; F13 + 下スクロール → 右へ

; ==========================================================
; ----- Others -----
; ==========================================================
Shift & Backspace::Send,{Del}
scrolllock::Return
$sc073::Send, +{sc073}  ; \ → _
$+sc073::Send, {sc073}  ; _ → \

; ==========================================================
; ----- Browser -----
; ==========================================================
; SetTitleMatchMode, 2
; #IfWinActive, vClock.jp
;     F1::vClockFullScreen()
; ; F2::TestUIA()
; #IfWinActive

; #IfWinActive ahk_group BrowserGroup
;     ^sc073::TogglePDFZoom()
; #IfWinActive

#IfWinActive ahk_group BrowserGroup
    ^sc073::TogglePDFZoom()
    F1::RunSiteSpecificKey("{F1}", KeyActions["F1"])
    F2::RunSiteSpecificKey("{F2}", KeyActions["F2"])
    ; F3::get_auth_debug()
; F3::ScrollToEdge("Up")
; F6::ScrollToEdge("Down")
#IfWinActive

; ==========================================================
; ----- Power Point -----
; ==========================================================
#IfWinActive, ahk_exe POWERPNT.EXE
    ^!l::SetRight()
    ^!j::SetLeft()
    ^!i::SetTop()
    ^!k::SetBottom()
    ^!g::GroupSet()
    ^!h::GroupRelease()
    ^!u::SetHorizontalCenter()
    ^!o::SetVerticalCenter()
    ^!m::SetHorizontalSpacer()
    ^!.::SetVerticalSpace()
    ^+!g::SetFront()
    ^+!h::SetBack()
    !2::SetFrameLine()
    !3::SetFrameSize()
    !4::OpenFormatObject()
#IfWinActive

; ==========================================================
; ----- Excel -----
; ==========================================================
#IfWinActive, ahk_exe EXCEL.EXE
    ^Tab::Send ^{PgDn}
    ^+Tab::Send ^{PgUp}
#IfWinActive

; ==========================================================
; ----- Mouse Gesture -----
; ==========================================================
#If MouseIsOverTarget()
    RButton::
        MouseGetPos, , , startWinID
        gesture := MG_RecognizeGesture()
        MG_ExecuteAction(gesture, startWinID)
    return
#If (MG_IsActive && MouseIsOverTarget())
    WheelUp::MG_ScrollAction("Up")
    WheelDown::MG_ScrollAction("Down")
#If
#If
