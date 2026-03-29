; ==============================================================================
; BracketWrap
; - Wrap selected text with brackets/quotes
; - Keep selection after wrapping
; - Provide smart Ctrl+C / Ctrl+X / Ctrl+D in editor windows
; ==============================================================================

global BW_UIA                      := ""
global BW_ExcludeApps              := Object()
global BW_OpenToClose              := Object()
global BW_CloseToOpen              := Object()
global BW_SymmetricSet             := Object()
global BW_DebugEnabled             := true
global BW_DebugLogDir              := A_ScriptDir . "\.claude"
global BW_DebugLogPath             := BW_DebugLogDir . "\bracket_wrap_debug.log"
global BW_DebugMaxBytes            := 262144
global BW_SelectionProbeTimeout    := 0.15

BW_Init() {
    global BW_UIA, BW_OpenToClose, BW_CloseToOpen, BW_SymmetricSet, BW_ExcludeApps

    try
        BW_UIA := UIA_Interface()

    BW_DebugInit()

    BW_ExcludeApps["POWERPNT.EXE"] := true

    lBrace := Chr(123)
    rBrace := Chr(125)

    BW_OpenToClose["("] := ")"
    BW_OpenToClose["["] := "]"
    BW_OpenToClose[lBrace] := rBrace

    BW_CloseToOpen[")"] := "("
    BW_CloseToOpen["]"] := "["
    BW_CloseToOpen[rBrace] := lBrace

    BW_SymmetricSet[""""] := true
    BW_SymmetricSet["'"] := true
    BW_SymmetricSet["$"] := true
    BW_SymmetricSet[Chr(37)] := true
}

BW_DebugInit() {
    global BW_DebugEnabled

    if (!BW_DebugEnabled)
        return

    BW_DebugEnsureLogDir()
    BW_DebugLog("startup", "script=" . A_ScriptFullPath)
}

BW_DebugEnsureLogDir() {
    global BW_DebugLogDir

    if !InStr(FileExist(BW_DebugLogDir), "D")
        FileCreateDir, %BW_DebugLogDir%
}

BW_DebugRotateIfNeeded() {
    global BW_DebugLogPath, BW_DebugMaxBytes

    if !FileExist(BW_DebugLogPath)
        return

    FileGetSize, logSize, %BW_DebugLogPath%
    if (logSize < BW_DebugMaxBytes)
        return

    backupPath := RegExReplace(BW_DebugLogPath, "\.log$", ".old.log")
    FileDelete, %backupPath%
    FileMove, %BW_DebugLogPath%, %backupPath%, 1
}

BW_DebugSanitize(text) {
    text := StrReplace(text, "`r", " ")
    text := StrReplace(text, "`n", " ")
    text := StrReplace(text, "`t", " ")
    return text
}

BW_DebugTrim(text, maxLen := 140) {
    if (StrLen(text) <= maxLen)
        return text
    return SubStr(text, 1, maxLen) . "..."
}

BW_DebugLog(event, extra := "") {
    global BW_DebugEnabled, BW_DebugLogPath

    if (!BW_DebugEnabled)
        return

    BW_DebugEnsureLogDir()
    BW_DebugRotateIfNeeded()

    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " extra=" . BW_DebugSanitize(extra)
    FileAppend, % line . "`n", %BW_DebugLogPath%, UTF-8
}

BW_DebugSnapshot(reason := "manual") {
    details := BW_DebugCollectSnapshot()
    BW_DebugLog("snapshot", "reason=" . reason . " " . details)
    ToolTip, BracketWrap snapshot saved
    SetTimer, CloseToolTip, -1500
}

BW_DebugOpenLog() {
    global BW_DebugLogPath

    BW_DebugEnsureLogDir()
    if !FileExist(BW_DebugLogPath)
        FileAppend,, %BW_DebugLogPath%, UTF-8

    Run, notepad.exe "%BW_DebugLogPath%"
}

BW_DebugCollectSnapshot() {
    activeHwnd := WinExist("A")
    WinGet, activeExe, ProcessName, ahk_id %activeHwnd%
    WinGetClass, activeClass, ahk_id %activeHwnd%
    WinGetTitle, activeTitle, ahk_id %activeHwnd%

    info := "activeHwnd=" . activeHwnd
        . " activeExe=" . activeExe
        . " activeClass=" . activeClass
        . " activeTitle=" . BW_DebugSanitize(activeTitle)
        . " wrapFeature=" . BW_WrapFeatureEnabled()
        . " smartFeature=" . BW_SmartHotkeysEnabled()

    candidates := BW_GetSelectionCandidates()
    if (IsObject(candidates) && candidates.MaxIndex()) {
        loopCount := candidates.MaxIndex()
        if (loopCount > 10)
            loopCount := 10
        Loop, %loopCount% {
            entry := candidates[A_Index]
            info .= " cand" . A_Index . "=" . BW_DebugDescribeCandidate(entry.Tag, entry.El)
        }
    } else {
        info .= " candidates=none"
    }

    matchedTag := ""
    matchedEl := ""
    selectionText := ""
    selectionStatus := BW_FindSelectedText(selectionText, matchedTag, matchedEl)
    info .= " selectionStatus=" . selectionStatus
        . " matchedTag=" . matchedTag
        . " selectionLen=" . StrLen(selectionText)
        . " selectionText=""" . BW_DebugSanitize(BW_DebugTrim(selectionText, 80)) . """"

    return info
}

BW_DebugDescribeCandidate(tag, el) {
    selectionText := ""
    selectionStatus := BW_TryGetSelectionFromElement(el, selectionText)
    return tag . "{" . BW_DebugDescribeElement(el)
        . " sel=" . selectionStatus
        . " len=" . StrLen(selectionText)
        . " text=""" . BW_DebugSanitize(BW_DebugTrim(selectionText, 40)) . """}"
}

BW_DebugDescribeElement(el) {
    if (!el)
        return "none"

    frameworkId := ""
    textAvailable := ""
    dumpText := ""

    try
        frameworkId := el.CurrentFrameworkId
    try
        textAvailable := el.GetCurrentPropertyValue("IsTextPatternAvailable")
    try
        dumpText := el.Dump()

    return BW_DebugSanitize(BW_DebugTrim(dumpText, 180))
        . " FrameworkId=" . frameworkId
        . " TextPattern=" . textAvailable
}

BW_GetSelectedText(ByRef outText) {
    return BW_FindSelectedText(outText)
}

BW_GetSelectedTextByUIA(ByRef outText) {
    matchedTag := ""
    matchedEl := ""
    if BW_FindSelectedTextCandidate(outText, matchedEl, matchedTag)
        return 1

    outText := ""
    return 0
}

BW_FindSelectedText(ByRef outText, ByRef matchedTag := "", ByRef matchedEl := "") {
    if BW_FindSelectedTextCandidate(outText, matchedEl, matchedTag)
        return 1

    if BW_WrapClipboardFallbackEnabled() && BW_TryGetSelectionByClipboard(outText) {
        matchedTag := "clipboard"
        matchedEl := ""
        return 1
    }

    outText := ""
    matchedTag := ""
    matchedEl := ""
    return 0
}

BW_FindSelectedTextCandidate(ByRef outText, ByRef matchedEl := "", ByRef matchedTag := "") {
    candidates := BW_GetSelectionCandidates()
    if !(IsObject(candidates) && candidates.MaxIndex()) {
        outText := ""
        matchedEl := ""
        matchedTag := ""
        return false
    }

    for _, entry in candidates {
        selectionText := ""
        if (BW_TryGetSelectionFromElement(entry.El, selectionText) = 1) {
            outText := selectionText
            matchedEl := entry.El
            matchedTag := entry.Tag
            return true
        }
    }

    outText := ""
    matchedEl := ""
    matchedTag := ""
    return false
}

BW_TryGetSelectionFromElement(el, ByRef outText) {
    outText := ""
    if (!el)
        return -1

    tp := ""
    try
        tp := el.GetCurrentPatternAs("Text")
    if (!tp)
        return -1

    ranges := ""
    try
        ranges := tp.GetSelection()
    if (!ranges)
        return 0

    rangeCount := 0
    try
        rangeCount := ranges.Length
    if (!rangeCount)
        return 0

    range := ""
    try
        range := ranges.GetElement(0)
    if (!range)
        return 0

    try
        outText := range.GetText(-1)
    if (StrLen(outText) < 1)
        return 0

    return 1
}

BW_GetSelectionCandidates() {
    global BW_UIA

    if (!BW_UIA)
        return []

    candidates := []
    seen := Object()
    activeHwnd := WinExist("A")

    focusedEl := ""
    try
        focusedEl := BW_UIA.GetFocusedElement()
    BW_AddCandidate(candidates, seen, focusedEl, "focused")
    BW_AddParentCandidates(candidates, seen, focusedEl, "focusedParent", 8)

    windowEl := ""
    try
        windowEl := BW_UIA.ElementFromHandle(activeHwnd)
    BW_AddCandidate(candidates, seen, windowEl, "window")

    if (WinActive("ahk_group BrowserGroup") || WinActive("ahk_exe Code.exe")) {
        chromiumNormalized := ""
        chromiumRenderer := ""
        try
            chromiumNormalized := BW_UIA.GetChromiumContentElement("A")
        try
            chromiumRenderer := BW_UIA.ElementFromChromium("A")

        BW_AddCandidate(candidates, seen, chromiumNormalized, "chromiumNormalized")
        BW_AddParentCandidates(candidates, seen, chromiumNormalized, "chromiumNormalizedParent", 6)
        BW_AddCandidate(candidates, seen, chromiumRenderer, "chromiumRenderer")
        BW_AddDescendantsByType(candidates, seen, chromiumRenderer, "Document", "chromiumRendererDocument", 8)
        BW_AddDescendantsByType(candidates, seen, chromiumRenderer, "Edit", "chromiumRendererEdit", 8)
        BW_AddDescendantsByType(candidates, seen, chromiumNormalized, "Document", "chromiumNormalizedDocument", 8)
        BW_AddDescendantsByType(candidates, seen, chromiumNormalized, "Edit", "chromiumNormalizedEdit", 8)

        if (WinActive("ahk_group BrowserGroup")) {
            browserDoc := ""
            try {
                cBrowser := new UIA_Browser("A")
                browserDoc := cBrowser.GetCurrentDocumentElement()
            }
            BW_AddCandidate(candidates, seen, browserDoc, "browserCurrentDocument")
        }
    }

    if (WinActive("ahk_group EditorGroup") || WinActive("ahk_exe pycharm64.exe")) {
        BW_AddDescendantsByType(candidates, seen, windowEl, "Document", "windowDocument", 12)
        BW_AddDescendantsByType(candidates, seen, windowEl, "Edit", "windowEdit", 12)
    }

    BW_AddTextPatternCandidates(candidates, seen, focusedEl, "focusedTextPattern", 16)
    BW_AddTextPatternCandidates(candidates, seen, windowEl, "windowTextPattern", 24)

    return candidates
}

BW_AddParentCandidates(ByRef candidates, ByRef seen, el, prefix, maxDepth := 6) {
    global BW_UIA

    if (!el)
        return

    walker := BW_UIA.TreeWalkerTrue
    currentEl := el
    Loop, %maxDepth% {
        try
            currentEl := walker.GetParentElement(currentEl)
        if (!currentEl)
            break

        BW_AddCandidate(candidates, seen, currentEl, prefix . A_Index)
    }
}

BW_AddDescendantsByType(ByRef candidates, ByRef seen, rootEl, controlType, prefix, limit := 8) {
    if (!rootEl)
        return

    found := ""
    try
        found := rootEl.FindAllByType(controlType)
    if !(IsObject(found) && found.MaxIndex())
        return

    loopCount := found.MaxIndex()
    if (loopCount > limit)
        loopCount := limit

    Loop, %loopCount%
        BW_AddCandidate(candidates, seen, found[A_Index], prefix . A_Index)
}

BW_AddTextPatternCandidates(ByRef candidates, ByRef seen, rootEl, prefix, limit := 12) {
    global BW_UIA

    if (!rootEl || !BW_UIA)
        return

    found := ""
    try {
        cond := BW_UIA.CreatePropertyCondition("IsTextPatternAvailable", 1)
        found := rootEl.FindAll(cond)
    }
    if !(IsObject(found) && found.MaxIndex())
        return

    loopCount := found.MaxIndex()
    if (loopCount > limit)
        loopCount := limit

    Loop, %loopCount%
        BW_AddCandidate(candidates, seen, found[A_Index], prefix . A_Index)
}

BW_AddCandidate(ByRef candidates, ByRef seen, el, tag) {
    if (!el)
        return

    key := ""
    try
        key := el.__Value
    if (key = "")
        key := tag

    if seen.HasKey(key)
        return

    seen[key] := true
    candidates.Push({El: el, Tag: tag})
}

BW_TryGetSelectionByClipboard(ByRef outText) {
    global BW_SelectionProbeTimeout

    outText := ""
    clipSaved := ClipboardAll
    Clipboard := ""
    SendInput, ^c
    ClipWait, %BW_SelectionProbeTimeout%
    if (ErrorLevel || Clipboard = "") {
        Clipboard := clipSaved
        VarSetCapacity(clipSaved, 0)
        return false
    }

    outText := Clipboard
    Clipboard := clipSaved
    VarSetCapacity(clipSaved, 0)
    return true
}

BW_ReplaceSelection(newText, keepSelection := true) {
    prefix := Chr(123) . "Text" . Chr(125)
    SendInput, % prefix . newText
    Sleep, 30

    if (keepSelection && newText != "")
        BW_ReselectInsertedText(StrLen(newText))
}

BW_ReselectInsertedText(length) {
    if (length < 1)
        return

    SendInput, {Shift down}
    Loop, %length%
        SendInput, {Left}
    SendInput, {Shift up}
}

BW_SendChar(char) {
    prefix := Chr(123) . "Text" . Chr(125)
    SendInput, % prefix . char
}

BW_SendOriginalKeys(keys) {
    SendInput, %keys%
}

BW_OnKey(char, fallbackKeys) {
    global BW_OpenToClose, BW_CloseToOpen, BW_SymmetricSet

    selText := ""
    matchedTag := ""
    matchedEl := ""
    if !BW_FindSelectedTextCandidate(selText, matchedEl, matchedTag) {
        BW_DebugLog("wrap_passthrough", "char=" . char . " reason=no-selection")
        return BW_SendOriginalKeys(fallbackKeys)
    }

    BW_DebugLog("wrap_match"
        , "char=" . char
        . " matchedTag=" . matchedTag
        . " len=" . StrLen(selText)
        . " text=""" . BW_DebugSanitize(BW_DebugTrim(selText, 80)) . """")

    if (BW_SymmetricSet.HasKey(char))
        return BW_OnKey_Symmetric(char, selText)
    if (BW_OpenToClose.HasKey(char))
        return BW_ReplaceSelection(char . selText . BW_OpenToClose[char])
    if (BW_CloseToOpen.HasKey(char))
        return BW_OnKey_Unwrap(char, selText, fallbackKeys)
    BW_SendOriginalKeys(fallbackKeys)
}

BW_OnKey_Symmetric(char, text) {
    if (BW_StrHasWrap(text, char, char))
        BW_ReplaceSelection(SubStr(text, 2, StrLen(text) - 2))
    else
        BW_ReplaceSelection(char . text . char)
}

BW_OnKey_Unwrap(char, text, fallbackKeys) {
    global BW_CloseToOpen

    open := BW_CloseToOpen[char]
    if (BW_StrHasWrap(text, open, char))
        BW_ReplaceSelection(SubStr(text, 2, StrLen(text) - 2))
    else
        BW_SendOriginalKeys(fallbackKeys)
}

BW_SmartCopy() {
    selText := ""
    if !BW_SmartHotkeysEnabled() {
        SendInput, ^c
        return
    }

    if (BW_GetSelectedText(selText) = 1) {
        SendInput, ^c
        return
    }

    Send, {Home}
    Send, +{End}
    Send, +{Right}
    Send, ^c
    Send, {Right}
    Send, {Left}
}

BW_SmartCut() {
    selText := ""
    if !BW_SmartHotkeysEnabled() {
        SendInput, ^x
        return
    }

    if (BW_GetSelectedText(selText) = 1) {
        SendInput, ^x
        return
    }

    Send, {Home}
    Send, +{End}
    Send, +{Right}
    Send, ^x
}

BW_SmartDelete() {
    selText := ""
    if !BW_SmartHotkeysEnabled() {
        SendInput, ^d
        return
    }

    if (BW_GetSelectedText(selText) = 1) {
        SendInput, ^d
        return
    }

    Send, {Home}
    Send, +{End}
    Send, +{Right}
    Send, {Del}
}

BW_StrHasWrap(text, prefix, suffix) {
    return (StrLen(text) >= 2
        && SubStr(text, 1, 1) = prefix
        && SubStr(text, 0) = suffix)
}

BW_IsExcluded() {
    global BW_ExcludeApps

    WinGet, exeName, ProcessName, A
    return BW_ExcludeApps.HasKey(exeName)
}

BW_WrapFeatureEnabled() {
    global EnableBracketWrap
    return EnableBracketWrap && !BW_IsExcluded()
}

BW_WrapClipboardFallbackEnabled() {
    WinGet, exeName, ProcessName, A
    WinGetTitle, title, A

    if (exeName = "notepad.exe")
        return true

    if (exeName = "ApplicationFrameHost.exe" && InStr(title, "Notepads"))
        return true

    return false
}

BW_SmartHotkeysEnabled() {
    if !BW_WrapFeatureEnabled()
        return false

    return WinActive("ahk_group EditorGroup") || WinActive("ahk_exe pycharm64.exe")
}
