.macro ReturnFromInterrupt() {
    pla
    tay
    pla
    tax
    pla
    rti
}

.macro WasteXTimes5Plus1Cycles(x)
{
    ldx #x  // 2
 !: dex     // x*2
    bne !-  // x-1*3+2
}