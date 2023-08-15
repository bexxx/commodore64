#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

.const FixedLinesBeforeFld = 1 * 8              // text lines before FLD effect
.const FixedLinesAfterFld = 3 * 8               // fixed text lines between 2 FLDs
.const StartLine = 50 + FixedLinesBeforeFld     // start must be at the end of a char line
.const SkipRasterLinesTop = 1 * 8               // raster lines of first FLD
.const SkipRasterLinesBottom = 2 * 8            // raster lines of second FLD
.const MaxBounceHeight = 7 * 8                  // bounce height of fixed content

BasicUpstart2(main)

main:

    lda #$00                                    // make FLD lines as background color (pixels clear)
    sta $3fff                                   // this is what VIC reads if there is something to display but no data is available
    sei                                         // disable all interrupts

    //jsr Kernel.ClearScreen

    ldx #$00
drawCharacters:
.label character = *+1
    lda #$01                                    // draw alphabet on column 0 to fill screen
.label screenTargetLo = *+1
.label screenTargetHi = *+2
    sta $0400
    inx
    cpx #$19                                    // draw on all 25 columns (notice missing lines on bottom)
    beq startNewFrame

    inc character                               // next character
    lda screenTargetLo
    clc
    adc #$28                    
    sta screenTargetLo
    bcc drawCharacters
    inc screenTargetHi
    jmp drawCharacters

    lda #$ff                                    // init sine index. Because we increment first, this will be 0 on first run.
    sta currentSineIndex

startNewFrame:
    BusyWaitForNewScreen()                      // wait for new frame
 
    lda #%00011011                              // apply YSCROLL default
    sta VIC.SCREEN_CONTROL_REG                  
    
    ldy currentSineIndex                        // load index into sine table
    iny                                         // increment first
    cpy #(SineTableEnd-SineTable)               // compare with end of array
    bne updateSineIndex
    ldy #$00
updateSineIndex:
    sty currentSineIndex                        // store updated index for next iteration
    ldx SineTable, y                            // load FLD offset based on sine curve 
    stx currentTopFldLines                      // store in code the top FLD height
    sec
    lda #MaxBounceHeight                        // max height - top bounce == bottom FLD height
    sbc currentTopFldLines
    sta currentBottomFldLines                   // store in code

    lda #StartLine                              // wait for starting line
!:  cmp VIC.CURRENT_RASTERLINE_REG
    bne !-

.label currentTopFldLines = *+1
    ldx #03  
    beq waitForFixedLinesAfterFld               // in case top FLD is 0, skip waiting for raster lines
!:  IncreaseYScrollBy(1)                        // increase YSCROLL to never match current raster line's last 3 bits
    BusyWaitForNextRasterLine()
    dex                                         
    bne !-                                      // iterate for x raster lines
 
waitForFixedLinesAfterFld:                      // wait raster lines for the fixed content (multiples of 8)
    ldx #FixedLinesAfterFld-1
 !: BusyWaitForNextRasterLine()
    dex
    bne !-

.label currentBottomFldLines = *+1    
    ldx #$00
    inx
!:  BusyWaitForNextRasterLine()
    IncreaseYScrollBy(1)
    dex                                
    bne !-          

    lda #%00011011                              // set YSCROLL to default again for rest of screen
    sta VIC.SCREEN_CONTROL_REG                          

    jmp startNewFrame                           // do this forever

currentSineIndex:
    .byte $00

.align $100
.segment Default "sine table"
.const sineSteps = 84
SineTable:
    .fill sineSteps, MaxBounceHeight - MaxBounceHeight * sin(toRadians(i*180/sineSteps))
SineTableEnd: