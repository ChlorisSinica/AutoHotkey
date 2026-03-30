; ==============================================================================
; TextEditor — 括弧ラップ / Smart 行操作
;
; 機能:
;   - 選択テキストを括弧/引用符で囲む (wrap)
;   - 括弧で囲まれたテキストの括弧を外す (unwrap)
;   - IME ON 時に全角括弧 「」『』【】（） に対応
;   - テキスト未選択時の Ctrl+C/X/D で行コピー/カット/複製
;
; 依存:
;   - UiaIntegration.ahk: UiaIsEditable(), UiaHasSelection()
;   - Hotstring.ahk: IME_GetTargetHwnd(), IME_GetOpenStatusForHwnd()
;
; ガード:
;   - #If (EnableBracketWrap && UiaIsEditable() && UiaHasSelection())
;   - #If (EnableBracketWrap && UiaIsEditable() && !UiaHasSelection() && BW_SmartKeysEnabled())
; ==============================================================================

; ── グローバル変数 ──────────────────────────────────────────
global BW_OpenToClose     := Object()
global BW_CloseToOpen     := Object()
global BW_SymmetricSet    := Object()
global BW_IME_OpenToClose := Object()
global BW_IME_CloseToOpen := Object()
global BW_ExcludeApps     := Object()
global BW_SmartKeyApps    := Object()

; デバッグ
global BW_DebugEnabled  := true
global BW_DebugLogDir   := A_ScriptDir . "\.claude"
global BW_DebugLogPath  := BW_DebugLogDir . "\bracket_wrap_debug.log"
global BW_DebugMaxBytes := 262144

; ── 初期化 ──────────────────────────────────────────────────

BW_Init() {
    global BW_OpenToClose, BW_CloseToOpen, BW_SymmetricSet
    global BW_IME_OpenToClose, BW_IME_CloseToOpen, BW_ExcludeApps

    BW_DebugInit()

    lBrace := Chr(123)
    rBrace := Chr(125)

    ; 半角括弧マッピング
    BW_OpenToClose["("] := ")"
    BW_OpenToClose["["] := "]"
    BW_OpenToClose[lBrace] := rBrace

    BW_CloseToOpen[")"] := "("
    BW_CloseToOpen["]"] := "["
    BW_CloseToOpen[rBrace] := lBrace

    ; 対称文字
    BW_SymmetricSet[""""] := true
    BW_SymmetricSet["'"] := true
    BW_SymmetricSet["$"] := true
    BW_SymmetricSet[Chr(37)] := true   ; %

    ; 全角括弧マッピング (IME ON 用: 開き括弧)
    BW_IME_OpenToClose["("] := BW_Pair("（", "）")
    BW_IME_OpenToClose["["] := BW_Pair("「", "」")
    BW_IME_OpenToClose[lBrace] := BW_Pair("『", "』")

    ; 全角括弧マッピング (IME ON 用: 閉じ括弧)
    BW_IME_CloseToOpen[")"] := BW_Pair("", "")
    BW_IME_CloseToOpen["]"] := BW_Pair("【", "】")
    BW_IME_CloseToOpen[rBrace] := BW_Pair("", "")

    ; unwrap 対象の全角ペア (IME 状態不問で検出)
    BW_CloseToOpen["）"] := "（"
    BW_CloseToOpen["」"] := "「"
    BW_CloseToOpen["』"] := "『"
    BW_CloseToOpen["】"] := "【"

    ; 除外アプリ
    BW_ExcludeApps["POWERPNT.EXE"] := true

    ; Smart 行操作ホワイトリスト → SmartKeyGroup 動的生成
    ; BW_SmartKeyApps は SUI_LoadConfig() で INI から展開済み
    for exeName, _ in BW_SmartKeyApps
        GroupAdd, SmartKeyGroup, ahk_exe %exeName%
}

; ── ガード関数 ──────────────────────────────────────────────

BW_SmartKeysEnabled() {
    return WinActive("ahk_group SmartKeyGroup")
}

BW_Pair(open, close) {
    obj := Object()
    obj.Open := open
    obj.Close := close
    return obj
}

BW_IsExcluded() {
    global BW_ExcludeApps
    WinGet, exeName, ProcessName, A
    return BW_ExcludeApps.HasKey(exeName)
}

; ── テキスト取得 ────────────────────────────────────────────

BW_GetSelectionByClipboard(ByRef outText) {
    outText := ""
    clipSaved := ClipboardAll
    Clipboard := ""
    SendInput, ^c
    ClipWait, 0.3
    if (ErrorLevel || Clipboard = "") {
        BW_DebugLog("clipboard_fail", "ErrorLevel=" . ErrorLevel)
        Clipboard := clipSaved
        VarSetCapacity(clipSaved, 0)
        return false
    }
    outText := Clipboard
    Clipboard := clipSaved
    VarSetCapacity(clipSaved, 0)
    return true
}

; ── 括弧ラップ: メインハンドラ ──────────────────────────────

BW_OnKey(char) {
    global BW_OpenToClose, BW_CloseToOpen, BW_SymmetricSet

    if (BW_IsExcluded()) {
        BW_SendChar(char)
        return
    }

    selText := ""
    if !BW_GetSelectionByClipboard(selText) {
        BW_SendChar(char)
        return
    }

    BW_DebugLog("wrap_match", "char=" . char . " len=" . StrLen(selText))

    if (BW_SymmetricSet.HasKey(char))
        return BW_OnKey_Symmetric(char, selText)
    if (BW_OpenToClose.HasKey(char))
        return BW_ReplaceSelection(char . selText . BW_OpenToClose[char])
    if (BW_CloseToOpen.HasKey(char))
        return BW_OnKey_Unwrap(char, selText)

    BW_SendChar(char)
}

; ── IME 連動括弧ハンドラ ────────────────────────────────────

BW_OnKeyIME(char) {
    global BW_OpenToClose, BW_CloseToOpen
    global BW_IME_OpenToClose, BW_IME_CloseToOpen

    if (BW_IsExcluded()) {
        BW_SendChar(char)
        return
    }

    hTarget := IME_GetTargetHwnd(activeHwnd)
    imeOn := IME_GetVerifiedOpenStatus(hTarget, activeHwnd)
    BW_DebugLog("ime_state", "imeOn=" . imeOn . " hTarget=" . hTarget . " activeHwnd=" . activeHwnd . " char=" . char)

    if (!imeOn || imeOn = "")
        return BW_OnKey(char)

    ; IME ON → 全角括弧マッピングを使用
    selText := ""
    if !BW_GetSelectionByClipboard(selText) {
        BW_SendChar(char)
        return
    }

    ; 開き括弧の IME マッピング
    if (BW_IME_OpenToClose.HasKey(char)) {
        mapping := BW_IME_OpenToClose[char]
        BW_DebugLog("wrap", "before=" . selText . " open=" . mapping.Open . " close=" . mapping.Close)
        BW_ReplaceSelection(mapping.Open . selText . mapping.Close)
        return
    }

    ; 閉じ括弧の IME マッピング
    if (BW_IME_CloseToOpen.HasKey(char)) {
        mapping := BW_IME_CloseToOpen[char]

        ; まず全ペアの unwrap を試行
        unwrapped := BW_TryUnwrapAny(selText)
        if (unwrapped != "") {
            BW_DebugLog("unwrap_ime", "before=" . selText . " after=" . unwrapped)
            BW_ReplaceSelection(unwrapped)
            return
        }

        ; unwrap 非該当で mapping に Open/Close があれば wrap
        if (mapping.Open != "") {
            BW_DebugLog("wrap_ime", "before=" . selText . " open=" . mapping.Open)
            BW_ReplaceSelection(mapping.Open . selText . mapping.Close)
            return
        }

        BW_SendChar(char)
        return
    }

    ; マッピングなし → 半角として処理
    BW_OnKey(char)
}

; ── wrap/unwrap ロジック ────────────────────────────────────

BW_OnKey_Symmetric(char, text) {
    if (BW_StrHasWrap(text, char, char)) {
        BW_DebugLog("unwrap_sym", "char=" . char)
        BW_ReplaceSelection(SubStr(text, 2, StrLen(text) - 2))
    } else {
        BW_DebugLog("wrap_sym", "char=" . char)
        BW_ReplaceSelection(char . text . char)
    }
}

BW_OnKey_Unwrap(char, text) {
    global BW_CloseToOpen
    open := BW_CloseToOpen[char]
    if (BW_StrHasWrap(text, open, char)) {
        BW_DebugLog("unwrap", "open=" . open . " close=" . char)
        BW_ReplaceSelection(SubStr(text, 2, StrLen(text) - 2))
    } else {
        BW_SendChar(char)
    }
}

BW_TryUnwrapAny(text) {
    global BW_CloseToOpen
    if (StrLen(text) < 2)
        return ""
    lastChar := SubStr(text, 0)
    if (BW_CloseToOpen.HasKey(lastChar)) {
        openChar := BW_CloseToOpen[lastChar]
        openLen := StrLen(openChar)
        closeLen := StrLen(lastChar)
        if (SubStr(text, 1, openLen) = openChar)
            return SubStr(text, openLen + 1, StrLen(text) - openLen - closeLen)
    }
    return ""
}

BW_StrHasWrap(text, prefix, suffix) {
    return (StrLen(text) >= 2
        && SubStr(text, 1, StrLen(prefix)) = prefix
        && SubStr(text, 0, StrLen(suffix)) = suffix)
}

; ── テキスト操作 ───────────────────────────────────────────

BW_ReplaceSelection(newText) {
    BW_DebugLog("replace", "len=" . StrLen(newText))
    prefix := Chr(123) . "Text" . Chr(125)
    SendInput, % prefix . newText
    Sleep, 30
    BW_ReselectInsertedText(StrLen(newText))
}

BW_ReselectInsertedText(length) {
    if (length < 1)
        return
    BW_DebugLog("reselect", "len=" . length)
    keys := "{Shift down}"
    Loop, %length%
        keys .= "{Left}"
    keys .= "{Shift up}"
    SendInput, % keys
}

BW_SendChar(char) {
    prefix := Chr(123) . "Text" . Chr(125)
    SendInput, % prefix . char
}

; ── Smart 行操作 ───────────────────────────────────────────

BW_SmartCopy() {
    if (BW_IsExcluded()) {
        SendInput, ^c
        return
    }
    Send, {Ctrl up}
    Clipboard := ""
    Send, {Home}+{End}^c{End}
    ClipWait, 0.3
    if (ErrorLevel) {
        BW_DebugLog("smart_copy_fail", "ClipWait timeout")
        return
    }
    Clipboard := RTrim(Clipboard, "`r`n")
    BW_DebugLog("smart_copy", "clip=[" . SubStr(Clipboard, 1, 40) . "]")
    UiaRequestRefresh()
}

BW_SmartCut() {
    if (BW_IsExcluded()) {
        SendInput, ^x
        return
    }
    Send, {Ctrl up}
    Clipboard := ""
    Send, {Home}+{Down}^x
    ClipWait, 0.3
    if (ErrorLevel) {
        BW_DebugLog("smart_cut_fail", "ClipWait timeout")
    }
    UiaRequestRefresh()
}

BW_SmartDuplicate() {
    if (BW_IsExcluded()) {
        SendInput, ^d
        return
    }
    Send, {Ctrl up}
    clipSaved := ClipboardAll
    Clipboard := ""
    Send, {Home}+{End}^c
    ClipWait, 0.3
    if (ErrorLevel) {
        BW_DebugLog("smart_dup_fail", "ClipWait timeout")
        Clipboard := clipSaved
        VarSetCapacity(clipSaved, 0)
        return
    }
    lineText := RTrim(Clipboard, "`r`n")
    Clipboard := "`r`n" . lineText
    BW_DebugLog("smart_dup", "line=[" . lineText . "] clip_len=" . StrLen(Clipboard))
    Send, {End}^v
    Sleep, 200
    Clipboard := clipSaved
    VarSetCapacity(clipSaved, 0)
    UiaRequestRefresh()
}

; ── デバッグ ───────────────────────────────────────────────

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

BW_DebugLog(event, extra := "") {
    global BW_DebugEnabled, BW_DebugLogPath
    if (!BW_DebugEnabled)
        return
    BW_DebugEnsureLogDir()
    BW_DebugRotateIfNeeded()
    FormatTime, stamp,, yyyy-MM-dd HH:mm:ss
    line := stamp . "." . A_MSec . " event=" . event
    if (extra != "")
        line .= " " . extra
    FileAppend, % line . "`n", %BW_DebugLogPath%, UTF-8
}
