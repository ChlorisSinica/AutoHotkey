; ========================================================
; 関数群
; =======================================================

MoveWindow(targetTitle, x, y, w, h) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel) {
            return
        }
    }
    WinMove, %targetTitle%,, x, y, w, h
}

; ピクセル指定移動 (見た目のズレ補正付き)
MoveWindowPixel(hwnd, x, y, w, h) {
    ; 現在の論理座標
    WinGetPos, lx, ly, lw, lh, ahk_id %hwnd%

    ; 見た目の座標を取得してオフセット計算
    VarSetCapacity(rect, 16, 0)
    hr := DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 9, "Ptr", &rect, "UInt", 16)

    if (hr = 0) {
        vx := NumGet(rect, 0, "Int"), vy := NumGet(rect, 4, "Int")
        vr := NumGet(rect, 8, "Int"), vb := NumGet(rect, 12, "Int")
        vw := vr - vx, vh := vb - vy

        ; 補正値を計算
        offsetX := vx - lx
        offsetY := vy - ly
        offsetW := vw - lw
        offsetH := vh - lh

        ; 補正値を適用
        x -= offsetX
        y -= offsetY
        w -= offsetW
        h -= offsetH
    }

    WinMove, ahk_id %hwnd%,, x, y, w, h
}

; 比率(0.0～1.0)でウィンドウを移動する関数
MoveWindowRatio(targetTitle, xRatio, yRatio, wRatio, hRatio) {
    if (targetTitle != "A") {
        WinWaitActive, %targetTitle%, , 2
        if (ErrorLevel)
            return
    }

    WinGet, hwnd, ID, %targetTitle%
    if !hwnd
        return

    ; ★重要: ウィンドウが現在あるモニターの作業領域を取得
    GetMonitorWorkAreaFromWindow(hwnd, WL, WT, WW, WH)

    ; 比率からピクセル値を計算
    finalX := WL + (WW * xRatio)
    finalY := WT + (WH * yRatio)
    finalW := WW * wRatio
    finalH := WH * hRatio

    ; ピクセル計算結果を使って移動 (DWM補正付き)
    MoveWindowPixel(hwnd, finalX, finalY, finalW, finalH)
}

; ========================================================
; アプリ名・座標・比率を一括取得
; ========================================================
GetActiveWindowInfo() {
    ; 1. 基本情報の取得
    WinGet, processName, ProcessName, A
    WinGetTitle, title, A
    WinGet, hwnd, ID, A

    ; 2. ピクセル座標の取得 (DWM補正付き)
    GetVisibleWindowPos(x, y, w, h, "A")

    ; 3. 比率の計算 (GetActiveWindowPosRatioのロジック)
    GetMonitorWorkAreaFromWindow(hwnd, MonLeft, MonTop, MonWidth, MonHeight)
    rx := (x - MonLeft) / MonWidth
    ry := (y - MonTop)  / MonHeight
    rw := w / MonWidth
    rh := h / MonHeight

    ; 4. 結果の整形
    ; 設定ファイル用にそのまま貼れるコマンド文字列
    ratioCommand := Format("MoveWindowRatio(""A"", {:.3f}, {:.3f}, {:.3f}, {:.3f})", rx, ry, rw, rh)

    infoText := "【プロセス名】 " . processName . "`n"
        .  "【タイトル】 " . title . "`n"
        .  "【ピクセル座標】 X=" . x . " Y=" . y . " W=" . w . " H=" . h . "`n"
        .  "--------------------------------------------------`n"
        .  "【比率コマンド (クリップボードにコピー済)】`n" . ratioCommand

    ; 5. 出力
    Clipboard := ratioCommand
    MsgBox, 64, ウィンドウ情報解析, %infoText%
}

ShowMonitorInfo() {
    Output := ""

    ; モニターの総数を取得
    SysGet, MonCount, MonitorCount
    ; メインモニターの番号を取得
    SysGet, PrimMon, MonitorPrimary

    Output .= "検出されたモニター数: " . MonCount . "`n`n"

    Loop, %MonCount% {
        ; --- 1. モニター全体の解像度を取得 (Monitor) ---
        SysGet, Mon, Monitor, %A_Index%
        MonWidth  := MonRight - MonLeft
        MonHeight := MonBottom - MonTop

        ; --- 2. 作業領域を取得 (MonitorWorkArea) ---
        ; タスクバーを除いた、ウィンドウを最大化したときのサイズ
        SysGet, Work, MonitorWorkArea, %A_Index%
        WorkWidth  := WorkRight - WorkLeft
        WorkHeight := WorkBottom - WorkTop

        ; メインモニターかどうかの判定
        IsPrimary := (A_Index = PrimMon) ? " ★メインモニター" : ""

        ; --- 出力テキストの作成 ---
        Output .= "---------------------------------------`n"
        Output .= "モニター番号: " . A_Index . IsPrimary . "`n"
        Output .= "---------------------------------------`n"

        Output .= "[全体解像度]`n"
        Output .= "  サイズ: " . MonWidth . " x " . MonHeight . "`n"
        Output .= "  座標  : Left=" . MonLeft . ", Top=" . MonTop . ", Right=" . MonRight . ", Bottom=" . MonBottom . "`n`n"

        Output .= "[作業領域 (WorkArea)]`n"
        Output .= "  サイズ: " . WorkWidth . " x " . WorkHeight . "`n"
        Output .= "  座標  : Left=" . WorkLeft . ", Top=" . WorkTop . ", Right=" . WorkRight . ", Bottom=" . WorkBottom . "`n`n"
    }

    MsgBox, 0, モニター情報一覧, %Output%
}

GetVisibleWindowPos(ByRef X, ByRef Y, ByRef Width, ByRef Height, WinTitle := "A") {
    ; 対象ウィンドウのハンドル(ID)を取得
    WinGet, hwnd, ID, %WinTitle%
    if !hwnd
        return

    ; RECT構造体のためのメモリ確保 (4バイト整数 x 4 = 16バイト)
    VarSetCapacity(rect, 16, 0)

    ; DWMWA_EXTENDED_FRAME_BOUNDS = 9
    ; 成功すると 0 (S_OK) が返る
    hr := DllCall("dwmapi\DwmGetWindowAttribute"
        , "Ptr",  hwnd
        , "UInt", 9
        , "Ptr",  &rect
        , "UInt", 16)

    if (hr = 0) {
        ; --- 成功時: DWMから取得した「見た目の座標」を使用 ---
        X := NumGet(rect, 0, "Int")      ; Left
        Y := NumGet(rect, 4, "Int")      ; Top
        R := NumGet(rect, 8, "Int")      ; Right
        B := NumGet(rect, 12, "Int")     ; Bottom

        Width  := R - X
        Height := B - Y
    } else {
        ; --- 失敗時（DWM非対応など）: 通常のWinGetPosで代用 ---
        WinGetPos, X, Y, Width, Height, ahk_id %hwnd%
    }
}

; 補助関数: ウィンドウハンドルからモニターハンドルを取得（今回は簡易ロジックで代用したので未使用でも可）
GetMonitorHandleFromWindow(hwnd) {
    ; Windows API: MonitorFromWindow
    return DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2) ; 2=MONITOR_DEFAULTTONEAREST
}

; 指定ウィンドウが含まれるモニターの作業領域を取得
GetMonitorWorkAreaFromWindow(hwnd, ByRef Left, ByRef Top, ByRef Width, ByRef Height) {
    WinGetPos, x, y, w, h, ahk_id %hwnd%
    cx := x + (w / 2)
    cy := y + (h / 2)

    SysGet, MonCount, MonitorCount

    ; 見つからなかった場合のデフォルト（プライマリ）
    SysGet, Mon, MonitorWorkArea, 1
    MonLeft := MonLeft, MonRight := MonRight, MonTop := MonTop, MonBottom := MonBottom

    Loop, %MonCount% {
        SysGet, tmp, MonitorWorkArea, %A_Index%
        ; ウィンドウの中心点がそのモニター内にあるか判定
        if (cx >= tmpLeft && cx <= tmpRight && cy >= tmpTop && cy <= tmpBottom) {
            MonLeft := tmpLeft
            MonRight := tmpRight
            MonTop := tmpTop
            MonBottom := tmpBottom
            break
        }
    }

    Left := MonLeft
    Top := MonTop
    Width := MonRight - MonLeft
    Height := MonBottom - MonTop
}
