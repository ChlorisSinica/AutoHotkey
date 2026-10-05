; Run: AutoHotkeyU64.exe /ErrorStdOut /CP65001 tests\WindowGridPersistence.test.ahk
#NoEnv
#NoTrayIcon
#Include %A_ScriptDir%\..\Plugins\WindowGrid.ahk

global TestChecks := 0

try {
    if (A_Args.Length() = 2 && A_Args[1] = "--check-persisted") {
        TestEqual(GridModeIndex, 1, "fresh process default")
        Grid_LoadConfig(A_Args[2])
        TestEqual(GridModeIndex, 2, "fresh process restored index")
        TestEqual(GRID_ROWS, 3, "fresh process restored rows")
        TestEqual(GRID_COLS, 2, "fresh process restored cols")
        ExitApp, 0
    }
    TestModePersistence()
    FileAppend, % "PASS: " . TestChecks . " persistence checks`n", *
    ExitApp, 0
} catch e {
    FileAppend, % "FAIL: " . e.Message . "`n", *
    ExitApp, 1
}

CloseToolTip:
return

TestModePersistence() {
    global SUI_ConfigPath, GridModes, GridModeIndex, GRID_ROWS, GRID_COLS
    originalPath := SUI_ConfigPath
    originalModes := GridModes
    testPath := A_Temp . "\WindowGrid-test-" . DllCall("GetCurrentProcessId") . "-" . A_TickCount . ".ini"
    try {
        SUI_ConfigPath := testPath
        Grid_LoadConfig(testPath)
        TestEqual(GRID_ROWS, 2, "missing config defaults to 2 rows")
        TestEqual(GRID_COLS, 2, "missing config defaults to 2 cols")
        IniWrite, 7, %testPath%, OtherSetting, Keep
        Grid_ToggleMode()
        ToolTip
        IniRead, saved, %testPath%, WindowGrid, Mode
        if (saved != "3x2")
            throw Exception("toggle must immediately persist 3x2")
        command := Chr(34) . A_AhkPath . Chr(34) . " /ErrorStdOut /CP65001 "
            . Chr(34) . A_ScriptFullPath . Chr(34) . " --check-persisted " . Chr(34) . testPath . Chr(34)
        RunWait, %command%,, Hide UseErrorLevel
        TestEqual(ErrorLevel, 0, "restored in fresh process")
        GridModes := [originalModes[2], originalModes[1]]
        Grid_LoadConfig(testPath)
        TestEqual(GridModeIndex, 1, "dimensions survive mode reorder")
        TestEqual(GRID_ROWS, 3, "reordered rows")
        GridModes := originalModes
        Grid_LoadConfig(testPath)
        Grid_ToggleMode()
        ToolTip
        GRID_ROWS := 3
        Grid_LoadConfig(testPath)
        TestEqual(GRID_ROWS, 2, "toggle wraps and persists 2x2")
        IniRead, kept, %testPath%, OtherSetting, Keep
        TestEqual(kept, 7, "unrelated setting preserved")
        for _, invalid in ["garbage", "99x99", "3x3"] {
            IniWrite, %invalid%, %testPath%, WindowGrid, Mode
            Grid_LoadConfig(testPath)
            TestEqual(GRID_ROWS, 2, "invalid mode falls back")
            TestEqual(GRID_COLS, 2, "invalid mode cols")
        }
        TestEqual(Grid_SaveConfig(""), false, "missing save path fails")
        TestEqual(Grid_SaveConfig(A_Temp), false, "directory is not a config file")
    } finally {
        ToolTip
        SetTimer, CloseToolTip, Off
        GridModes := originalModes
        SUI_ConfigPath := originalPath
        FileDelete, %testPath%
    }
}

TestEqual(actual, expected, label) {
    global TestChecks
    TestChecks += 1
    if (Abs(actual - expected) > 0.00001)
        throw Exception(label . ": expected " . expected . ", got " . actual)
}

GetVisibleWindowPos(ByRef x, ByRef y, ByRef w, ByRef h, title) {
    global TestRect
    x := TestRect.x, y := TestRect.y, w := TestRect.w, h := TestRect.h
}

GetMonitorWorkAreaInfoFromPoint(x, y) {
    global TestMonitor
    return TestMonitor
}

WindowIsland_Enabled() {
    global TestIsland
    return TestIsland
}

GetWindowIslandGaps(monitor) {
    shortEdge := Min(monitor.Width, monitor.Height)
    return {OuterX: Round(shortEdge * 0.006), OuterY: Round(shortEdge * 0.008)
        , InnerX: Round(shortEdge * 0.006), InnerY: Round(shortEdge * 0.008)}
}

GetAdjacentMonitorWorkAreaInfo(monitor, direction) {
    return ""
}

MoveWindowPixel(hwnd, x, y, w, h) {
    global TestMoved
    TestMoved := {x: x, y: y, w: w, h: h}
}
