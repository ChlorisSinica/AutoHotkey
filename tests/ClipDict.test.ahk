; Run: AutoHotkeyU64.exe /ErrorStdOut /CP65001 tests\ClipDict.test.ahk
#NoEnv
#NoTrayIcon
#Include %A_ScriptDir%\..\Plugins\ClipDict.ahk

global TestChecks := 0

try {
    TestEscapeRoundTrip()
    TestScaleOptions()
    TestNormalizeIndex()
    TestApplyLiteral()
    TestApplyRegex()
    TestSaveLoadRoundTrip()
    TestLoadHandWrittenFile()
    FileAppend, % "PASS: " . TestChecks . " ClipDict checks`n", *
    ExitApp, 0
} catch e {
    FileAppend, % "FAIL: " . e.Message . "`n", *
    ExitApp, 1
}

TestEscapeRoundTrip() {
    samples := ["plain", "a`tb", "line1`r`nline2", "C:\Users\name", "\n literal", "#hash", "\#", "\\", "trailing\", "日本語　全角"]
    for _, sample in samples {
        escaped := ClipDict_Escape(sample)
        TestEqual(InStr(escaped, "`t") || InStr(escaped, "`r") || InStr(escaped, "`n"), 0, "escaped has no TAB/CR/LF: " . sample)
        TestSame(ClipDict_Unescape(escaped), sample, "escape round trip")
    }
    TestSame(ClipDict_Escape("#a"), "\#a", "leading # escaped")
    TestSame(ClipDict_Escape("a#"), "a#", "inner # kept")
    TestSame(ClipDict_Unescape("C:\Users"), "C:\Users", "unknown escape kept")
    TestSame(ClipDict_Unescape("a\tb\nc"), "a`tb`nc", "known escapes decoded")
    TestSame(ClipDict_Unescape("a\Tb"), "a\Tb", "escapes are case-sensitive")
}

TestScaleOptions() {
    global ClipDict_Scale
    original := ClipDict_Scale
    try {
        ClipDict_Scale := 1.5
        TestSame(ClipDict_Pos("x12 y14 w32 h20 vClipDictLV c606060 +LV0x10000 -Multi")
            , "x18 y21 w48 h30 vClipDictLV c606060 +LV0x10000 -Multi", "only coordinates scaled")
        TestEqual(ClipDict_Px(760), 1140, "pixel scale")
        ClipDict_Scale := 1
        TestSame(ClipDict_Pos("x12 y14"), "x12 y14", "scale 1 keeps values")
    } finally {
        ClipDict_Scale := original
    }
}

TestNormalizeIndex() {
    TestEqual(ClipDict_NormalizeIndex(3), 3, "valid index")
    TestEqual(ClipDict_NormalizeIndex("9"), 9, "string index")
    TestEqual(ClipDict_NormalizeIndex(0), 1, "below range")
    TestEqual(ClipDict_NormalizeIndex(10), 1, "above range")
    TestEqual(ClipDict_NormalizeIndex("x"), 1, "non-numeric")
}

TestApplyLiteral() {
    dict := {CaseSensitive: 1, Entries: [{From: "foo", To: "bar", Regex: 0}
        , {From: "bar", To: "baz", Regex: 0}
        , {From: "", To: "never", Regex: 0}
        , {From: "/", To: "\", Regex: 0}]}
    previous := A_StringCaseSense
    result := ClipDict_Apply("foo bar a/b", dict, counts, errors)
    TestSame(result, "baz baz a\b", "entries apply top to bottom")
    TestEqual(counts[1], 1, "foo count")
    TestEqual(counts[2], 2, "bar count includes chained result")
    TestEqual(counts[3], 0, "empty search skipped")
    TestEqual(counts[4], 1, "literal backslash replacement")
    TestEqual(errors.Count(), 0, "no errors")
    TestSame(A_StringCaseSense, previous, "StringCaseSense restored")

    dict := {CaseSensitive: 1, Entries: [{From: "foo", To: "x", Regex: 0}]}
    TestSame(ClipDict_Apply("Foo foo", dict, counts, errors), "Foo x", "case-sensitive literal")
    dict.CaseSensitive := 0
    TestSame(ClipDict_Apply("Foo foo", dict, counts, errors), "x x", "case-insensitive literal")
    TestEqual(counts[1], 2, "case-insensitive count")
    TestSame(ClipDict_Apply("", dict, counts, errors), "", "empty source")
}

TestApplyRegex() {
    dict := {CaseSensitive: 1, Entries: [{From: "(\d+)円", To: "¥$1", Regex: 1}
        , {From: "(abc", To: "x", Regex: 1}
        , {From: "、", To: "\n", Regex: 1}]}
    result := ClipDict_Apply("100円、2000円", dict, counts, errors)
    TestSame(result, "¥100`n¥2000", "regex backreference and \n in replacement")
    TestEqual(counts[1], 2, "regex count")
    TestEqual(counts[2], -1, "invalid regex marked")
    TestEqual(errors.HasKey(2), true, "invalid regex error recorded")
    TestEqual(counts[3], 1, "entries after an error still apply")
    TestEqual(ClipDict_SumCounts(counts), 3, "sum skips errors")

    TestSame(ClipDict_RegexPattern("abc", 1), "abc", "case-sensitive pattern untouched")
    TestSame(ClipDict_RegexPattern("abc", 0), "i)abc", "i option added")
    TestSame(ClipDict_RegexPattern("m)^abc", 0), "im)^abc", "i merged into existing options")
    TestSame(ClipDict_RegexPattern("(a)b", 0), "i)(a)b", "group is not an option prefix")

    dict := {CaseSensitive: 0, Entries: [{From: "m)^abc", To: "X", Regex: 1}]}
    ; AHK の正規表現の既定改行は CRLF (クリップボードのテキストと同じ)
    TestSame(ClipDict_Apply("ABC`r`nabc", dict, counts, errors), "X`r`nX", "case-insensitive multiline regex")
    TestSame(ClipDict_RegexError("abc"), "", "valid regex has no error")
    TestEqual(ClipDict_RegexError("(abc") != "", true, "invalid regex reports error")
}

TestSaveLoadRoundTrip() {
    global ClipDict_Dir, ClipDict_Dicts
    originalDir := ClipDict_Dir
    testDir := A_Temp . "\ClipDict-test-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount
    try {
        ClipDict_Dir := testDir
        ClipDict_Dicts := {}
        dict := ClipDict_GetDict(3)
        dict.Name := "#表記|ゆれ"
        dict.CaseSensitive := 0
        dict.Entries.Push({From: "#tag", To: "\#x", Regex: 0})
        dict.Entries.Push({From: "a`tb", To: "c`r`nd", Regex: 1})
        dict.Entries.Push({From: "C:\Users", To: "D:\", Regex: 0})
        TestEqual(ClipDict_SaveDict(3), true, "save succeeds and creates directory")
        TestEqual(FileExist(ClipDict_DictPath(3) . ".tmp") = "", true, "temp file removed")

        loaded := ClipDict_LoadDict(ClipDict_DictPath(3), 3)
        TestSame(loaded.Name, dict.Name, "name round trip")
        TestEqual(loaded.CaseSensitive, 0, "case flag round trip")
        TestEqual(loaded.Entries.Length(), 3, "entry count round trip")
        for index, entry in dict.Entries {
            TestSame(loaded.Entries[index].From, entry.From, "from round trip " . index)
            TestSame(loaded.Entries[index].To, entry.To, "to round trip " . index)
            TestEqual(loaded.Entries[index].Regex, entry.Regex, "regex flag round trip " . index)
        }

        ClipDict_LoadAll()
        TestEqual(ClipDict_Dicts[3].Entries.Length(), 3, "load all reads saved dict")
        TestSame(ClipDict_Dicts[1].Name, "辞書1", "missing dict gets default name")
        TestEqual(ClipDict_Dicts[1].CaseSensitive, 1, "missing dict defaults to case-sensitive")
        TestSame(ClipDict_DictLabel(3), "3: #表記|ゆれ", "label uses name")
        ClipDict_Dicts[2].Name := ""
        TestSame(ClipDict_DictLabel(2), "2: 辞書2", "empty name falls back")
    } finally {
        ClipDict_Dir := originalDir
        ClipDict_Dicts := {}
        FileRemoveDir, %testDir%, 1
    }
}

TestLoadHandWrittenFile() {
    path := A_Temp . "\ClipDict-hand-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . ".tsv"
    try {
        file := FileOpen(path, "w", "UTF-8-RAW")
        file.Write("# comment`n#name`t手書き`n`nサーバ`tサーバー`n`tignored`nx`ty`tr`n")
        file.Close()
        loaded := ClipDict_LoadDict(path, 5)
        TestSame(loaded.Name, "手書き", "BOM-less UTF-8 name")
        TestEqual(loaded.CaseSensitive, 1, "missing case line defaults on")
        TestEqual(loaded.Entries.Length(), 2, "comments, blanks and empty search skipped")
        TestSame(loaded.Entries[1].To, "サーバー", "LF-only file parsed")
        TestEqual(loaded.Entries[1].Regex, 0, "missing type column is literal")
        TestEqual(loaded.Entries[2].Regex, 1, "r type is regex")
        TestEqual(ClipDict_LoadDict(path . ".missing", 4).Entries.Length(), 0, "missing file is empty dict")
    } finally {
        FileDelete, %path%
    }
}

TestEqual(actual, expected, label) {
    global TestChecks
    TestChecks += 1
    if (actual != expected)
        throw Exception(label . ": expected " . expected . ", got " . actual)
}

TestSame(actual, expected, label) {
    global TestChecks
    TestChecks += 1
    if !(actual == expected)
        throw Exception(label . ": expected [" . expected . "], got [" . actual . "]")
}

ClipboardWrite(ByRef data, retries := 5) {
    return true
}

GetMonitorWorkAreaInfoFromWindow(hwnd) {
    return ""
}

GetMonitorWorkAreaInfoFromPoint(x, y) {
    return ""
}
