global KeyActions := {}
KeyActions["F1"] := {}
KeyActions["F2"] := {}
KeyActions["F1"]["x.com"]             := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["youtube.com"]       := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["instagram.com"]     := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["music.youtube.com"] := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["supjav.com"]        := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["abema.tv"]          := Func("SaveCookiesCurrentSite")
global Browser_PDFZoomDebugEnabled    := false
global Browser_PDFZoomDebugLogDir     := A_ScriptDir . "\.claude"
global Browser_PDFZoomDebugLogPath    := Browser_PDFZoomDebugLogDir . "\pdf_zoom_debug.log"
global Browser_PDFZoomDebugMaxBytes   := 262144
global Browser_PDFZoomTryShortcutFirst := false
global Browser_PDFZoomNativeShortcutSpec := "vkDDsc02B"
global Browser_PDFZoomNativeShortcutLabel := "Ctrl+vkDDsc02B"
global Browser_URLExportPath          := "C:\myApp\__temp__\urls.txt"

; ==========================================================
; ホットキー定義 (ブラウザがアクティブな時のみ有効)
; ==========================================================
ShowBrowserURLType()
{
    CurrentURL := GetBrowserURL()           ; 1. URLを取得
    if (CurrentURL = "")                    ; 取得失敗時は中断
        return
    PageType := GetUrlType(CurrentURL)      ; 2. URLの種類を判定
    CheckUrlType(PageType, CurrentURL)      ; 3. 結果を表示
}

; ==========================================================
; 関数: ブラウザのURL取得
; ==========================================================
GetBrowserURL() {
    try {
        cUIA := new UIA_Browser("A")        ; アクティブウィンドウを対象にUIA初期化
        currentUrl := cUIA.GetCurrentURL()  ; アドレスバーまたはドキュメント要素からURL取得

        if (currentUrl != "") {
            return currentUrl
        } else {
            MsgBox, URLを取得できませんでした。 ; 取得失敗時のメッセージ
            return ""
        }
    } catch e {
        MsgBox, エラーが発生しました。`n詳細: %e%
        return ""
    }
}

CopyPlaneURL() {
    ClipSaved := ClipboardAll
    Clipboard := ""
    Send, ^c
    ClipWait, 0.5
    if ErrorLevel
    {
        ClipboardWrite(ClipSaved)
        return
    }

    ; 変数経由で書き戻すことで、HTML情報を削除してテキストのみにする
    UrlText := Clipboard
    Clipboard := ""
    ClipboardWrite(UrlText)

    ClipSaved := ""
}

Browser_DebugInit() {
    global Browser_PDFZoomDebugEnabled, Browser_PDFZoomDebugLogPath, Browser_PDFZoomDebugMaxBytes

    Debug_CreateChannel("BrowserPDF", Browser_PDFZoomDebugLogPath, Browser_PDFZoomDebugMaxBytes, Browser_PDFZoomDebugEnabled)
}

Browser_DebugSanitize(text) {
    return Debug_Sanitize(text)
}

Browser_PDFZoomLog(event, extra := "") {
    Debug_Log("BrowserPDF", event, extra)
}

Browser_LogCtrlSc073Probe() {
    global Browser_PDFZoomDebugEnabled

    if (!Browser_PDFZoomDebugEnabled)
        return

    thisHotkey := Browser_DebugSanitize(A_ThisHotkey)
    priorHotkey := Browser_DebugSanitize(A_PriorHotkey)
    ctrlState := GetKeyState("Ctrl", "P") ? 1 : 0
    shiftState := GetKeyState("Shift", "P") ? 1 : 0
    browserActive := WinActive("ahk_group BrowserGroup") ? 1 : 0
    activeHwnd := WinExist("A")

    if (!activeHwnd) {
        Browser_PDFZoomLog("pdf_zoom_hotkey_probe"
            , "thisHotkey=" . thisHotkey
            . " priorHotkey=" . priorHotkey
            . " timeSincePrior=" . A_TimeSincePriorHotkey
            . " ctrl=" . ctrlState
            . " shift=" . shiftState
            . " browserActive=" . browserActive
            . " active=missing")
        return
    }

    pdfInfo := Browser_GetPDFContextInfo(activeHwnd, cBrowser)
    Browser_PDFZoomLog("pdf_zoom_hotkey_probe"
        , "thisHotkey=" . thisHotkey
        . " priorHotkey=" . priorHotkey
        . " timeSincePrior=" . A_TimeSincePriorHotkey
        . " ctrl=" . ctrlState
        . " shift=" . shiftState
        . " browserActive=" . browserActive
        . " state=" . pdfInfo.State
        . " reasons=" . pdfInfo.Reasons
        . " exe=" . pdfInfo.Exe
        . " class=" . pdfInfo.Class
        . " title=" . pdfInfo.Title
        . " url=" . pdfInfo.Url
        . " zoomButton=" . pdfInfo.ZoomButton
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd)
        . (pdfInfo.Error != "" ? " error=" . pdfInfo.Error : ""))
}

Browser_IsPdfUrl(url) {
    if (url = "")
        return false
    return RegExMatch(url, "i)\.pdf(?:$|[?#&])")
}

Browser_IsPdfTitle(title) {
    if (title = "")
        return false
    return RegExMatch(title, "i)\.pdf(?:$|\s| - )")
}

Browser_AppendReason(ByRef reasonText, reason) {
    if (reason = "")
        return

    if (reasonText = "") {
        reasonText := reason
        return
    }

    if !InStr("|" . reasonText . "|", "|" . reason . "|")
        reasonText .= "|" . reason
}

Browser_GetFocusedElementSummary() {
    global Browser_PDFZoomDebugEnabled

    if (!Browser_PDFZoomDebugEnabled)
        return ""

    try {
        UIA := UIA_Interface()
        focusedEl := UIA.GetFocusedElement()
        summary := "name=" . Browser_DebugSanitize(focusedEl.CurrentName)
        summary .= " type=" . Browser_DebugSanitize(focusedEl.CurrentLocalizedControlType)
        summary .= " aid=" . Browser_DebugSanitize(focusedEl.CurrentAutomationId)
        summary .= " class=" . Browser_DebugSanitize(focusedEl.CurrentClassName)
        return summary
    }

    return "unavailable"
}

Browser_GetFocusedControlSummary(activeHwnd) {
    global Browser_PDFZoomDebugEnabled

    if (!Browser_PDFZoomDebugEnabled)
        return ""

    ControlGetFocus, focusedCtl, ahk_id %activeHwnd%
    WinGet, controlList, ControlList, ahk_id %activeHwnd%

    preferredCtl := ""
    for _, ctl in StrSplit(controlList, "`n", "`r") {
        if (ctl = "")
            continue
        if RegExMatch(ctl, "i)^Chrome_RenderWidgetHostHWND") {
            preferredCtl := ctl
            break
        }
        if (preferredCtl = "" && RegExMatch(ctl, "i)^Intermediate D3D Window"))
            preferredCtl := ctl
        else if (preferredCtl = "" && RegExMatch(ctl, "i)^Chrome_WidgetWin"))
            preferredCtl := ctl
    }

    summary := "focusedCtl=" . Browser_DebugSanitize(focusedCtl)
    if (preferredCtl != "")
        summary .= " preferredCtl=" . Browser_DebugSanitize(preferredCtl)
    return summary
}

Browser_FocusBrowserControl(activeHwnd, ByRef focusMethod := "") {
    WinGet, controlList, ControlList, ahk_id %activeHwnd%

    targetCtl := ""
    for _, ctl in StrSplit(controlList, "`n", "`r") {
        if (ctl = "")
            continue
        if RegExMatch(ctl, "i)^Chrome_RenderWidgetHostHWND") {
            targetCtl := ctl
            break
        }
        if (targetCtl = "" && RegExMatch(ctl, "i)^Intermediate D3D Window"))
            targetCtl := ctl
        else if (targetCtl = "" && RegExMatch(ctl, "i)^Chrome_WidgetWin"))
            targetCtl := ctl
    }

    if (targetCtl = "") {
        Browser_LogPDFFocusTrace(activeHwnd, "BrowserControlFocus", "fail", "target=missing")
        return false
    }

    Browser_LogPDFFocusTrace(activeHwnd, "BrowserControlFocus", "attempt", "target=" . targetCtl)
    ControlFocus, %targetCtl%, ahk_id %activeHwnd%
    Sleep, 40
    ControlGetFocus, focusedCtl, ahk_id %activeHwnd%
    if (focusedCtl = targetCtl) {
        focusMethod := "ControlFocus:" . targetCtl
        Browser_LogPDFFocusTrace(activeHwnd, "BrowserControlFocus", "success", focusMethod)
        return true
    }

    Browser_LogPDFFocusTrace(activeHwnd, "BrowserControlFocus", "fail"
        , "target=" . targetCtl . " focusedCtl=" . focusedCtl)
    return false
}

Browser_ScreenToClient(hwnd, screenX, screenY) {
    VarSetCapacity(pt, 8, 0)
    NumPut(screenX, pt, 0, "Int")
    NumPut(screenY, pt, 4, "Int")

    if !DllCall("ScreenToClient", "Ptr", hwnd, "Ptr", &pt)
        return ""

    return {x: NumGet(pt, 0, "Int"), y: NumGet(pt, 4, "Int")}
}

Browser_DescribeElement(el) {
    if (!el)
        return "missing"

    name := ""
    type := ""
    aid := ""
    className := ""
    focusable := "?"
    hasFocus := "?"

    try name := el.CurrentName
    try type := el.CurrentLocalizedControlType
    try aid := el.CurrentAutomationId
    try className := el.CurrentClassName
    try focusable := el.CurrentIsKeyboardFocusable
    try hasFocus := el.CurrentHasKeyboardFocus

    return "name=" . Browser_DebugSanitize(name)
        . " type=" . Browser_DebugSanitize(type)
        . " aid=" . Browser_DebugSanitize(aid)
        . " class=" . Browser_DebugSanitize(className)
        . " focusable=" . focusable
        . " hasFocus=" . hasFocus
}

Browser_IsPDFToolbarElement(el) {
    if (!el)
        return false

    aid := ""
    name := ""
    type := ""

    try aid := el.CurrentAutomationId
    try name := el.CurrentName
    try type := el.CurrentLocalizedControlType

    if (aid = "pagefit" || aid = "fit-to-width" || aid = "widthfit")
        return true

    if (type = "ボタン" || type = "button") {
        if InStr(name, "ページに合わせる")
            return true
        if InStr(name, "幅に合わせる")
            return true
        if InStr(name, "Fit to page")
            return true
        if InStr(name, "Fit to width")
            return true
    }

    return false
}

Browser_TrySetUIAAutoSetFocus(uia, enabled, ByRef previousValue := "", ByRef detail := "") {
    if !IsObject(uia) {
        detail := "AutoSetFocus=uia_missing"
        return false
    }

    try {
        previousValue := uia.AutoSetFocus
        uia.AutoSetFocus := enabled ? 1 : 0
        detail := "AutoSetFocus=" . previousValue . "->" . (enabled ? 1 : 0)
        return true
    } catch e {
        detail := "AutoSetFocus=unsupported error=" . Browser_DebugSanitize(e)
        return false
    }
}

Browser_RestoreUIAAutoSetFocus(uia, previousValue, ByRef detail := "") {
    if !IsObject(uia) {
        detail := "AutoSetFocusRestore=uia_missing"
        return false
    }

    try {
        uia.AutoSetFocus := previousValue
        detail := "AutoSetFocusRestore=" . previousValue
        return true
    } catch e {
        detail := "AutoSetFocusRestore=failed error=" . Browser_DebugSanitize(e)
        return false
    }
}

Browser_AddPDFFocusCandidate(ByRef candidates, label, el) {
    if (!el)
        return

    candidates.Push({Label: label, Element: el, Summary: Browser_DescribeElement(el)})
}

Browser_DescribePDFFocusCandidates(candidates) {
    text := ""

    for _, candidate in candidates {
        if (text != "")
            text .= " || "
        text .= candidate.Label . ":" . candidate.Summary
    }

    return (text != "") ? text : "none"
}

Browser_LogPDFFocusTrace(activeHwnd, step, result, detail := "") {
    text := "step=" . Browser_DebugSanitize(step)
        . " result=" . Browser_DebugSanitize(result)
    if (detail != "")
        text .= " detail=" . Browser_DebugSanitize(detail)

    if (activeHwnd) {
        focusedSummary := Browser_GetFocusedElementSummary()
        controlSummary := Browser_GetFocusedControlSummary(activeHwnd)
        if (focusedSummary != "")
            text .= " focus=" . focusedSummary
        if (controlSummary != "")
            text .= " " . controlSummary
    }

    Browser_PDFZoomLog("pdf_zoom_focus_trace", text)
}

Browser_ShouldRestorePDFFocus() {
    try {
        UIA := UIA_Interface()
        focusedEl := UIA.GetFocusedElement()
        focusedAid := focusedEl.CurrentAutomationId
        focusedType := focusedEl.CurrentControlType

        if (focusedAid = "RootWebArea")
            return false
        if (focusedType = UIA_Enum.UIA_DocumentControlTypeId)
            return false
    }

    return true
}

Browser_FocusWebContentPane(activeHwnd, ByRef focusMethod := "") {
    WinActivate, ahk_id %activeHwnd%
    WinWaitActive, ahk_id %activeHwnd%, , 1

    Browser_LogPDFFocusTrace(activeHwnd, "WebContentCtrlF6", "attempt")
    Send, ^{F6}
    Sleep, 40
    focusMethod := "Ctrl+F6"
    Browser_PDFZoomLog("pdf_zoom_focus_web_content"
        , "step=" . focusMethod
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd))

    if !Browser_ShouldRestorePDFFocus() {
        Browser_LogPDFFocusTrace(activeHwnd, "WebContentCtrlF6", "ready", focusMethod)
        return true
    }

    Browser_LogPDFFocusTrace(activeHwnd, "WebContentEscCtrlF6", "attempt", focusMethod)
    SendInput, {Esc}
    Sleep, 20
    Send, ^{F6}
    Sleep, 40
    focusMethod := "Esc + Ctrl+F6"
    Browser_PDFZoomLog("pdf_zoom_focus_web_content"
        , "step=" . focusMethod
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd))

    focusReady := !Browser_ShouldRestorePDFFocus()
    Browser_LogPDFFocusTrace(activeHwnd, "WebContentEscCtrlF6"
        , focusReady ? "ready" : "continue"
        , focusMethod)
    return focusReady
}

Browser_TryRefocusViaMousePoint(activeHwnd, ByRef focusMethod := "") {
    MouseGetPos, mouseX, mouseY, mouseHwnd
    if (mouseHwnd != activeHwnd) {
        focusMethod := "mouse_outside_active_window"
        Browser_LogPDFFocusTrace(activeHwnd, "MousePointControlClick", "fail", focusMethod)
        return false
    }

    mouseElSummary := "unavailable"
    try {
        UIA := UIA_Interface()
        mouseEl := UIA.ElementFromPoint(mouseX, mouseY)
        mouseElSummary := Browser_DescribeElement(mouseEl)
        if Browser_IsPDFToolbarElement(mouseEl) {
            focusMethod := "mouse_over_toolbar " . mouseElSummary
            Browser_LogPDFFocusTrace(activeHwnd, "MousePointControlClick", "fail", focusMethod)
            return false
        }
    }

    clientPt := Browser_ScreenToClient(activeHwnd, mouseX, mouseY)
    if !IsObject(clientPt) {
        focusMethod := "screen_to_client_failed"
        Browser_LogPDFFocusTrace(activeHwnd, "MousePointControlClick", "fail", focusMethod)
        return false
    }

    clickPos := "X" . clientPt.x . " Y" . clientPt.y
    Browser_LogPDFFocusTrace(activeHwnd, "MousePointControlClick", "attempt"
        , "x=" . clientPt.x . " y=" . clientPt.y)
    ControlClick, %clickPos%, ahk_id %activeHwnd%,, Left, 1, NA
    Sleep, 30
    focusMethod := "ControlClickCurrentMousePoint x=" . clientPt.x . " y=" . clientPt.y
        . " mouseEl=" . mouseElSummary
    Browser_LogPDFFocusTrace(activeHwnd, "MousePointControlClick", "success", focusMethod)
    return true
}

Browser_GetPDFDocumentElement(cBrowser) {
    if !IsObject(cBrowser)
        return ""

    try {
        docEl := cBrowser.GetCurrentDocumentElement()
        if (docEl)
            return docEl
    }

    try {
        rootWebArea := cBrowser.BrowserElement.FindFirstBy("AutomationId=RootWebArea")
        if (rootWebArea)
            return rootWebArea
    }

    try {
        genericDoc := cBrowser.BrowserElement.FindFirstBy("ControlType=Document")
        if (genericDoc)
            return genericDoc
    }

    return ""
}

Browser_GetPDFDocumentPoint(cBrowser, relativeTo := "window") {
    docEl := Browser_GetPDFDocumentElement(cBrowser)
    if (!docEl)
        return ""

    try pos := docEl.GetCurrentPos(relativeTo)
    if !IsObject(pos)
        return ""

    ; 中央寄りだとリンク等を踏む可能性があるので、左寄り・やや上寄りの安全側を狙う
    clickX := pos.x + Round(pos.w * 0.18)
    clickY := pos.y + Round(pos.h * 0.22)

    if (clickX < pos.x + 12)
        clickX := pos.x + 12
    if (clickY < pos.y + 12)
        clickY := pos.y + 12

    return {x: clickX, y: clickY, w: pos.w, h: pos.h}
}

Browser_TryRefocusViaDocumentControlClick(activeHwnd, cBrowser, ByRef focusMethod := "") {
    clickPt := Browser_GetPDFDocumentPoint(cBrowser, "window")
    if !IsObject(clickPt) {
        focusMethod := "document_control_click=no_point"
        Browser_LogPDFFocusTrace(activeHwnd, "DocumentControlClick", "fail", focusMethod)
        return false
    }

    clickPos := "X" . clickPt.x . " Y" . clickPt.y
    Browser_LogPDFFocusTrace(activeHwnd, "DocumentControlClick", "attempt"
        , "x=" . clickPt.x . " y=" . clickPt.y)
    ControlClick, %clickPos%, ahk_id %activeHwnd%,, Left, 1, NA
    Sleep, 40
    focusMethod := "ControlClickDocumentPoint x=" . clickPt.x . " y=" . clickPt.y
    Browser_PDFZoomLog("pdf_zoom_focus_doc_click"
        , "step=" . focusMethod
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd))
    Browser_LogPDFFocusTrace(activeHwnd, "DocumentControlClick", "success", focusMethod)
    return true
}

Browser_TryRefocusViaDocumentPhysicalClick(activeHwnd, cBrowser, ByRef focusMethod := "") {
    clickPt := Browser_GetPDFDocumentPoint(cBrowser, "screen")
    if !IsObject(clickPt) {
        focusMethod := "document_physical_click=no_point"
        Browser_LogPDFFocusTrace(activeHwnd, "DocumentPhysicalClick", "fail", focusMethod)
        return false
    }

    Browser_LogPDFFocusTrace(activeHwnd, "DocumentPhysicalClick", "attempt"
        , "x=" . clickPt.x . " y=" . clickPt.y)
    MouseGetPos, origX, origY
    MouseMove, % clickPt.x, % clickPt.y, 0
    Sleep, 10
    MouseClick, Left, % clickPt.x, % clickPt.y, 1, 0
    Sleep, 20
    MouseMove, % origX, % origY, 0
    Sleep, 20

    focusMethod := "PhysicalClickDocumentPoint x=" . clickPt.x . " y=" . clickPt.y
    Browser_PDFZoomLog("pdf_zoom_focus_doc_click"
        , "step=" . focusMethod
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd))
    Browser_LogPDFFocusTrace(activeHwnd, "DocumentPhysicalClick", "success", focusMethod)
    return true
}

; ==========================================================
; 関数: URLタイプの判定
; ==========================================================
GetUrlType(targetUrl)
{
    ; 1. 新しいタブ (ntp.msn.com, newtab, about:blank)
    If InStr(targetUrl, "ntp.msn.com") || InStr(targetUrl, "newtab") || (targetUrl = "about:blank")
        Return "NewTab"                     ; 新しいタブと判定

    ; 2. ローカルファイル (file: または ドライブレター)
    Else If (SubStr(targetUrl, 1, 5) = "file:") || RegExMatch(targetUrl, "^[a-zA-Z]:")
        Return "File"                       ; ローカルファイルと判定

    ; 3. 一般的なWebページ (http/https)
    Else If (SubStr(targetUrl, 1, 4) = "http")
        Return "Web"                        ; Webサイトと判定

    ; 4. その他
    Else
        Return "Other"                      ; その他（設定画面など）
}

; ==========================================================
; 関数: 結果の表示
; ==========================================================
CheckUrlType(PageType, originalUrl) {
    If (PageType = "NewTab")
        MsgBox, 新しいタブです。何もしません。
    Else If (PageType = "File")
        MsgBox, ローカルファイルを開いています。`nパス: %originalUrl%
    Else If (PageType = "Web")
        MsgBox, 通常のWebサイトです。`nURL: %originalUrl%
    Else
        MsgBox, その他の画面（設定など）です。`nURL: %originalUrl%
}

; ==========================================================
; 関数: vClock.jp で全画面表示するだけ (F11とは異なる)
; ==========================================================
vClockFullScreen(cBrowser) {
    if (btn := cBrowser.FindFirst("AutomationId=btn-full-screen"))
        btn.Click()
}

; OpenvClockFullScreen() {
;     OpenEdgeMaximized("vclock.jp")
;     cBrowser := new UIA_Browser("A")
;     vClockFullScreen(cBrowser)
; }

; ==========================================================
; 関数: 幅に合わせる ⇔ ページに合わせる の切り替え
; ==========================================================
Browser_GetPDFContextInfo(activeHwnd, ByRef cBrowser := "") {
    info := {State: 0, Exe: "", Class: "", Title: "", Url: "", Reasons: "", Error: "", ZoomButton: ""}
    reasons := ""

    WinGet, exeName, ProcessName, ahk_id %activeHwnd%
    WinGetClass, winClass, ahk_id %activeHwnd%
    WinGetTitle, winTitle, ahk_id %activeHwnd%
    info.Exe   := exeName
    info.Class := winClass
    info.Title := winTitle

    if Browser_IsPdfTitle(winTitle)
        Browser_AppendReason(reasons, "title")

    try cBrowser := new UIA_Browser("ahk_id " . activeHwnd)
    catch e {
        info.Error := Browser_DebugSanitize(e)
        info.Reasons := reasons
        info.State := (reasons != "") ? 1 : 0
        return info
    }

    try {
        currentUrl := cBrowser.GetCurrentURL()
        info.Url := currentUrl
        if Browser_IsPdfUrl(currentUrl)
            Browser_AppendReason(reasons, "url")
    } catch e {
        info.Error := Browser_DebugSanitize(e)
    }

    for _, id in ["pagefit", "fit-to-width", "widthfit"] {
        try {
            if (cBrowser.BrowserElement.FindFirstBy("AutomationId=" . id)) {
                Browser_AppendReason(reasons, "aid:" . id)
                break
            }
        }
    }

    try {
        if Browser_FindPDFZoomButton(cBrowser, matchLabel) {
            info.ZoomButton := matchLabel
            Browser_AppendReason(reasons, "button")
        }
    }

    info.Reasons := reasons
    info.State := (reasons != "") ? 1 : 0
    return info
}

Browser_GetPDFContextState(activeHwnd) {
    info := Browser_GetPDFContextInfo(activeHwnd)
    return info.State
}

Browser_FindPDFZoomButton(cBrowser, ByRef matchLabel := "") {
    for _, id in ["pagefit", "fit-to-width", "widthfit"] {
        try {
            btn := cBrowser.BrowserElement.FindFirstBy("AutomationId=" . id)
            if (btn) {
                matchLabel := "AutomationId=" . id
                return btn
            }
        }
    }

    for _, name in ["ページに合わせる (Ctrl+\)", "幅に合わせる (Ctrl+\)"
        , "ページに合わせる", "幅に合わせる"
        , "Fit to page (Ctrl+\)", "Fit to width (Ctrl+\)"
        , "Fit to page", "Fit to width"] {
        try {
            btn := cBrowser.BrowserElement.FindFirstBy("Name=" . name)
            if (btn) {
                matchLabel := "Name=" . name
                return btn
            }
        }
    }

    return ""
}

Browser_DescribePDFZoomButton(cBrowser) {
    btn := Browser_FindPDFZoomButton(cBrowser, matchLabel)
    if (!btn)
        return "missing"

    buttonName := ""
    buttonId := ""
    buttonHelp := ""
    try buttonName := btn.CurrentName
    try buttonId := btn.CurrentAutomationId
    try buttonHelp := btn.CurrentHelpText

    return "match=" . Browser_DebugSanitize(matchLabel)
        . " aid=" . Browser_DebugSanitize(buttonId)
        . " name=" . Browser_DebugSanitize(buttonName)
        . (buttonHelp != "" ? " help=" . Browser_DebugSanitize(buttonHelp) : "")
}

Browser_SendPDFZoomNativeShortcut() {
    global Browser_PDFZoomNativeShortcutSpec

    sendSpec := "{Blind}^{" . Browser_PDFZoomNativeShortcutSpec . "}"
    SendInput, %sendSpec%
}

Browser_TogglePDFZoomViaShortcut(cBrowser, ByRef detail := "", preButtonState := "") {
    global Browser_PDFZoomNativeShortcutLabel

    if !IsObject(cBrowser) {
        detail := "shortcut=no_browser"
        return false
    }

    if (preButtonState = "")
        preButtonState := Browser_DescribePDFZoomButton(cBrowser)

    if (preButtonState = "missing") {
        detail := "shortcut=" . Browser_PDFZoomNativeShortcutLabel . " preButton=missing"
        return false
    }

    Browser_SendPDFZoomNativeShortcut()
    postButtonState := preButtonState
    Loop, 8 {
        Sleep, 20
        postButtonState := Browser_DescribePDFZoomButton(cBrowser)
        if (postButtonState != "missing" && preButtonState != postButtonState)
            break
    }

    detail := "shortcut=" . Browser_PDFZoomNativeShortcutLabel
        . " preButton=" . preButtonState
        . " postButton=" . postButtonState

    if (postButtonState != "missing" && preButtonState != postButtonState)
        return true

    return false
}

Browser_TogglePDFZoomViaButton(cBrowser, ByRef detail := "") {
    btn := Browser_FindPDFZoomButton(cBrowser, matchLabel)
    if (!btn) {
        detail := "button_not_found"
        return false
    }

    autoFocusChanged := Browser_TrySetUIAAutoSetFocus(cBrowser.UIA, false, autoFocusPrevious, autoFocusDetail)
    actionDetail := ""
    success := false

    try {
        btn.Click()
        actionDetail := matchLabel . " via=Click"
        success := true
    } catch e {
        Browser_PDFZoomLog("pdf_zoom_button_click_failed", matchLabel . " error=" . Browser_DebugSanitize(e))
    }

    if (!success) {
        try {
            btn.Invoke()
            actionDetail := matchLabel . " via=Invoke"
            success := true
        } catch e {
            Browser_PDFZoomLog("pdf_zoom_button_invoke_failed", matchLabel . " error=" . Browser_DebugSanitize(e))
        }
    }

    if (autoFocusChanged) {
        Browser_RestoreUIAAutoSetFocus(cBrowser.UIA, autoFocusPrevious, autoFocusRestoreDetail)
        autoFocusDetail .= " " . autoFocusRestoreDetail
    }

    if (autoFocusDetail != "") {
        if (actionDetail = "")
            actionDetail := matchLabel . " via=failed"
        actionDetail .= " " . autoFocusDetail
    }

    detail := actionDetail
    return success
}

Browser_FocusPDFDocument(activeHwnd, cBrowser := "", ByRef focusMethod := "") {
    if !IsObject(cBrowser) {
        try cBrowser := new UIA_Browser("ahk_id " . activeHwnd)
        catch
            return false
    }

    WinActivate, ahk_id %activeHwnd%
    WinWaitActive, ahk_id %activeHwnd%, , 1
    Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "begin")

    if Browser_TryRefocusViaDocumentControlClick(activeHwnd, cBrowser, documentClickMethod) {
        focusMethod := documentClickMethod
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    webContentReady := Browser_FocusWebContentPane(activeHwnd, webContentFocusMethod)
    Browser_LogPDFFocusTrace(activeHwnd, "FocusWebContentPane"
        , webContentReady ? "ready" : "continue"
        , webContentFocusMethod)

    if Browser_TryRefocusViaDocumentControlClick(activeHwnd, cBrowser, documentClickMethod) {
        focusMethod := webContentFocusMethod
        if (focusMethod != "")
            focusMethod .= " + "
        focusMethod .= documentClickMethod
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    if Browser_TryRefocusViaMousePoint(activeHwnd, mouseClickFocusMethod) {
        focusMethod := webContentFocusMethod
        if (focusMethod != "")
            focusMethod .= " + "
        focusMethod .= mouseClickFocusMethod
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    if Browser_TryRefocusViaDocumentPhysicalClick(activeHwnd, cBrowser, physicalClickMethod) {
        focusMethod := webContentFocusMethod
        if (focusMethod != "")
            focusMethod .= " + "
        focusMethod .= physicalClickMethod
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    candidates := []

    try {
        docEl := cBrowser.GetCurrentDocumentElement()
        Browser_AddPDFFocusCandidate(candidates, "CurrentDocument", docEl)
    }

    try {
        rootWebArea := cBrowser.BrowserElement.FindFirstBy("AutomationId=RootWebArea")
        Browser_AddPDFFocusCandidate(candidates, "RootWebArea", rootWebArea)
    }

    try {
        genericDoc := cBrowser.BrowserElement.FindFirstBy("ControlType=Document")
        Browser_AddPDFFocusCandidate(candidates, "GenericDocument", genericDoc)
    }

    Browser_PDFZoomLog("pdf_zoom_focus_candidates", Browser_DescribePDFFocusCandidates(candidates))

    logicalFocusOk := false
    logicalFocusMethod := ""
    for _, candidate in candidates {
        Browser_LogPDFFocusTrace(activeHwnd, "LogicalFocusCandidate", "attempt"
            , candidate.Label . " " . candidate.Summary)
        if Browser_TryFocusPDFElement(candidate.Element, candidateMethod, activeHwnd, candidate.Label)
        {
            logicalFocusOk := true
            logicalFocusMethod := candidate.Label . ":" . candidateMethod
            Browser_LogPDFFocusTrace(activeHwnd, "LogicalFocusCandidate", "success", logicalFocusMethod)
            break
        }
        Browser_LogPDFFocusTrace(activeHwnd, "LogicalFocusCandidate", "fail", candidate.Label)
    }

    if Browser_FocusBrowserControl(activeHwnd, controlFocusMethod) {
        focusMethod := logicalFocusMethod
        if (focusMethod != "")
            focusMethod .= " + "
        focusMethod .= controlFocusMethod
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    ; Chromium の PDF viewer は Esc でツールバー由来の疑似フォーカスが外れることがある。
    Browser_LogPDFFocusTrace(activeHwnd, "EscBeforeBrowserControlFocus", "attempt")
    SendInput, {Esc}
    Sleep, 40
    if Browser_FocusBrowserControl(activeHwnd, controlFocusMethodAfterEsc) {
        focusMethod := logicalFocusMethod
        if (focusMethod != "")
            focusMethod .= " + "
        focusMethod .= "Esc + " . controlFocusMethodAfterEsc
        Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument", "success", focusMethod)
        return true
    }

    focusMethod := logicalFocusMethod
    Browser_LogPDFFocusTrace(activeHwnd, "FocusPDFDocument"
        , logicalFocusOk ? "logical_only" : "fail"
        , focusMethod)
    return logicalFocusOk
}

Browser_TryFocusPDFElement(el, ByRef focusMethod := "", activeHwnd := "", candidateLabel := "") {
    if (!el)
        return false

    labelPrefix := (candidateLabel != "") ? candidateLabel . ":" : ""
    Browser_LogPDFFocusTrace(activeHwnd, "LogicalSetFocus", "attempt", labelPrefix . Browser_DescribeElement(el))
    try {
        el.SetFocus()
        Sleep, 40
        if (el.CurrentHasKeyboardFocus) {
            focusMethod := "SetFocus"
            Browser_LogPDFFocusTrace(activeHwnd, "LogicalSetFocus", "success", labelPrefix . focusMethod)
            return true
        }
    }
    Browser_LogPDFFocusTrace(activeHwnd, "LogicalSetFocus", "fail", labelPrefix . "no_keyboard_focus")

    Browser_LogPDFFocusTrace(activeHwnd, "LogicalLegacySelect", "attempt", labelPrefix . Browser_DescribeElement(el))
    try {
        legacy := el.GetCurrentPatternAs("LegacyIAccessible")
        if (legacy) {
            legacy.Select(1) ; TakeFocus
            Sleep, 40
            if (el.CurrentHasKeyboardFocus) {
                focusMethod := "LegacyIAccessible.Select"
                Browser_LogPDFFocusTrace(activeHwnd, "LogicalLegacySelect", "success", labelPrefix . focusMethod)
                return true
            }
        }
    }
    Browser_LogPDFFocusTrace(activeHwnd, "LogicalLegacySelect", "fail", labelPrefix . "no_keyboard_focus")

    Browser_LogPDFFocusTrace(activeHwnd, "LogicalControlClick", "attempt", labelPrefix . Browser_DescribeElement(el))
    try {
        el.ControlClick()
        Sleep, 40
        if (el.CurrentHasKeyboardFocus) {
            focusMethod := "ControlClick"
            Browser_LogPDFFocusTrace(activeHwnd, "LogicalControlClick", "success", labelPrefix . focusMethod)
            return true
        }
    }
    Browser_LogPDFFocusTrace(activeHwnd, "LogicalControlClick", "fail", labelPrefix . "no_keyboard_focus")

    return false
}

TogglePDFZoom() {
    global Browser_PDFZoomNativeShortcutLabel

    Browser_PDFZoomLog("pdf_zoom_toggle_raw"
        , "method=shortcut=" . Browser_PDFZoomNativeShortcutLabel)
    Browser_SendPDFZoomNativeShortcut()
    return true
}

; Legacy UIA/button-based implementation kept for environments where the
; native Edge shortcut is unavailable or needs deeper debugging.
TogglePDFZoomLegacy() {
    global Browser_PDFZoomTryShortcutFirst
    global Browser_PDFZoomNativeShortcutLabel

    activeHwnd := WinExist("A")
    if (!activeHwnd)
        return false

    pdfInfo := Browser_GetPDFContextInfo(activeHwnd, cBrowser)
    Browser_PDFZoomLog("pdf_zoom_start"
        , "state=" . pdfInfo.State
        . " reasons=" . pdfInfo.Reasons
        . " exe=" . pdfInfo.Exe
        . " class=" . pdfInfo.Class
        . " title=" . pdfInfo.Title
        . " url=" . pdfInfo.Url
        . " zoomButton=" . pdfInfo.ZoomButton
        . " focus=" . Browser_GetFocusedElementSummary()
        . " " . Browser_GetFocusedControlSummary(activeHwnd)
        . (pdfInfo.Error != "" ? " error=" . pdfInfo.Error : ""))

    if (pdfInfo.State != 1) {
        Browser_PDFZoomLog("pdf_zoom_skip_not_pdf"
            , "title=" . pdfInfo.Title . " url=" . pdfInfo.Url)
        return false
    }

    zoomMethod := ""
    usedButtonPath := false
    preButtonState := IsObject(cBrowser) ? Browser_DescribePDFZoomButton(cBrowser) : "no_browser"
    if (Browser_PDFZoomTryShortcutFirst && IsObject(cBrowser) && Browser_TogglePDFZoomViaShortcut(cBrowser, zoomMethod, preButtonState)) {
        Browser_PDFZoomLog("pdf_zoom_toggle"
            , "method=" . zoomMethod
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
        return true
    }

    if (Browser_PDFZoomTryShortcutFirst) {
        Browser_PDFZoomLog("pdf_zoom_toggle_shortcut_failed"
            , zoomMethod
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
    }

    if (IsObject(cBrowser) && Browser_TogglePDFZoomViaButton(cBrowser, zoomMethod)) {
        usedButtonPath := true
        postButtonState := Browser_DescribePDFZoomButton(cBrowser)
        Browser_PDFZoomLog("pdf_zoom_toggle"
            , "method=button " . zoomMethod
            . " preButton=" . preButtonState
            . " postButton=" . postButtonState
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
    } else {
        zoomMethod := "shortcut=" . Browser_PDFZoomNativeShortcutLabel
        Browser_PDFZoomLog("pdf_zoom_toggle_fallback"
            , zoomMethod . " preButton=" . preButtonState)
        Browser_SendPDFZoomNativeShortcut()
        Sleep, 40
        postButtonState := IsObject(cBrowser) ? Browser_DescribePDFZoomButton(cBrowser) : "no_browser"
        Browser_PDFZoomLog("pdf_zoom_toggle"
            , "method=" . zoomMethod
            . " preButton=" . preButtonState
            . " postButton=" . postButtonState
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
        return true
    }
    Sleep, 40

    if (usedButtonPath && Browser_FocusPDFDocument(activeHwnd, cBrowser, focusMethod)) {
        Browser_PDFZoomLog("pdf_zoom_focus_restore"
            , "result=ok method=" . zoomMethod . " focusMethod=" . focusMethod
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
        return true
    }

    if (usedButtonPath) {
        Browser_PDFZoomLog("pdf_zoom_focus_restore"
            , "result=logical_only method=" . zoomMethod . " focusMethod=" . focusMethod
            . " focus=" . Browser_GetFocusedElementSummary()
            . " " . Browser_GetFocusedControlSummary(activeHwnd))
    }
    return true
}

InspectElementUnderMouse() {
    UIA := UIA_Interface()
    if (!UIA)
        return

    try {
        ; マウスカーソルの位置にある要素を取得
        MouseGetPos, x, y
        element := UIA.ElementFromPoint(x, y)

        info := ""
        info .= "Name: " . element.CurrentName . "`n"
        info .= "ControlType: " . element.CurrentLocalizedControlType . " (" . element.CurrentControlType . ")`n"
        info .= "AutomationId: " . element.CurrentAutomationId . "`n"
        info .= "ClassName: " . element.CurrentClassName . "`n"

        ; 親要素の情報も有用な場合が多いので取得（1階層上）
        walker := UIA.TreeWalkerTrue
        parent := walker.GetParentElement(element)
        if (parent) {
            info .= "`n【親要素】`n"
            info .= "Name: " . parent.CurrentName . "`n"
            info .= "ControlType: " . parent.CurrentLocalizedControlType . " (" . parent.CurrentControlType . ")"
        }

        MsgBox, % "【マウス下の要素情報】`n`n" . info
    } catch e {
        MsgBox, 取得に失敗しました。`n%e%
    }
}

CheckFocus() {
    UIA := UIA_Interface()
    if (!UIA) {
        MsgBox, UIAの初期化に失敗しました
        return
    }
    try {
        ; 現在フォーカスを持っている要素を取得
        focusedEl := UIA.GetFocusedElement()
        info := ""
        info .= "Name: " . focusedEl.CurrentName . "`n"
        info .= "ControlType: " . focusedEl.CurrentLocalizedControlType . " (" . focusedEl.CurrentControlType . ")`n"
        info .= "AutomationId: " . focusedEl.CurrentAutomationId . "`n"
        info .= "ClassName: " . focusedEl.CurrentClassName
        MsgBox, % "【現在のフォーカス要素】`n`n" . info
    } catch e {
        MsgBox, フォーカス要素の取得に失敗しました。`n%e%
    }
}

; ==========================================================
; Youtube: 画質を1080pに変更する
; ==========================================================
YouTubeSet1080p(cBrowser) {
    ; UIA初期化
    UIA := (cBrowser.UIA) ? cBrowser.UIA : UIA_Interface()
    if (!UIA)
        return

    ; --- 1. 設定ボタンを押す ---
    settingsBtn := cBrowser.FindFirstByNameAndType("設定", "Button")
    if (!settingsBtn)
        settingsBtn := cBrowser.FindFirstByNameAndType("Settings", "Button")

    if (!settingsBtn) {
        ShowYouTubeTooltip("設定ボタンが見つかりません")
        return
    }

    settingsBtn.Click()
    Sleep, 300

    ; --- 2. メニューから「画質」を探す ---
    qualityEl := FindElementByKeyword(cBrowser, ["画質", "Quality"])

    if (!qualityEl) {
        settingsBtn.Click()
        ShowYouTubeTooltip("画質メニューが見つかりません")
        return
    }

    qualityEl.Click()
    Sleep, 300

    ; --- 3. 「1080p」を探すが、「Premium」と「Enhanced」は除外する ---
    ; 第3引数に除外したいキーワードの配列を渡します
    targetRes := FindElementByKeyword(cBrowser, ["1080p"], ["Premium", "Enhanced"])

    if (targetRes) {
        targetRes.Click()
        ShowYouTubeTooltip("1080pに変更しました")
        return
    }

    ; --- 4. 詳細(Advanced)を探す ---
    advancedEl := FindElementByKeyword(cBrowser, ["詳細", "Advanced"])

    if (advancedEl) {
        advancedEl.Click()
        Sleep, 300

        ; 詳細の中でも Premium を除外して探す
        targetRes := FindElementByKeyword(cBrowser, ["1080p"], ["Premium", "Enhanced"])
        if (targetRes) {
            targetRes.Click()
            ShowYouTubeTooltip("詳細から1080pに変更しました")
        } else {
            ShowYouTubeTooltip("1080p (通常) が見つかりませんでした")
            Send, {Esc}
        }
    } else {
        ShowYouTubeTooltip("画質選択肢が見つかりません")
        Send, {Esc}
    }
}

ShowYouTubeTooltip(msg) {
    ToolTip, % msg
    SetTimer, CloseToolTip, -2000
}

; 調査用: フォーカスされた要素の「隣（兄弟）」をすべて表示する
DebugYouTubeSiblings(cBrowser) {
    settingsBtn := cBrowser.FindFirstByName("設定")
    if (!settingsBtn) settingsBtn := cBrowser.FindFirstByName("Settings")
        settingsBtn.Click()
    Sleep, 1000 ; メニューが開くのを待つ

    try {
        UIA := (cBrowser.UIA) ? cBrowser.UIA : UIA_Interface()
        focused := UIA.GetFocusedElement() ; フォーカス（メニューの1行目）を取得
        walker := UIA.TreeWalker.ControlViewWalker
        parent := walker.GetParentElement(focused) ; 親（メニュー枠）を取得

        ; 親の中にある子供（メニュー項目）をすべて列挙
        children := parent.FindAll(UIA.CreateTrueCondition())

        list := "メニュー項目一覧:`n"
        Loop % children.MaxIndex() {
            child := children[A_Index]
            list .= "[" . A_Index . "] Name: " . child.CurrentName . " / Type: " . child.CurrentLocalizedControlType . "`n"
        }
        MsgBox, % list
    } catch e {
        MsgBox, エラー: %e%
    }
}

; ==============================================================================
; 3. 共通関数 (ロジック本体)
;    fallbackKey : URLがマッチしなかった時に送信するキー (例: "{F1}")
;    targetMap   : 検索対象の連想配列 (例: KeyActions["F1"])
; ==============================================================================
RunSiteSpecificKey(fallbackKey, targetMap) {
    url := ""
    try {
        cBrowser := new UIA_Browser("A")
        url := cBrowser.GetCurrentURL()
    }

    ; ブラウザでない、またはURLが取れない場合は元のキーを送信して終了
    if (url = "") {
        Send, %fallbackKey%
        return
    }

    hit := false

    ; 渡されたマップ (targetMap) の中身だけを検索
    for keyUrl, actionFunc in targetMap {
        if InStr(url, keyUrl) {
            ; アクション実行
            actionFunc.Call(cBrowser, url)

            hit := true

            ; ツールチップ表示 (どのキーの機能か分かりやすくするため fallbackKey も表示)
            ToolTip, % keyUrl . " 用の機能を実行しました (" . fallbackKey . ")"
            SetTimer, CloseToolTip, -2000
            break
        }
    }

    ; ヒットしなかった場合は元のキーを送信
    if (!hit) {
        Send, %fallbackKey%
    }
}

; ==============================================================================
; ブラウザ上で実行
; ウィンドウ内の全てのタブのURLをC:\myApp\__temp__\urls.txtに追加
; ==============================================================================
GetAllEdgeURLs(includeTitle := false) {
    ; 保存先の設定
    global Browser_URLExportPath

    targetPath := Trim(Browser_URLExportPath)
    if (targetPath = "")
        targetPath := "C:\myApp\__temp__\urls.txt"
    SplitPath, targetPath, , targetDir

    ; フォルダがない場合は作成
    if (targetDir != "" && !InStr(FileExist(targetDir), "D")) {
        FileCreateDir, %targetDir%
    }

    WinGet, activeHwnd, ID, A

    try {
        cUIA := new UIA_Browser("ahk_id " . activeHwnd)
    } catch e {
        MsgBox, 16, エラー, Edgeの初期化に失敗しました。
        return
    }

    outText := ""
    firstUrl := ""
    firstTitle := ""

    Loop {
        ; UIAを使って裏側からURLを確実に取得（クリップボード不使用）
        currentUrl := cUIA.GetCurrentURL()
        WinGetTitle, currentTitle, ahk_id %activeHwnd%

        ; 1周したかどうかの判定
        if (A_Index == 1) {
            ; 最初のタブのURLとタイトルを記憶
            firstUrl := currentUrl
            firstTitle := currentTitle
        }
        else if (currentUrl == firstUrl && currentTitle == firstTitle) {
            ; URLとタイトルが最初のタブと完全に一致したら「一周した」とみなしてループを抜ける
            break
        }

        ; 無限ループ防止用のリミッター (100タブで強制終了)
        if (A_Index > 100) {
            break
        }

        ; 出力テキストに追加
        if (currentUrl != "") {
            if (includeTitle) {
                outText .= currentTitle . "`n" . currentUrl . "`n"
            } else {
                outText .= currentUrl . "`n"
            }
        }

        ; ショートカットキーで次のタブへ移動
        Send, ^{Tab}
        Sleep, 150 ; 画面の切り替わりを少し待つ (環境によって増減可)
    }

    ; 結果をファイルに追記
    if (outText != "") {
        FileAppend, %outText%, %targetPath%, UTF-8
    }
}

Debug_GetAllEdgeURLs() {
    MsgBox, 64, Debug 1, 関数が開始されました。

    ; 1. アクティブウィンドウの情報を取得して確認
    WinGet, activeHwnd, ID, A
    WinGetClass, activeClass, ahk_id %activeHwnd%
    WinGet, activeExe, ProcessName, ahk_id %activeHwnd%
    WinGetTitle, activeTitle, ahk_id %activeHwnd%

    MsgBox, 64, Debug 2, 【ウィンドウ情報】`nHWND: %activeHwnd%`nExe: %activeExe%`nClass: %activeClass%`nTitle: %activeTitle%

    if (activeExe != "msedge.exe") {
        MsgBox, 48, Debug エラー, アクティブなウィンドウが Edge (msedge.exe) ではありません。処理を中断します。
        return
    }

    ; 2. UIA_Browser の初期化テスト
    try {
        ; もしここで失敗する場合、"ahk_id " . activeHwnd ではなく "ahk_exe msedge.exe" に変えると動くことがあります
        cUIA := new UIA_Browser("ahk_id " . activeHwnd)
        MsgBox, 64, Debug 3, UIA_Browser の初期化に成功しました。
    } catch e {
        MsgBox, 16, Debug エラー, UIA_Browserの初期化でエラーが発生しました。`n%e%
        return
    }

    ; 3. タブの取得テスト
    tabs := cUIA.GetTabs()

    if (!tabs || tabs.MaxIndex() == "") {
        MsgBox, 48, Debug 4 (失敗), GetTabs() が空を返しました。`nUIAがEdgeのタブ要素を見つけられていません。
        return
    }

    tabCount := tabs.MaxIndex()
    MsgBox, 64, Debug 4 (成功), GetTabs() 成功！`n見つかったタブの数: %tabCount%

    ; 4. 最初のタブ情報とURL取得テスト
    if (tabCount > 0) {
        firstTabName := tabs[1].Name
        MsgBox, 64, Debug 5, 最初のタブの名前:`n%firstTabName%

        try {
            cUIA.SelectTab(tabs[1])
            Sleep, 100
            currentUrl := cUIA.GetCurrentURL()
            MsgBox, 64, Debug 6, URL取得テスト:`n%currentUrl%
        } catch e {
            MsgBox, 16, Debug エラー, URL取得中にエラーが発生しました。`n%e%
        }
    }

    MsgBox, 64, Debug 完了, デバッグ処理が最後まで到達しました。
}
