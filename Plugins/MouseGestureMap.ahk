; ■ ブラウザ用マップ
Map_Browser(g) {
    Switch g
    {
    Case "↗": WinMinimize, A
    Case "↙": Send, ^+t
    Case "↖": Send, ^1
    Case "↘": Send, ^9
    Case "→": Send, ^{Tab}
    Case "←": Send, ^+{Tab}
    Case "↓": Send, ^w
    Case "↑": Send, ^t
    }
}

; ■ エクスプローラー用マップ
Map_Explorer(g) {
    Switch g
    {
    Case "↗": WinMinimize, A
    Case "↙": Send, ^z
    Case "↖": Send, ^1
    Case "↘": Send, ^1^+{Tab}
    Case "→": Send, ^{Tab}
    Case "←": Send, ^+{Tab}
    Case "↓": Send, ^w
    Case "↑": Send, ^t
    }
}

; ■ エディタ用マップ
Map_Editor(g) {
    Switch g
    {
    Case "→": Send, ^{Tab}
    Case "←": Send, ^+{Tab}
    Case "↓": Send, ^w
    Case "↑": Send, ^t
    Default: Map_Default(g)
    }
}

; ■ Pycharm用マップ
Map_Pycharm(g) {
    Switch g
    {
    Case "→": Send, !{Right}
    Case "←": Send, !{Left}
    Case "↓": Send, ^{F4}
    Case "↑": Send, ^!{Insert}
    Default: Map_Default(g)
    }
}

; ■ 共通設定 (デフォルト)
Map_Default(g) {
    Switch g
    {
    Case "↗": WinMinimize, A
    }
}