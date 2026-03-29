<!-- ⚠️ 設計意図を示す擬似コード。実装時に正確な構文に整えること -->

# Snippets: チャタリング防止プラグイン + CSharpUIA 導入

## §1 Plugins/ChatterGuard.ahk

```ahk
; === 状態 ===
global CG_State       := {}
global CG_OnCleanDown := ""   ; Func callback: OnCleanDown(keyName)
global CG_OnCleanUp   := ""   ; Func callback: OnCleanUp(keyName)

; thresholds = { "F15": 55, "XButton1": 55, ... }
CG_Init(thresholds) {
    global CG_State
    CG_State := {}
    for keyName, ms in thresholds {
        CG_State[keyName] := { isDown: false, threshold: ms, lastStamp: 0 }
    }
}

CG_RawDown(keyName) {
    ; plan.md §3.1 の状態遷移に従う
    ; isDown=true なら無視、threshold 内なら無視、それ以外で OnCleanDown
}

CG_RawUp(keyName) {
    ; isDown=false なら無視、それ以外で OnCleanUp
}

CG_Stamp(keyName) {
    ; lastStamp = A_TickCount
}

CG_IsHeld(keyName) {
    ; return isDown
}
```

**ポイント**: .logs/ 版との差分はグローバル直書きの `CG_Thresholds` / `CG_ComboThresholds` がないこと。閾値は `CG_Init` 経由でのみ設定。

## §2 Plugins/KeyRouter.ahk

```ahk
global MK_ActionMap       := {}
global MK_ComboMap        := {}
global MK_WheelMap        := {}
global MK_HoldState       := {}
global MK_TriggerKeys     := {}
global MK_ComboTicks      := {}
global MK_ComboThresholds := {}
global MK_ReleaseCallbacks := {}
global MK_ComboReady      := false

; 初期化: ChatterGuard 接続
MK_Init(thresholds) {
    CG_Init(thresholds)
    CG_OnCleanDown := Func("MK_OnDown")
    CG_OnCleanUp   := Func("MK_OnUp")
}

; MK_OnDown, MK_OnUp, MK_OnWheel, MK_Exec, MK_ResolveAction
; → .logs/MouseKeyRouter.ahk と同一ロジック

; コンボ連打防止閾値を外部設定可能に
MK_SetComboThresholds(thresholds) {
    global MK_ComboThresholds
    MK_ComboThresholds := thresholds
}
```

**ポイント**: .logs/ 版の L21-23（グローバルスコープでの自動初期化）を `MK_Init()` に移動。`CG_ComboThresholds` → `MK_ComboThresholds` として KeyRouter 側で管理。

## §3 main.ahk 変更箇所

### §3.1 #Include 追加

```ahk
; --- Plugins ファイルの読み込み --- の末尾に追加
#Include %A_ScriptDir%\Plugins\ChatterGuard.ahk
#Include %A_ScriptDir%\Plugins\KeyRouter.ahk
```

### §3.2 初期化セクション

```ahk
; --- キー設定テーブル ---
MK_Init({"XButton1": 55, "XButton2": 55, "MButton": 55
    , "F15": 55, "F16": 55, "F17": 55})

MK_SetComboThresholds({"F15+MButton": 120})

; 単独タップアクション
MK_ActionMap["F15"]     := {default: "^v", "ahk_exe POWERPNT.EXE": Func("PasteImageWithMetadata")}
MK_ActionMap["F16"]     := "^c"
MK_ActionMap["F17"]     := "^w"
MK_ActionMap["XButton1"] := "{XButton1}"
MK_ActionMap["XButton2"] := "{XButton2}"

; コンボアクション (modifier+trigger)
MK_ComboMap["F15+MButton"] := "{Media_Play_Pause}"

; ホイール修飾
MK_WheelMap["XButton1"] := {Up: Func("MouseWheel_HScroll").Bind("Left"), Down: Func("MouseWheel_HScroll").Bind("Right")}
MK_WheelMap["XButton2"] := {Up: Func("MouseWheel_Zoom").Bind("In"), Down: Func("MouseWheel_Zoom").Bind("Out")}
MK_WheelMap["F15"]      := {Up: "{Volume_Up}", Down: "{Volume_Down}"}
MK_WheelMap["F16"]      := {Up: Func("AltTabAction").Bind("Prev"), Down: Func("AltTabAction").Bind("Next")}
```

### §3.3 ホットキー定義の書き換え

```ahk
; Before (現在の main.ahk L109-L126):
;   #If (EnableMouseBtn && !WinActive("ahk_exe POWERPNT.EXE"))
;       F15::   Send ^v
;   #If (EnableMouseBtn)
;       XButton1::  XButton1
;       ...

; After:
#If (EnableMouseBtn)
    *F15::      CG_RawDown("F15")
    *F15 Up::   CG_RawUp("F15")
    *F16::      CG_RawDown("F16")
    *F16 Up::   CG_RawUp("F16")
    *F17::      CG_RawDown("F17")
    *F17 Up::   CG_RawUp("F17")
    *XButton1::     CG_RawDown("XButton1")
    *XButton1 Up::  CG_RawUp("XButton1")
    *XButton2::     CG_RawDown("XButton2")
    *XButton2 Up::  CG_RawUp("XButton2")
    *MButton::      CG_RawDown("MButton")
    *MButton Up::   CG_RawUp("MButton")
    WheelUp::       MK_OnWheel("Up")
    WheelDown::     MK_OnWheel("Down")
#If
```

**注意**: `*` 修飾子で他キーとの組み合わせを許可。`MK_ResolveAction` がアプリ別分岐を処理するため、`#If !WinActive(...)` は不要になる。

### §3.4 F16 Up の AltTab メニュー閉じ

```ahk
; F16 Up での CloseAltTabMenu() は MK_OnUp 内の ReleaseCallbacks で処理
; AltTabAction() 内で MK_RegisterRelease("F16", Func("CloseAltTabMenu")) を呼ぶ
```

## §4 main.ahk UIA 接続

```ahk
; #Include 追加 (WindowGrid の後)
#Include %A_ScriptDir%\lib\CSharpUIA\UiaIntegration.ahk

; 初期化セクション
UiaInit()
OnExit("UiaCleanup")
```
