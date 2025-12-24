;#Include C:\Program Files\AutoHotkey\myhotkey.ahk
;#Include C:\myApp\AutoHotkey\main.ahk
;vk1C:Convert-Key
;vk1D:Non-Convert-Key
;vkf0:CapsLock

InsertHyphen() {
    Send, {F2}
    Sleep, 50
    Send, {Left}
    Send, ^{Right 2}
    Sleep, 50
    Send, -{Space}{Tab}
    Sleep, 50
}

DeleteUnderBar() {
    Send, {F2}
    Sleep, 50
    Send, {Right}
    Send, ^{Left}
    Send, {Right}{Delete}
    Sleep, 50
    Send, {Space}{Tab}
    Sleep, 50
}

DeleteTitle() {
  Send, {Right}+{Home}
    Sleep, 50
    Send, ^+{Right 2}
    Sleep, 50
    Send, +{Left}
    Sleep, 50
  Send, {Backspace}{Tab}
    Sleep, 50
}

; ----- OneTime -----
vk1C & ,::
    Loop, 20
    {
        DeleteTitle()
    }
return

