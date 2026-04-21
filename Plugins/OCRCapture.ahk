; ==========================================================
; --- OCR Capture ---
; PrintWindow + Windows.Media.Ocr でダイアログ / 画面のテキスト抽出
; ==========================================================

OCR_Init() {
    Debug_CreateChannel("OCR"
        , A_ScriptDir . "\.claude\ocr_capture.log", 262144, true)
}

; ==========================================================
; --- Public: ウィンドウキャプチャ → OCR ---
; ==========================================================
OCR_CaptureAndRead() {
    hwnd := WinExist("A")
    if !hwnd {
        ToolTip, OCR: アクティブウィンドウなし
        SetTimer, CloseToolTip, -2000
        return
    }

    WinGetTitle, title, ahk_id %hwnd%
    WinGet, procName, ProcessName, ahk_id %hwnd%
    WinGetClass, className, ahk_id %hwnd%
    Debug_Log("OCR", "capture_start"
        , "hwnd=" . hwnd . " title=" . title . " proc=" . procName . " class=" . className)

    directText := OCR_TryReadDirectText(hwnd, title, procName, className)
    if (directText != "") {
        Debug_Log("OCR", "direct_text_success"
            , "hwnd=" . hwnd . " proc=" . procName . " class=" . className)
        OCR_FinalizeText("direct", hwnd, title, procName, directText)
        return
    }

    if !OCR_CaptureWindowToClipboard(hwnd) {
        Debug_Log("OCR", "capture_failed", "hwnd=" . hwnd)
        ToolTip, OCR: キャプチャ失敗
        SetTimer, CloseToolTip, -2000
        return
    }

    OCR_ProcessResult("capture", hwnd, title, procName)
}

; ==========================================================
; --- Public: クリップボード画像 → OCR ---
; ==========================================================
OCR_ReadClipboard() {
    hwnd := WinExist("A")
    WinGetTitle, title, ahk_id %hwnd%
    WinGet, procName, ProcessName, ahk_id %hwnd%
    Debug_Log("OCR", "clipboard_start"
        , "hwnd=" . hwnd . " title=" . title . " proc=" . procName)

    OCR_ProcessResult("clipboard", hwnd, title, procName)
}

; ==========================================================
; --- 内部: OCR 実行 + 結果処理 ---
; ==========================================================
OCR_ProcessResult(source, hwnd, title, procName) {
    outputPath := A_Temp . "\ahk_ocr_" . A_TickCount . ".txt"
    if FileExist(outputPath)
        FileDelete, %outputPath%

    exitCode := OCR_RunEngine(outputPath)

    if (exitCode = 1) {
        Debug_Log("OCR", "no_image", "source=" . source)
        ToolTip, OCR: クリップボードに画像なし
        SetTimer, CloseToolTip, -2000
        return
    }
    if (exitCode != 0) {
        Debug_Log("OCR", "engine_error", "source=" . source . " exit=" . exitCode)
        ToolTip, OCR: エンジンエラー (exit=%exitCode%)
        SetTimer, CloseToolTip, -2000
        return
    }

    FileRead, ocrText, %outputPath%
    FileDelete, %outputPath%
    OCR_FinalizeText(source, hwnd, title, procName, ocrText)
}

OCR_FinalizeText(source, hwnd, title, procName, ByRef rawText) {
    text := OCR_NormalizeText(rawText)
    if (text = "") {
        Debug_Log("OCR", "empty_result", "source=" . source)
        ToolTip, OCR: テキストなし
        SetTimer, CloseToolTip, -2000
        return false
    }

    charCount := StrLen(text)
    lineCount := 1
    Loop, Parse, text, `n, `r
        lineCount := A_Index

    Debug_Log("OCR", "text_success"
        , "source=" . source . " hwnd=" . hwnd
        . " proc=" . procName . " chars=" . charCount
        . " lines=" . lineCount)

    OCR_WriteHistory(source, hwnd, title, procName, text)

    if !ClipboardWrite(text) {
        Debug_Log("OCR", "clipboard_write_failed", "source=" . source)
        ToolTip, OCR: クリップボード書き込み失敗
        SetTimer, CloseToolTip, -2000
        return false
    }

    ToolTip, % "OCR: " . lineCount . " 行 / " . charCount . " 文字"
    SetTimer, CloseToolTip, -3000
    return true
}

; ==========================================================
; --- 内部: PrintWindow → クリップボード ---
; ==========================================================
OCR_CaptureWindowToClipboard(hwnd) {
    VarSetCapacity(rc, 16, 0)
    DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", &rc)
    w := NumGet(rc, 8, "Int") - NumGet(rc, 0, "Int")
    h := NumGet(rc, 12, "Int") - NumGet(rc, 4, "Int")
    if (w <= 0 || h <= 0)
        return false

    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    memDC := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
    hBmp := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
    old := DllCall("SelectObject", "Ptr", memDC, "Ptr", hBmp, "Ptr")

    ; PW_RENDERFULLCONTENT = 2 (DWM 対応)
    pwOk := DllCall("PrintWindow", "Ptr", hwnd, "Ptr", memDC, "UInt", 2)

    DllCall("SelectObject", "Ptr", memDC, "Ptr", old)
    DllCall("DeleteDC", "Ptr", memDC)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)

    if !pwOk {
        DllCall("DeleteObject", "Ptr", hBmp)
        return false
    }

    ; SetClipboardData 後はシステムが hBmp を所有する
    if !DllCall("OpenClipboard", "Ptr", 0) {
        DllCall("DeleteObject", "Ptr", hBmp)
        return false
    }
    DllCall("EmptyClipboard")
    result := DllCall("SetClipboardData", "UInt", 2, "Ptr", hBmp)
    DllCall("CloseClipboard")
    if !result
        DllCall("DeleteObject", "Ptr", hBmp)
    return (result != 0)
}

OCR_TryReadDirectText(hwnd, title, procName, className) {
    if !OCR_ShouldPreferDirectText(className, procName)
        return ""

    WinGetText, winText, ahk_id %hwnd%
    winText := OCR_NormalizeText(winText)
    if (winText != "")
        return winText

    controlDump := OCR_GetControlTextDump(hwnd)
    return OCR_NormalizeText(controlDump)
}

OCR_ShouldPreferDirectText(className, procName) {
    if (className = "#32770")
        return true
    if (procName = "AutoHotkeyU64.exe" || procName = "AutoHotkey.exe")
        return true
    return false
}

OCR_GetControlTextDump(hwnd) {
    out := ""
    WinGet, controlList, ControlList, ahk_id %hwnd%
    Loop, Parse, controlList, `n, `r
    {
        ctrl := A_LoopField
        if (ctrl = "")
            continue

        ControlGetText, ctrlText, %ctrl%, ahk_id %hwnd%
        ctrlText := OCR_NormalizeText(ctrlText)
        if (ctrlText = "")
            continue

        if (out != "")
            out .= "`r`n"
        out .= ctrlText
    }
    return out
}

OCR_NormalizeText(ByRef text) {
    normalized := RegExReplace(text, "\R", "`r`n")
    normalized := RegExReplace(normalized, "[\t ]+`r`n", "`r`n")
    normalized := RegExReplace(normalized, "(`r`n){3,}", "`r`n`r`n")
    return Trim(normalized, "`r`n`t ")
}

; ==========================================================
; --- 内部: PowerShell OCR 呼び出し ---
; ==========================================================
OCR_RunEngine(outputPath) {
    scriptPath := A_ScriptDir . "\Plugins\OCRCapture\ocr_clipboard.ps1"
    if !FileExist(scriptPath) {
        Debug_Log("OCR", "script_not_found", "path=" . scriptPath)
        return -1
    }

    psExe := A_WinDir . "\System32\WindowsPowerShell\v1.0\powershell.exe"
    runCmd := Chr(34) . psExe . Chr(34)
        . " -NoProfile -STA -ExecutionPolicy Bypass -File "
        . Chr(34) . scriptPath . Chr(34)
        . " " . Chr(34) . outputPath . Chr(34)

    return OCR_RunProcessSilent(runCmd, 15000)
}

; ==========================================================
; --- 内部: CREATE_NO_WINDOW + WaitForSingleObject ---
; ==========================================================
OCR_RunProcessSilent(cmd, timeoutMs := 10000) {
    static CREATE_NO_WINDOW := 0x08000000
    siSize := A_PtrSize = 8 ? 104 : 68
    piSize := 8 + 2 * A_PtrSize

    VarSetCapacity(SI, siSize, 0)
    NumPut(siSize, SI, 0, "UInt")
    VarSetCapacity(PI, piSize, 0)

    ok := DllCall("CreateProcessW"
        , "Ptr", 0, "WStr", cmd
        , "Ptr", 0, "Ptr", 0, "Int", 0
        , "UInt", CREATE_NO_WINDOW
        , "Ptr", 0, "Ptr", 0
        , "Ptr", &SI, "Ptr", &PI)
    if (!ok)
        return -1

    hProcess := NumGet(PI, 0, "Ptr")
    hThread := NumGet(PI, A_PtrSize, "Ptr")
    DllCall("CloseHandle", "Ptr", hThread)

    waitResult := DllCall("WaitForSingleObject", "Ptr", hProcess, "UInt", timeoutMs, "UInt")
    if (waitResult != 0) {
        ; WAIT_TIMEOUT or error — terminate orphaned child
        DllCall("TerminateProcess", "Ptr", hProcess, "UInt", 1)
        DllCall("CloseHandle", "Ptr", hProcess)
        return -1
    }

    exitCode := 0
    DllCall("GetExitCodeProcess", "Ptr", hProcess, "UInt*", exitCode)
    DllCall("CloseHandle", "Ptr", hProcess)
    return exitCode
}

; ==========================================================
; --- 内部: 履歴ファイル書き出し ---
; ==========================================================
OCR_WriteHistory(source, hwnd, title, procName, ByRef ocrText) {
    historyDir := A_ScriptDir . "\.claude\ocr_history"
    if !InStr(FileExist(historyDir), "D")
        FileCreateDir, %historyDir%

    FormatTime, stamp,, yyyyMMdd-HHmmss
    filePath := historyDir . "\" . stamp . ".txt"

    FormatTime, readableStamp,, yyyy-MM-dd HH:mm:ss
    header := "CapturedAt: " . readableStamp . "." . A_MSec
        . "`nSource: " . source
        . "`nHWND: " . hwnd
        . "`nWindow: " . title
        . "`nProcess: " . procName
        . "`n---`n"

    FileAppend, % header . ocrText . "`n", %filePath%, UTF-8

    ; latest.txt も更新
    latestPath := historyDir . "\latest.txt"
    if FileExist(latestPath)
        FileDelete, %latestPath%
    FileAppend, % header . ocrText . "`n", %latestPath%, UTF-8
}
