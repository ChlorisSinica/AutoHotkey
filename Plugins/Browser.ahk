global KeyActions := {}
KeyActions["F1"] := {}
KeyActions["F1"]["x.com"]             := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["youtube.com"]       := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["instagram.com"]     := Func("SaveCookiesCurrentSite")
KeyActions["F1"]["music.youtube.com"] := Func("SaveCookiesCurrentSite")

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
        Clipboard := ClipSaved
        return
    }

    ; 変数経由で書き戻すことで、HTML情報を削除してテキストのみにする
    UrlText := Clipboard
    Clipboard := ""
    Clipboard := UrlText

    ClipSaved := ""
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
TogglePDFZoom() {
    ; UIA初期化
    UIA := UIA_Interface()
    if (!UIA)
        return

    ; ウィンドウ要素取得
    try {
        el := UIA.ElementFromHandle(WinExist("A"))
    } catch {
        return
    }

    ; --- 検索対象のIDリスト ---
    ; 1. pagefit (ダンプ画像で確認済み: 現在が「幅に合わせる」状態のときに出現)
    ; 2. fit-to-width (標準的なID: 現在が「ページに合わせる」状態のときに出現すると推測)
    ; 3. widthfit (pagefitの命名規則からの推測)
    targetIDs := ["pagefit", "fit-to-width", "widthfit"]

    btn := ""

    ; IDリストを順に検索し、見つかったボタンを押す
    for index, id in targetIDs {
        btn := el.FindFirstBy("AutomationId=" . id)
        if (btn)
            break ; 見つかったらループを抜ける
    }

    ; IDで見つからない場合、Name（日本語名）で検索するバックアップ処理
    ; 「Ctrl+\」というショートカットキー表記が名前に含まれているボタンを探す
    if (!btn) {
        cond1 := UIA.CreatePropertyCondition("Name", "ページに合わせる (Ctrl+\)")
        cond2 := UIA.CreatePropertyCondition("Name", "幅に合わせる (Ctrl+\)")
        condOr := UIA.CreateOrCondition(cond1, cond2)

        btn := el.FindFirst(condOr)
    }

    ; 実行
    if (btn) {
        try {
            btn.Invoke()
        } catch {
            ; Invokeがダメな場合の予備
            try {
                btn.Click()
            }
        }
    } else {
        ; ボタンが見つからない場合 (ツールバーが隠れている等)
        ToolTip, PDF操作ボタンが見つかりません
        SetTimer, CloseToolTip, -2000
    }

    ; --- 【修正案：マウス移動なしのフォーカス復帰】 ---
    Sleep, 100

    try {
        ; まず要素(RootWebArea)を取得
        docEl := el.FindFirstBy("AutomationId=RootWebArea")
        if (!docEl)
            docEl := el.FindFirstBy("ControlType=50030")

        if (docEl) {
            ; 方法A: LegacyIAccessibleパターン経由でのフォーカス (マウス不要)
            try {
                ; "LegacyIAccessible" パターンを取得
                legacy := docEl.GetCurrentPatternAs("LegacyIAccessible")

                if (legacy) {
                    ; 0x1 は "TakeFocus" (フォーカスを取得せよ) というフラグです
                    legacy.Select(1)
                    Send, {Tab}+{Tab}{F6}{Esc}
                    return ; 成功したらここで終了
                }
            } catch {
                ; レガシーパターン取得失敗時は次へ
            }
        }
    } catch e {
        ; エラー処理
    }
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
    targetDir := "C:\myApp\__temp__"
    targetPath := targetDir . "\urls.txt"

    ; フォルダがない場合は作成
    if !InStr(FileExist(targetDir), "D") {
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