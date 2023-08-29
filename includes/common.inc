#import "./vic_constants.inc"

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

