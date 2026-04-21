; ==============================================================================
; Feature state registry
; - Single source for settings item order and flag access helpers
; - Keeps UI sync logic out of IndicatorManager's long if/else chains
; ==============================================================================

global _FeatureState_Specs := FeatureState_CreateSpecs()

FeatureState_CreateSpecs() {
    specs := []
    specs.Push({Var: "EnableNavLayer",     Name: "キーボード拡張"})
    specs.Push({Var: "EnableWinPlace",     Name: "ウィンドウ配置"})
    specs.Push({Var: "EnableVDesk",        Name: "仮想デスクトップ"})
    specs.Push({Var: "EnableMouseEmu",     Name: "キーボードマウス"})
    specs.Push({Var: "EnableMouseBtn",     Name: "ボタン・ホイール"})
    specs.Push({Var: "EnableGestures",     Name: "マウスジェスチャー"})
    specs.Push({Var: "EnableChatterGuard", Name: "チャタリング防止"})
    specs.Push({Var: "EnableAlt",          Name: "Alt"})
    specs.Push({Var: "EnableOthers",       Name: "その他"})
    specs.Push({Var: "EnableBrowser",      Name: "ブラウザ"})
    specs.Push({Var: "EnablePPT",          Name: "PowerPoint"})
    specs.Push({Var: "EnableExcel",        Name: "Excel"})
    return specs
}

FeatureState_GetSpecs() {
    global _FeatureState_Specs
    return _FeatureState_Specs
}

FeatureState_HasFlag(varName) {
    specs := FeatureState_GetSpecs()
    for _, spec in specs {
        if (spec.Var = varName)
            return true
    }
    return false
}

FeatureState_GetFlag(varName, defaultValue := 0) {
    if !FeatureState_HasFlag(varName)
        return defaultValue ? 1 : 0

    value := %varName%
    return value ? 1 : 0
}

FeatureState_SetFlag(varName, value) {
    if !FeatureState_HasFlag(varName)
        return false

    value := value ? 1 : 0
    %varName% := value

    if (varName = "EnableChatterGuard") {
        if (value)
            CG_Init(["XButton1", "XButton2"])
        else
            CG_Cleanup()
    }
    return true
}

FeatureState_AfterBulkSync(reason := "") {
    if IsFunc("Cursor_ResolveModeForFlags")
        Cursor_ResolveModeForFlags(reason != "" ? reason : "feature_sync")
}


