; ----------------------------------------------------------
; 汎用ヘルパー: キーワードを含み、かつ除外ワードを含まない要素を探す
; 引数:
;   keywords: 検索したい文字の配列 (OR条件) ["A", "B"]
;   excludeKeywords: 除外したい文字の配列 (OR条件) ["X", "Y"] (省略可)
; ----------------------------------------------------------
FindElementByKeyword(parentEl, keywords, excludeKeywords := "") {
    condTrue := parentEl.UIA.CreateTrueCondition()
    elements := parentEl.FindAll(condTrue)

    Loop % elements.MaxIndex() {
        el := elements[A_Index]
        name := el.CurrentName

        ; --- 除外チェック ---
        isExcluded := false
        if (IsObject(excludeKeywords)) {
            for i, ex in excludeKeywords {
                if (InStr(name, ex)) {
                    isExcluded := true
                    break ; 除外ワードが見つかったらこの要素はスキップ
                }
            }
        }
        if (isExcluded)
            continue ; 次の要素へ

        ; --- ヒットチェック ---
        for i, k in keywords {
            if (InStr(name, k)) {
                return el ; 合致した要素を返す
            }
        }
    }
    return ""
}

; 既存のヘルパー関数（もし cBrowser に FindFirstByNameAndType が無い場合の保険）
if (!IsFunc(UIA_Browser.FindFirstByNameAndType)) {
    UIA_Browser.FindFirstByNameAndType := Func("My_FindFirstByNameAndType")
}

My_FindFirstByNameAndType(this, name, type) {
    ; 簡易実装: type引数は今回はButton決め打ち等のため省略し、Nameだけで探す例
    return this.FindFirstByName(name)
}