; ═══════════════════════════════════════════════════════════════
; UiaIntegration.ahk — UIA 監視プロセス連携ライブラリ (AHK v1.1)
;
; 使い方:
;   #Include <UiaIntegration>
;   UiaInit()                          ; main.ahk の初期化セクションで呼ぶ
;   OnExit("UiaCleanup")              ; main.ahk で登録
;
; 公開関数:
;   UiaInit()              ; 監視プロセス起動 + 共有メモリ接続
;   UiaCleanup()           ; 共有メモリ解放 + 監視プロセス停止
;   UiaIsEditable()        ; 0 or 1
;   UiaHasSelection()      ; 0 or 1
;   UiaControlType()       ; 0=Edit, 1=RichEdit, 2=Document, 3=Browser, 0xFF=Unknown
;   UiaProcessId()         ; PID
;   UiaGetState(ByRef, ByRef, ByRef)  ; 一括取得
; ═══════════════════════════════════════════════════════════════

; ── 設定 ──────────────────────────────────────────────────────
; UiaMonitor.exe のパス（環境に合わせて変更）
global UIA_MONITOR_EXE := A_ScriptDir . "\lib\UiaMonitor\UiaMonitor\UiaMonitor.exe"

; 共有メモリ名（C# 側と一致させること）
global UIA_MMF_NAME := "AhkUiaState"

; 共有メモリハンドル
global hMapFile := 0
global pBuf := 0

; ═══════════════════════════════════════════════════════════════
; コア機能
; ═══════════════════════════════════════════════════════════════

UiaInit() {
    if !UiaStartMonitor()
        return

    Sleep, 500  ; 起動待ち
    UiaOpenSharedMemory()
}

UiaStartMonitor() {
    global UIA_MONITOR_EXE

    Process, Exist, UiaMonitor.exe
    if (ErrorLevel != 0)
        return true

    if !FileExist(UIA_MONITOR_EXE)
        return false

    Run, %UIA_MONITOR_EXE%, , Hide
    return true
}

UiaOpenSharedMemory() {
    global UIA_MMF_NAME, hMapFile, pBuf

    ; FILE_MAP_READ = 0x0004
    hMapFile := DllCall("OpenFileMapping"
        , "UInt", 0x0004    ; dwDesiredAccess = FILE_MAP_READ
        , "Int",  0         ; bInheritHandle
        , "Str",  UIA_MMF_NAME
        , "Ptr")

    if (!hMapFile) {
        ; リトライ（プロセス起動直後は共有メモリがまだない場合がある）
        Loop, 10 {
            Sleep, 200
            hMapFile := DllCall("OpenFileMapping"
                , "UInt", 0x0004
                , "Int",  0
                , "Str",  UIA_MMF_NAME
                , "Ptr")
            if (hMapFile)
                break
        }
        if (!hMapFile) {
            ; 共有メモリが開けない場合はサイレントに失敗（機能無効状態で続行）
            return
        }
    }

    ; FILE_MAP_READ = 0x0004
    pBuf := DllCall("MapViewOfFile"
        , "Ptr",  hMapFile
        , "UInt", 0x0004    ; dwDesiredAccess
        , "UInt", 0         ; dwFileOffsetHigh
        , "UInt", 0         ; dwFileOffsetLow
        , "UInt", 16        ; dwNumberOfBytesToMap
        , "Ptr")

    if (!pBuf) {
        DllCall("CloseHandle", "Ptr", hMapFile)
        hMapFile := 0
    }
}

; ── 状態読取り関数 ──────────────────────────────────────────

; テキスト編集可能欄にいるか（0 or 1）
UiaIsEditable() {
    global pBuf
    if (!pBuf)
        return 0
    return NumGet(pBuf + 0, 0, "UChar")
}

; テキスト選択中か（0 or 1）
UiaHasSelection() {
    global pBuf
    if (!pBuf)
        return 0
    return NumGet(pBuf + 1, 0, "UChar")
}

; コントロール種別（0=Edit, 1=RichEdit, 2=Document, 3=Browser, 0xFF=Unknown）
UiaControlType() {
    global pBuf
    if (!pBuf)
        return 0xFF
    return NumGet(pBuf + 2, 0, "UChar")
}

; フォーカス先プロセスID
UiaProcessId() {
    global pBuf
    if (!pBuf)
        return 0
    return NumGet(pBuf + 4, 0, "UInt")
}

; 一括取得（参照渡し）
UiaGetState(ByRef isEditable, ByRef hasSelection, ByRef controlType := 0) {
    global pBuf
    if (!pBuf) {
        isEditable := 0
        hasSelection := 0
        controlType := 0xFF
        return
    }
    isEditable   := NumGet(pBuf + 0, 0, "UChar")
    hasSelection := NumGet(pBuf + 1, 0, "UChar")
    controlType  := NumGet(pBuf + 2, 0, "UChar")
}

; ── クリーンアップ ───────────────────────────────────────────

UiaCleanup(ExitReason := "", ExitCode := 0) {
    global hMapFile, pBuf, UIA_MMF_NAME

    ; 共有メモリ解放
    if (pBuf) {
        DllCall("UnmapViewOfFile", "Ptr", pBuf)
        pBuf := 0
    }

    ; シャットダウンシグナル経由で正常終了を試みる
    UiaSendShutdownSignal()

    if (hMapFile) {
        DllCall("CloseHandle", "Ptr", hMapFile)
        hMapFile := 0
    }

    ; 猶予を与えてからプロセス確認
    Sleep, 800
    Process, Exist, UiaMonitor.exe
    if (ErrorLevel != 0) {
        ; シャットダウンシグナルで終了しなかった場合のみ強制終了
        Process, Close, UiaMonitor.exe
    }
}

; 共有メモリ Offset 9 に再チェック要求を書込み
; Smart 行操作後に呼出し → C# 側 PollSelection で即時フォーカス再取得
UiaRequestRefresh() {
    global UIA_MMF_NAME

    hWrite := DllCall("OpenFileMapping"
        , "UInt", 0x0002
        , "Int",  0
        , "Str",  UIA_MMF_NAME
        , "Ptr")
    if (!hWrite)
        return

    pWrite := DllCall("MapViewOfFile"
        , "Ptr",  hWrite
        , "UInt", 0x0002
        , "UInt", 0
        , "UInt", 0
        , "UInt", 16
        , "Ptr")
    if (pWrite) {
        ; Offset 9 = refreshRequest, 1 = 再チェック要求
        NumPut(1, pWrite + 9, 0, "UChar")
        DllCall("UnmapViewOfFile", "Ptr", pWrite)
    }
    DllCall("CloseHandle", "Ptr", hWrite)
}

UiaSendShutdownSignal() {
    global UIA_MMF_NAME

    ; 書き込み用に共有メモリを開き直す
    ; FILE_MAP_WRITE = 0x0002
    hWrite := DllCall("OpenFileMapping"
        , "UInt", 0x0002
        , "Int",  0
        , "Str",  UIA_MMF_NAME
        , "Ptr")
    if (!hWrite)
        return

    pWrite := DllCall("MapViewOfFile"
        , "Ptr",  hWrite
        , "UInt", 0x0002
        , "UInt", 0
        , "UInt", 0
        , "UInt", 16
        , "Ptr")
    if (pWrite) {
        ; Offset 8 = shutdownSignal, 1 = シャットダウン要求
        NumPut(1, pWrite + 8, 0, "UChar")
        DllCall("UnmapViewOfFile", "Ptr", pWrite)
    }
    DllCall("CloseHandle", "Ptr", hWrite)
}
