#import "vic_constants.inc"

// in: accu, single color
setColorRamToSingleColor: {
    ldx #$0
!:  sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    dex
    bne !-

    rts    
}

busyWaitForNewScreen: {
    lda VIC.SCREEN_CONTROL_REG                      
    bpl busyWaitForNewScreen        // 7th bit is MSB of rasterline, wait for the next frame
!:  lda VIC.SCREEN_CONTROL_REG                      
    bmi !-                          // wait until the 7th bit is clear (=> line 0 of raster)

    rts
}

// takes number of frames in accumulator
waitNFrames: {
    tay
!:  jsr busyWaitForNewScreen
    dey
    bne !-

    rts
}