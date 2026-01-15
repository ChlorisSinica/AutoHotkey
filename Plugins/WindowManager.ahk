; --- 計算メモ (基準: 3840 x 2088) ---
; X=1930 -> 0.503 (ほぼ画面半分より少し右)
; Y=430  -> 0.206
; W=1380 -> 0.360
; H=980  -> 0.470
; ------------------------------------

; ========================================================
; 関数群
; ========================================================

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

; アプリケーション起動ヘルパー
OpenMoveExplorer(path, xr, yr, wr, hr) {
    Run, explorer.exe "%path%"
    WinWaitActive, ahk_class CabinetWClass, , 3
    MoveWindowRatio("A", xr, yr, wr, hr)
}

OpenVSCode() {
    TargetID := WinExist("ahk_exe Code.exe")
    if TargetID {
        WinActivate, ahk_id %TargetID%
    } else {
        try {
            Run, code "%A_ScriptDir%"
        } catch {
            Run, "%A_AppData%\..\Local\Programs\Microsoft VS Code\Code.exe" "%A_ScriptDir%"
        }
        WinWaitActive, ahk_exe Code.exe, , 5
        TargetID := WinExist("A")
    }
    ; VSCodeも正規化比率で配置 (例: 右側メイン配置に近い設定)
    MoveWindowRatio("ahk_id " . TargetID, 0.503, 0.216, 0.404, 0.766)
}