#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

.const FixedLinesBeforeFld = 1 * 8              // text lines before FLD effect
.const FixedLinesAfterFld = 3 * 8               // fixed text lines between 2 FLDs
.const StartLine = 49 + FixedLinesBeforeFld     // start must be at the end of a char line
.const SkipRasterLinesTop = 1 * 8               // raster lines of first FLD
.const SkipRasterLinesBottom = 2 * 8            // raster lines of second FLD

BasicUpstart2(main)

main:

    lda #$ff                                    // make FLD lines at the bottom black (pixels set)
    sta $3fff                                   // this is what VIC reads if there is something to display but no data is available
    sei                                         // disable all interrupts

    jsr Kernel.ClearScreen

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

startNewFrame:
    BusyWaitForNewScreen()                      // wait for new frame
 
    lda #%00011011                              // apply YSCROLL default
    sta VIC.SCREEN_CONTROL_REG                  
 
    lda #StartLine                              // wait for starting line
!:  cmp VIC.CURRENT_RASTERLINE_REG
    bne !-

    // we are now in the middle of line 57 (%00111001, YSCROLL 011), one more before a badline

    ldx #SkipRasterLinesTop                     // skip n lines on top 
!:  BusyWaitForNextRasterLine()
    
    // after 58, %00111010++ we always increase YSCROLL by one (0100++)
    IncreaseYScrollBy(1)                        // increase YSCROLL to never match current raster line's last 3 bits
    dex                                         
    bne !-                                      // iterate for x raster lines
 
    // 7,6,5,4,3,2,1,0
    // now we at 66, 
    lda #%00011011                              // restore defaults for the next n text lines
    sta VIC.SCREEN_CONTROL_REG                    

    ldx #FixedLinesAfterFld
 !: BusyWaitForNextRasterLine()
    dex
    bne !-
    // we're now at 89, 01011001

    ldx #SkipRasterLinesBottom                  // skip n lines at the bottom of the text
!:  BusyWaitForNextRasterLine()

    // 90, 01011010++
    IncreaseYScrollBy(1)
    dex                                
    bne !-          

    lda #%00011011                              // apply defaults for the rest of the screen
    sta $d011                          

    jmp startNewFrame                           // do this forever
