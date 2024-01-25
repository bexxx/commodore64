#import "./vic_constants.inc"
#import "./zeropage.inc"

.macro ReturnFromInterrupt() {
    pla
    tay
    pla
    tax
    pla
    rti
}

.macro WasteXTimes5Plus1Cycles(x) {
    ldx #x  // 2
 !: dex     // x*2
    bne !-  // x-1*3+2
}

.macro BusyWaitForNewScreen() {
waitForNewFrame:
    lda VIC.SCREEN_CONTROL_REG                      
    bpl waitForNewFrame                         // 7th bit is MSB of rasterline, wait for the next frame
!:  lda VIC.SCREEN_CONTROL_REG                      
    bmi !-                                      // wait until the 7th bit is clear (=> line 0 of raster)
}

.macro BusyWaitForNextRasterLine() {
    lda VIC.CURRENT_RASTERLINE_REG              // load current raster line
waitForRasterChange:
    cmp VIC.CURRENT_RASTERLINE_REG              // wait raster line to change (next line)
    beq waitForRasterChange
}

.macro IncreaseYScrollBy(pixels) {
    clc                                         
    lda VIC.SCREEN_CONTROL_REG                  // load current reg values with YSCROLL
    adc #pixels                                 // add number of pixels to scroll
    and #%00000111                              // handle overflow of 3 bit
    ora #%00011000                              // restore text mode default (consider adding this as parameter)
    sta VIC.SCREEN_CONTROL_REG                  // write back
}

.macro MakeClearScreenFunction(VicBankNumber, ScreenStart) {
    lda #00
    tax
!:  sta VicBankNumber * $4000 + ScreenStart + $0000,x
    sta VicBankNumber * $4000 + ScreenStart + $0100,x
    sta VicBankNumber * $4000 + ScreenStart + $0200,x
    sta VicBankNumber * $4000 + ScreenStart + $0300,x
    dex
    bne !-
    rts
}

.macro MakeCopyCharRomFunction(VicBank, CharsetStart) {
    .var targetCharsetAddress = VicBank * $4000 + CharsetStart

// copy charset from $d000 (ROM) to VicBankStart+CharsetStart
    sei 

    lda Zeropage.PORT_REG                   // enable chartset rom at $d000
    and #Zeropage.ENABLE_CHAREN_MASK
    sta Zeropage.PORT_REG               

    ldx #$00                               
copyLoop:    
    .for (var page=0; page < 8; page++) {   // we loop 8 times (8x255 = 2Kb)
        lda $d000 + page * $100,x
        sta targetCharsetAddress + page * $100,x
    }
    dex
    bne copyLoop

    lda Zeropage.PORT_REG                   // switch in I/O mapped registers again...
    ora #Zeropage.ENABLE_CHAREN_CLEAR_MASK
    sta Zeropage.PORT_REG     

    cli                                     // turn off interrupt disable flag
    
    rts    
}

.macro MakeCopyScreenRamFunction(SourceVicBank, SourceScreenOffset, TargetVicBank, TargetScreenOffset) {
    .var sourceBufferStart = SourceVicBank * $4000 + SourceScreenOffset
    .var targetBufferStart = TargetVicBank * $4000 + TargetScreenOffset
    ldx #$00
copyLoop:
    // copy 2k screen ram unrolled 4x 256 bytes
.for(var page = 0; page < 4; page++) {    
    lda sourceBufferStart + page * $100,x
    sta targetBufferStart + page * $100,x
 }
    dex
    bne copyLoop

    rts    
}
