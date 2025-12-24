InsertDateTime(fmt) {
    FormatTime, TimeString,, %fmt%
    SendInput, {Text}%TimeString%
}

