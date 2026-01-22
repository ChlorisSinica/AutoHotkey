; ==============================================================================
; インジケーター＆設定初期化関数 (ラッパー)
; main.ahk の Indicator_Init() 呼び出しに対応するために必要です
; ==============================================================================
Indicator_Init() {
    SettingsUI.Init()
}

; ホットキー (vk1C & F1) から呼ばれる関数
Settings_Open() {
    SettingsUI.Show()
}

; ホットキー (Escape) から呼ばれる関数
Settings_Close() {
    Gui, Settings:Destroy
}

; ==============================================================================
; 設定管理クラス
; ==============================================================================
class SettingsUI {
    ; --- クラス変数（設定値の保持） ---
    static IsDetailOpen := 0
    static EditorType := 1  ; 1: Notepads, 2: Notepad
    
    ; 設定項目のリスト
    static CheckBoxes := {"EnableNavLayer": "変換キー拡張 (カーソル移動など)"
                        , "EnableWinMgr":   "Window操作 (Win+矢印など)"
                        , "EnableMouseExt": "マウスボタン拡張 (F13-F24)"
                        , "EnableAppSpec":  "アプリ固有設定 (Excel/PPT/Browser)"
                        , "EnableMouseEmu": "キーボードマウス (vk1C+WASD)"
                        , "EnableGestures": "マウスジェスチャー"}

    ; --- 1. 初期化処理 ---
    Init() {
        Global StartupShortcutPath, TargetScriptPath
        TargetScriptPath := A_ScriptDir . "\main.ahk"
        StartupShortcutPath := A_Startup . "\ahk_main_shorcut.lnk"

        Menu, Tray, Add     
        Menu, Tray, Add     ; 区切り線
        Menu, Tray, Add, スタートアップで実行する, Startup_Toggle
        Menu, Tray, Add, 機能設定 (Settings), Settings_Open
        
        IfExist, %StartupShortcutPath%
            Menu, Tray, Check, スタートアップで実行する
    }

    ; --- 2. GUI表示（メイン） ---
    Show() {
        Global ; 【重要】クラス内でGUIコマンドを使うためのおまじない

        ; 既存GUIの破棄と新規作成
        Gui, Settings:Destroy
        Gui, Settings:New, +AlwaysOnTop +HwndhGui, 機能のON/OFF設定
        Gui, Settings:Font, s10, Meiryo UI

        ; イベントハンドラのバインド
        this.fnSave   := ObjBindMethod(this, "OnSave")
        this.fnToggle := ObjBindMethod(this, "OnToggleDetail")

        ; 各エリアの描画
        this.AddBasicControls()
        this.AddDetailControls()

        ; 初回の表示状態を適用
        this.RefreshWindowSize()
    }

    ; --- 3. 基本設定エリアの描画 ---
    AddBasicControls() {
        Global ; 【重要】コントロール変数をグローバル扱いにする
        fn := this.fnSave
        For param, labelText in this.CheckBoxes {
            CurrentVal := %param% 
            Gui, Settings:Add, CheckBox, v%param% g%fn% Checked%CurrentVal%, %labelText%
        }
    }

    ; --- 4. 詳細設定エリアの描画 ---
    AddDetailControls() {
        Global ; 【重要】コントロール変数をグローバル扱いにする
        fnToggle := this.fnToggle
        fnSave   := this.fnSave

        ; 少し間隔を空ける
        Gui, Settings:Add, Text, h5 

        ; ▼ クリック用のテキストラベル (ボタンの代わり)
        ; 青色(cBlue)にしてリンクっぽく見せます
        LabelText := (this.IsDetailOpen ? "▼" : "▶") . " メモ帳"
        Gui, Settings:Add, Text, xs vDetailLabel g%fnToggle% cBlue, %LabelText%

        ; ▼ ラジオボタン（横並び配置）
        Check1 := (this.EditorType = 1) ? "Checked" : ""
        Check2 := (this.EditorType = 2) ? "Checked" : ""
        
        ; 1つ目: Notepads (インデントして配置)
        Gui, Settings:Add, Radio, xs+20 y+5 vRadioNotepads g%fnSave% %Check1%, Notepads (UWP)
        
        ; 2つ目: notepad.exe (x+15 で右横に配置)
        Gui, Settings:Add, Radio, x+15 vRadioStandard g%fnSave% %Check2%, notepad.exe (標準)
    }

    ; --- イベント: 保存処理 ---
    OnSave() {
        Global ; 【重要】変数を読み取るために必要
        Gui, Settings:Submit, NoHide
        
        ; ラジオボタン(RadioNotepads)の値を見てクラス変数を更新
        ; ラジオボタンはグループの1つ目の変数に 1(ON) か 0(OFF) が入るわけではなく、
        ; グループのどの項目が選ばれたか(1, 2...)が入る仕様を利用する場合と、
        ; 個別の変数を見る場合がありますが、ここでは RadioNotepads に 1(Notepads) か 2(Standard) が入ります。
        this.EditorType := RadioNotepads
    }

    ; --- イベント: 折りたたみ切替 ---
    OnToggleDetail() {
        this.IsDetailOpen := !this.IsDetailOpen
        
        ; ラベルのテキスト更新 (▶ / ▼)
        LabelText := (this.IsDetailOpen ? "▼" : "▶") . " メモ帳"
        GuiControl, Settings:, DetailLabel, %LabelText%
        
        ; 表示更新
        this.RefreshWindowSize()
    }

    ; --- ウィンドウサイズ更新（表示/非表示の切り替え） ---
    RefreshWindowSize() {
        if (this.IsDetailOpen) {
            ; 開くとき: コントロールを表示してから AutoSize
            GuiControl, Settings:Show, RadioNotepads
            GuiControl, Settings:Show, RadioStandard
            Gui, Settings:Show, AutoSize
        } else {
            ; 閉じるとき: コントロールを隠してから AutoSize
            GuiControl, Settings:Hide, RadioNotepads
            GuiControl, Settings:Hide, RadioStandard
            Gui, Settings:Show, AutoSize
        }
    }
}

; ==============================================================================
; スタートアップ切替関数
; ==============================================================================
Startup_Toggle(ItemName, ItemPos="", MenuName="") {
    Global StartupShortcutPath, TargetScriptPath
    if (ItemName = "")
        return
    IfNotExist, %TargetScriptPath%
    {
        MsgBox, 16, エラー, 同一フォルダに main.ahk が見つかりません。`n%TargetScriptPath%
        return
    }
    IfExist, %StartupShortcutPath%
    {
        FileDelete, %StartupShortcutPath%
        if (ErrorLevel = 0) {
            Menu, Tray, Uncheck, %ItemName%
            MsgBox, 64, 設定変更, スタートアップから削除しました。
        } else {
            MsgBox, 16, エラー, 削除に失敗しました。`n%StartupShortcutPath%
        }
    }
    Else
    {
        FileCreateShortcut, %TargetScriptPath%, %StartupShortcutPath%, %A_ScriptDir%
        if (ErrorLevel = 0) {
            Menu, Tray, Check, %ItemName%
            MsgBox, 64, 設定変更, スタートアップに登録しました。
        } else {
            MsgBox, 16, エラー, 作成に失敗しました。
        }
    }
}