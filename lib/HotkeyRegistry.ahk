; ==============================================================================
; Hotkey help registry
; - Scaffold for migrating help metadata toward a single structured source
; - Does not register hotkeys; it only groups metadata for Settings UI
; ==============================================================================

HotkeyRegistry_Create() {
    return {}
}

HotkeyRegistry_AddItem(ByRef registry, featureVar, key, desc, action, whenText
    , note := "", match := "", before := 1, after := 1, sourceFile := "") {
    if !registry.HasKey(featureVar)
        registry[featureVar] := []

    registry[featureVar].Push({Kind: "item"
        , Key: key
        , Desc: desc
        , Action: action
        , When: whenText
        , Note: note
        , Match: match
        , Before: before
        , After: after
        , SourceFile: sourceFile})
}

HotkeyRegistry_AddSection(ByRef registry, featureVar, title, body, whenText
    , match := "", before := 0, after := 0, sourceFile := "") {
    if !registry.HasKey(featureVar)
        registry[featureVar] := []

    registry[featureVar].Push({Kind: "section"
        , Key: title
        , Desc: body
        , When: whenText
        , Match: match
        , Before: before
        , After: after
        , SourceFile: sourceFile})
}

HotkeyRegistry_ExportHelpData(registry) {
    data := {}
    for featureVar, entries in registry {
        h := []
        for _, entry in entries {
            if (entry.Kind = "section")
                h.Push(SUI_HelpSection(entry.Key, entry.Desc, entry.When, entry.Match, entry.Before, entry.After, entry.SourceFile))
            else
                h.Push(SUI_HelpItem(entry.Key, entry.Desc, entry.Action, entry.When, entry.Note, entry.Match, entry.Before, entry.After, entry.SourceFile))
        }
        data[featureVar] := h
    }
    return data
}
