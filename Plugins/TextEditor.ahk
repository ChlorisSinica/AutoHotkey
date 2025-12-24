LineCopyOrCut(cut := false) {
    ; 選択範囲があるかどうかを判定
    ClipSaved := ClipboardAll
    Clipboard := ""          ; クリップボードを一旦空に
    Send ^c                  ; 通常コピーを試みる
    ClipWait, 0.1
    if (Clipboard != "") {
        ; 選択範囲があった → 通常コピー／カット
        if (cut)
            Send ^x
        else
            Send ^c
    } else {
        ; 選択範囲がなかった → 行コピー／カット
        Send {Home}
        Send +{End}
        Send +{Right}        ; 改行まで含めたい場合
        if (cut)
            Send ^x
        else
            Send ^c
        Send {Right}{Left}   ; 選択解除
    }
    Clipboard := ClipSaved   ; クリップボードを元に戻す
    VarSetCapacity(ClipSaved, 0)
}



