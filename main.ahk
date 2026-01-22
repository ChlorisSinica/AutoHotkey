#NoEnv
#SingleInstance, Force
SetWorkingDir %A_ScriptDir%
CoordMode, Mouse, Screen
SetBatchLines, -1

; from [https://github.com/Descolada/UIAutomation]
#Include %A_ScriptDir%\Plugins\UIA_Interface.ahk
#Include %A_ScriptDir%\Plugins\UIA_Browser.ahk
; --- Pluginsファイルの読み込み ---
#Include %A_ScriptDir%\Plugins\UIA_Utils.ahk
#Include %A_ScriptDir%\Plugins\Application.ahk
#Include %A_ScriptDir%\Plugins\Browser.ahk
#Include %A_ScriptDir%\Plugins\GestureMap.ahk
#Include %A_ScriptDir%\Plugins\Hotstring.ahk
#Include %A_ScriptDir%\Plugins\MouseCursor.ahk
#Include %A_ScriptDir%\Plugins\MouseGesture.ahk
#Include %A_ScriptDir%\Plugins\PowerPoint.ahk
#Include %A_ScriptDir%\Plugins\IndicatorManager.ahk
#Include %A_ScriptDir%\Plugins\TextEditor.ahk
#Include %A_ScriptDir%\Plugins\GetAuth.ahk
#Include %A_ScriptDir%\Plugins\WindowManager.ahk

; --- 初期化処理 ---
DllCall("SetThreadDpiAwarenessContext", "ptr", -4)
EnvGet, profilePath, USERPROFILE

Indicator_Init()
TrayTip, AutoHotkey, Script Reloaded, 2 ;

; ==========================================================
; ----- Indicator用変数 -----
; ==========================================================
global EnableNavLayer   := 1
global EnableWinMgr     := 1
global EnableMouseExt   := 1
global EnableAppSpec    := 1
global EnableMouseEmu   := 1
global EnableGestures   := 1
vk1C & F1::Settings_Open()
#If WinActive("機能のON/OFF設定")
    Escape::Settings_Close()
#If

; ==========================================================
; ----- vk1C(Non-Convert) -----
; ==========================================================
#If (EnableNavLayer)
    vk1C & j::Send,{Blind}{Left}
    vk1C & k::Send,{Blind}{Down}
    vk1C & i::Send,{Blind}{Up}
    vk1C & l::Send,{Blind}{Right}
    vk1C & u::Send,{Blind}{Home}
    vk1C & o::Send,{Blind}{End}
    vk1C & p::Send,{Blind}{F2}
    vk1C & 1::Send,{Blind}^+6
    vk1C & 2::Send,{Blind}^+2
    vk1C & n::OpenWithMspaint(0)
    vk1C & m::OpenWithNotePad(0, SettingsUI.EditorType)
    vk1C & t::InsertDateTime("yyyy/MM/dd (ddd) HH:mm ")
#If
#If (EnableMouseEmu)
    vk1C & e::StartCursorMove()
    vk1C & s::StartCursorMove()
    vk1C & d::StartCursorMove()
    vk1C & f::StartCursorMove()
    vk1C & w::Click, Down
    vk1C & r::Click, Right, Down
    vk1C & w Up::Click, Up
    vk1C & r Up::Click, Right, Up
#If

; ==========================================================
; ----- Alt -----
; ==========================================================
!w::Send, !{F4}
^!c::ReplaceEscapeToSlash()
^!n::OpenWithMspaint(1)
^!m::OpenWithNotePad(1, SettingsUI.EditorType)

; ==========================================================
; ----- Window-key -----
; ==========================================================
#If (EnableWinMgr)
    #q::Send {LWin Down}{Ctrl Down}{Left}{LWin Up}{Ctrl Up}
    #w::Send {LWin Down}{Ctrl Down}{Right}{LWin Up}{Ctrl Up}
    ^#b::GetActiveWindowPos()
    ^#e::GetApplicationName()
    ; ^#F1::OpenvClockFullScreen()
    ^#1::MoveWindowRatio("A", 0.503, 0.206, 0.360, 0.470)
    ^#2::MoveWindowRatio("A", 0.503, 0.216, 0.404, 0.766)
    ^#3::MoveWindowRatio("A", 0.000, 0.225, 1.000, 0.775)
    ^#4::MoveWindowRatio("A", 0.503, 0.240, 0.456, 0.742)
    ^+#1::MoveWindowRatio("A", 0.003, 0.206, 0.360, 0.470)
    ^+#2::MoveWindowRatio("A", 0.003, 0.216, 0.404, 0.766)
    ^+#4::MoveWindowRatio("A", 0.003, 0.240, 0.456, 0.742)
    ^#F11::OpenMoveExplorer(profilePath . "\Downloads", 0.180, 0.000, 0.320, 1.000)
    ^#F12::OpenVSCode()
    ^+#F12::Reload
#If

; ==========================================================
; ----- Function-Key (for Mouse) -----
; ==========================================================
#If (EnableMouseExt)
    XButton1::XButton1  ; 戻る（手前側）
    XButton2::XButton2  ; 進む（　奥側）
    F15::Send ^v        ; 　　（手前側）
    F16::Send ^c        ; 　　（　奥側）
    F17::Send ^w        ; タブを閉じる
    F15 & F17::SendInput {Media_Play_Pause}     ;
    XButton2 & F17::Send !{F4}                  ;
    XButton1 & WheelUp::Send, {WheelLeft}       ; F13 + 上スクロール → 左へ
    XButton1 & WheelDown::Send, {WheelRight}    ; F13 + 下スクロール → 右へ
    XButton2 & WheelUp::Send ^{NumpadAdd}       ; ウィンドウ拡大
    XButton2 & WheelDown::Send ^{NumpadSub}     ; ウィンドウ縮小
    F15 & WheelUp::Send, {Volume_Up}            ; 音量アップ
    F15 & WheelDown::Send, {Volume_Down}        ; 音量ダウン
    F16 & WheelDown::AltTabAction("Next")
    F16 & WheelUp::AltTabAction("Prev")
    *F16 Up::CloseAltTabMenu()
#If

; ==========================================================
; ----- Others -----
; ==========================================================
Shift & Backspace::Send,{Del}
scrolllock::Return
$sc073::Send, +{sc073}  ; \ → _
$+sc073::Send, {sc073}  ; _ → \
vk1C & z::Manage_N_Hold("Toggle")
vk1C & x::Manage_N_Hold("Off")

; ==========================================================
; ----- Browser -----
; 「アプリ設定がON」かつ「ブラウザグループがアクティブ」
; ==========================================================
#If (EnableAppSpec && WinActive("ahk_group BrowserGroup"))
    ^sc073::TogglePDFZoom()
    ; F2::CheckFocus()
    ; F2::InspectElementUnderMouse()
    F1::RunSiteSpecificKey("{F1}", KeyActions["F1"])
    F2::RunSiteSpecificKey("{F2}", KeyActions["F2"])
    !c::CopyPlaneURL()
#If

; ==========================================================
; ----- Power Point -----
; 「アプリ設定がON」かつ「パワポがアクティブ」
; ==========================================================
#If (EnableAppSpec && WinActive("ahk_exe POWERPNT.EXE"))
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
#If

; ==========================================================
; ----- Excel -----
; 「アプリ設定がON」かつ「エクセルがアクティブ」
; ==========================================================
#If (EnableAppSpec && WinActive("ahk_exe EXCEL.EXE"))
    ^Tab::Send ^{PgDn}
    ^+Tab::Send ^{PgUp}
#If

; ==========================================================
; ----- Mouse Gesture -----
; ==========================================================
#If (EnableGestures&& MouseIsOverTarget())
    RButton::
        MouseGetPos, , , startWinID
        gesture := MG_RecognizeGesture()
        MG_ExecuteAction(gesture, startWinID)
    return
#If

#If (EnableGestures && MG_IsActive && MouseIsOverTarget())
    WheelUp::MG_ScrollAction("Up")
    WheelDown::MG_ScrollAction("Down")
#If