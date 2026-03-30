OutputFileName := "C:\myApp\Cookies\auth.json"
global SaveDir := "C:\myApp\Cookies"

get_auth(cBrowser) {
    ; ============================================================
    ; 2. 関数内で外の変数を使うために global 宣言を追加
    ; ============================================================
    global OutputFileName

    ; 保存先のフォルダが存在しないとエラーになるため、フォルダを作成する処理を追加（推奨）
    SplitPath, OutputFileName, , OutDir
    if (OutDir != "" && !InStr(FileExist(OutDir), "D"))
        FileCreateDir, %OutDir%

    ; --- 以下、既存の処理 ---
    ClipSaved := ClipboardAll

    WinGetTitle, CurrentTitle, A
    Send, ^+j
    Sleep, 2000

    JsCommand = copy(JSON.stringify({ "User-Agent": navigator.userAgent, "Cookie": document.cookie }));

    Send, {Text}%JsCommand%
    Sleep, 100
    Send, {Enter}

    Clipboard := ""
    ClipWait, 2
    if ErrorLevel
    {
        ClipboardWrite(ClipSaved)
        ClipSaved =
        MsgBox, データの取得に失敗しました。
        return
    }

    AuthData := Clipboard
    Send, ^+j

    if FileExist(OutputFileName)
        FileDelete, %OutputFileName%
    FileAppend, %AuthData%, %OutputFileName%, UTF-8

    ClipboardWrite(ClipSaved)
    ClipSaved =

    MsgBox, 成功！認証情報を保存しました。`n保存先: %OutputFileName%
}

get_auth_debug(cBrowser) {
    ; ============================================================
    ; デバッグ用関数も同様に修正が必要です
    ; ============================================================
    global OutputFileName  ; ★ここも追加

    ClipSaved := ClipboardAll
    WinGetTitle, CurrentTitle, A
    Send, ^+j
    Sleep, 3000
    Send, ^l
    Sleep, 500

    JsCommand = copy(JSON.stringify({ "User-Agent": navigator.userAgent, "Cookie": document.cookie }));

    Clipboard := ""
    Send, {Text}%JsCommand%
    Sleep, 500

    MsgBox, 4, 目視確認,
    (
    画面を見てください。
    開発者ツールのコンソール(入力欄)に、
    「copy(JSON.stringify...」 という文字が入力されていますか？
    )

    IfMsgBox No
    {
        Send, ^+j
        return
    }

    Send, {Enter}

    ClipWait, 3
    if ErrorLevel
    {
        MsgBox, エラー: クリップボードに来ませんでした。
        ClipboardWrite(ClipSaved)
        return
    }

    AuthData := Clipboard
    Send, ^+j

    ; ============================================================
    ; ★元コードでは "auth.json" と直書きされていた部分を変数に変更
    ; ============================================================
    if FileExist(OutputFileName)
        FileDelete, %OutputFileName%
    FileAppend, %AuthData%, %OutputFileName%, UTF-8

    ClipboardWrite(ClipSaved)
    ClipSaved =
    MsgBox, 成功！ %OutputFileName% を作成しました。
}

; ============================================================
; 関数定義
; ============================================================
SaveCookiesCurrentSite(cBrowser, currentUrl) {
    global SaveDir

    ; --- 設定・引数チェック ---
    if (SaveDir == "") {
        MsgBox, 16, 設定エラー, SaveDirが設定されていません。
        return
    }
    if (currentUrl == "") {
        MsgBox, 16, エラー, URLが正しく渡されていません。
        return
    }
    if !FileExist(SaveDir)
        FileCreateDir, %SaveDir%

    ; --- ファイル名生成 ---
    domainName := "unknown"
    if RegExMatch(currentUrl, "O)https?:\/\/(?:www\.)?([^\/:]+)", match)
        domainName := match.Value(1)

    ; ファイル名に使えない文字を置換
    domainName := RegExReplace(domainName, "[\\/:*?""<>|]", "_")
    fileName := domainName . ".txt"
    fullPath := SaveDir . "\" . fileName

    ; --- ブラウザ操作 ---
    if !WinActive("ahk_id " . cBrowser.BrowserId)
        WinActivate, % "ahk_id " . cBrowser.BrowserId

    ; 拡張機能を開く (Shift+Alt+6)
    Send, +!6
    Sleep, 1500 ; 描画待ち

    try {
        hwndPopup := WinExist("A")
        ControlGet, hwndRender, Hwnd, , Chrome_RenderWidgetHostHWND1, ahk_id %hwndPopup%
        targetHwnd := (hwndRender ? hwndRender : hwndPopup)

        el := cBrowser.UIA.ElementFromHandle(targetHwnd)
        buttons := el.FindAll("ControlType=Button")

        targetBtn := ""
        Loop % buttons.MaxIndex() {
            if InStr(buttons[A_Index].CurrentName, "Copy") {
                targetBtn := buttons[A_Index]
                break
            }
        }
        if (!targetBtn && buttons.MaxIndex() >= 3)
            targetBtn := buttons[3]

        if (!targetBtn) {
            MsgBox, 16, エラー, Copyボタンが見つかりませんでした
            Send, {Esc}
            return
        }

        ; --- クリップボード取得 ---
        ClipSaved := ClipboardAll
        Clipboard := ""

        targetBtn.Click()
        ClipWait, 3

        if (ErrorLevel || StrLen(Clipboard) == 0) {
            MsgBox, 16, エラー, データの取得に失敗しました
            ClipboardWrite(ClipSaved)
            Send, {Esc}
            return
        }

        rawContent := Clipboard
        ClipboardWrite(ClipSaved)
        Send, {Esc} ; ポップアップを閉じる

        ; ========================================================
        ; ★データ整形プロセス (gallery-dl対策)
        ; ========================================================

        finalContent := ""

        Loop, Parse, rawContent, `n, `r
        {
            line := A_LoopField
            if (line == "")
                continue

            ; ヘッダー行はそのまま
            if (SubStr(line, 1, 1) == "#") {
                finalContent .= line . "`n"
                continue
            }

            ; データ行: 連続するスペースをタブに変換して構造を修復
            ; (最初の6つの区切りをタブにする)
            if RegExMatch(line, "^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(.*)$", m) {
                line := m1 . "`t" . m2 . "`t" . m3 . "`t" . m4 . "`t" . m5 . "`t" . m6 . "`t" . m7
            }

            finalContent .= line . "`n"
        }

        ; ヘッダー補完
        if !InStr(finalContent, "# Netscape HTTP Cookie File") {
            finalContent := "# Netscape HTTP Cookie File`n# This file is generated by AHK`n`n" . finalContent
        }

        ; ========================================================
        ; ★保存処理 (BOMなしUTF-8)
        ; ========================================================

        fileObj := FileOpen(fullPath, "w", "UTF-8-RAW")
        if !fileObj {
            MsgBox, 16, エラー, % "保存に失敗しました。パスを確認してください:`n" . fullPath
            return
        }
        fileObj.Write(finalContent)
        fileObj.Close()

        ; --- 保存確認 (元の仕様に戻しました) ---
        if FileExist(fullPath) {
            FileGetSize, fSize, %fullPath%
            MsgBox, 64, 完了, % "保存完了！`nファイル: " . fileName . "`nサイズ: " . fSize . " bytes"
        } else {
            MsgBox, 16, 警告, % "保存処理は完了しましたが、ファイルが見つかりません。`n" . fullPath
        }

    } catch e {
        MsgBox, 16, エラー, % "例外エラー: " . e.Message
    }
}

; ==========================================================
; 汎用関数: IMEを強制的にOFFにする
; ==========================================================
EnsureImeOff() {
    ; ウィンドウメッセージでIMEをOFF(無変換/英数モード)にする
    ; 0x0283 = WM_IME_CONTROL, 0x002 = IMC_SETOPENSTATUS, 0 = OFF
    PostMessage, 0x0283, 0x002, 0,, A
}
