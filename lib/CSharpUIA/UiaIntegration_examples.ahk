; ═══════════════════════════════════════════════════════════════
; UiaIntegration_examples.ahk — ホットキー実装例（参考コード）
;
; このファイルは #Include しないでください。
; UiaIntegration.ahk の関数を使ったホットキーの実装例です。
; 実際の使用時は main.ahk のホットキーセクションに移植してください。
; ═══════════════════════════════════════════════════════════════

; ── 括弧囲み ────────────────────────────────────────────────
; 選択中 → 選択テキストを括弧で囲む
; 未選択（テキスト欄） → 括弧ペアを入力してカーソルを中へ
; テキスト欄外 → 何もしない（キーをそのまま通す）
;
; main.ahk での使用例:
;   #If (EnableBracketWrap)
;   $+9::
;       UiaGetState(isEd, hasSel)
;       if (!isEd) {
;           Send, (
;           return
;       }
;       if (hasSel)
;           Example_WrapSelection("(", ")")
;       else
;           Example_InsertPair("(", ")")
;       return
;   #If

Example_WrapSelection(openChar, closeChar) {
    clipSaved := ClipboardAll
    Clipboard := ""
    Send, ^x
    ClipWait, 1
    if (ErrorLevel) {
        Clipboard := clipSaved
        return
    }
    selected := Clipboard
    Clipboard := openChar . selected . closeChar
    Send, ^v
    Sleep, 50
    Clipboard := clipSaved
}

Example_InsertPair(openChar, closeChar) {
    SendInput, %openChar%%closeChar%{Left}
}

; ── 行コピー ────────────────────────────────────────────────
; main.ahk での使用例:
;   $^+c::
;       UiaGetState(isEd, hasSel)
;       if (!isEd) {
;           Send, ^+c
;           return
;       }
;       if (hasSel)
;           Send, ^c
;       else
;           Example_LineCopy()
;       return

Example_LineCopy() {
    Send, {Home}
    Send, +{End}
    Send, ^c
    Send, {End}
}

Example_LineCut() {
    Send, {Home}
    Send, +{Down}
    Send, ^x
}

Example_LineDuplicate() {
    clipSaved := ClipboardAll
    Clipboard := ""
    Send, {Home}
    Send, +{End}
    Send, ^c
    ClipWait, 1
    if (ErrorLevel) {
        Clipboard := clipSaved
        return
    }
    lineText := Clipboard
    Send, {End}
    Send, {Enter}
    Clipboard := lineText
    Send, ^v
    Sleep, 50
    Clipboard := clipSaved
}

Example_DuplicateSelection() {
    clipSaved := ClipboardAll
    Clipboard := ""
    Send, ^c
    ClipWait, 1
    if (ErrorLevel) {
        Clipboard := clipSaved
        return
    }
    Send, {Right}
    Send, ^v
    Sleep, 50
    Clipboard := clipSaved
}
