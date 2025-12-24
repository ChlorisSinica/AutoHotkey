OpenFormatObject() {
    Send, !jpsz
    Sleep, 50               
}

SetRight() {
    Send, !hgar
}

SetLeft() {
    Send, !hgal
}

SetTop() {
    Send, !hgat
}

SetBottom() {
    Send, !hgab
}

SetHorizontalCenter() 
{
    Send, !hgac
}

SetVerticalCenter() {
    Send, !hgam
}

SetHorizontalSpacer() {
    Send, !hgah
}

SetVerticalSpace() {
    Send, !hgav
}

GroupSet() {
    Send, !hgg
}

GroupRelease() {
    Send, !hgu
}

SetFront() {
    Send, !hgr
}

SetBack() {
    Send, !hgk
}

SetFrameLine() {
    Send, !jpsow{Home}{Down}{Enter}
}

SetFrameSize() {
    Send, !jpw
}
