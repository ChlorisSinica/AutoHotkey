global g_HoldN_Active := 0

InsertDateTime(fmt) {
    FormatTime, TimeString,, %fmt%
    SendInput, {Text}%TimeString%
}

Manage_N_Hold(Command) {
    ; グローバル変数を参照・変更することを宣言
    global g_HoldN_Active

    ; --- 強制停止 (Off) の処理 ---
    if (Command = "Off") {
        if (g_HoldN_Active) {
            Send, {n up}
            g_HoldN_Active := 0
            ToolTip, [停止] N長押し解除
            SetTimer, CloseToolTip, -1000
        }
        return
    }

    ; --- トグル切り替え (Toggle) の処理 ---
    if (Command = "Toggle") {
        g_HoldN_Active := !g_HoldN_Active ; 反転

        if (g_HoldN_Active) {
            Send, {n down}
            ToolTip, [自動] N長押し中... (vk1C+n+F2で停止)
        } else {
            Send, {n up}
            ToolTip, [解除] Nキーを離しました
            SetTimer, CloseToolTip, -1000
        }
    }
}