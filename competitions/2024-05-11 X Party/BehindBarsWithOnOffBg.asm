#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/cia2_constants.inc"

BasicUpstart2(main)

.namespace Configuration {
    .label VIC_Bank = 2
    .label ScreenRamOffset = $3000 
    .label ScreenRamStart = VIC_Bank * $4000 + ScreenRamOffset
    .label CharsetScrollerOffset = $0000
    .label CharsetSrollerStart = VIC_Bank * $4000 + CharsetScrollerOffset
    .label CharsetBarsOffset = $2000
    .label CharsetBarsStart = VIC_Bank * $4000 + CharsetBarsOffset 

    .label IrqBarsRasterLine = $1
    .label IrqScrollerRasterLine = $30 + 22 * 8
}


* = $1000 "Code and shit"
main:    
    // prepare screen with pattern, same char on each column, increase char each column
    ldx #39
    lda #$ff
!:  .for(var i = 0; i < 25; i++)
    {
        sta Configuration.ScreenRamStart + i * 40,x
    }    
    dex
    bpl !-

    ldx #39   
!:  txa
    .for(var i = 5; i < 22; i++)
    {
        sta Configuration.ScreenRamStart + i * 40,x
    }    
    dex
    bpl !-

    // clear charset
    ldx #0
    txa
!:  
    .for(var i = 0; i < 8; i++)
    {
        sta Configuration.CharsetBarsStart + i * $100,x
    }
    dex
    bne !-

    lda #DARK_GREY
    ldx #0
!:  
    .for(var i = 0; i < 4; i++)
    {
        sta VIC.ColorRamBase + i * $100,x
    }
    dex
    bne !-

    sei
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK2_MASK)

    // switch to new char set
    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_3000_MASK, VIC.SELECT_CHARSET_AT_2000_MASK)
    
    lda #BLACK
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    // disable kernel rom
    lda #$35
    sta Zeropage.PORT_REG

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure    

    lda #<interruptBars                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
    lda #>interruptBars                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

    lda #Configuration.IrqBarsRasterLine        // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    cli

waitForever: jmp waitForever

.align $100                                     // align on the start of a new page
.segment Default "Raster IRQ code"
interruptBars:
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack



.label colorIndex = * + 1
    ldx #$ff
    inx
    stx colorIndex
    lda colors,x
    sta iconBackgroundColor
    sta colorValue
    tax
    bpl !++++

    ldx #$ff
    stx colorIndex 

.label trueFalseValue = * + 1
    lda #$01
    bne doBlackColorRam
    lda #DARK_GREY
    sta zoomerBackgroundColor
    jmp !+
doBlackColorRam:
.label iconBackgroundColor = * + 1
    lda #BLACK
    sta zoomerBackgroundColor
!:
    ldx #40
.label colorRamColor = * + 1
!:  
    .for (var i=4; i<23;i++) {
        sta $d800 + i*40,x
    }
    dex
    bpl !-

    lda trueFalseValue
    eor #$01
    sta trueFalseValue
    
    ldx iconCounter1
    dex
    bpl !+
    ldx #2
!:
    stx iconCounter1
    stx iconCounter2
    stx iconCounter3
    stx iconCounter4

!:
.label colorValue = * + 1
    lda #$ff
    sta $d020
    sta $d021
    
    //inc $d020

    //
    // copy the bitmap from bars to charset
    //

    ldx #7
    ldy #8*8-1

    .var mask = %11001100
    .for (var i = 0; i < 8; i++) {
        lda bars+32,x
        and #mask
        sta Configuration.CharsetBarsStart + $100,y
        dey
        .eval mask = mask ^ $ff
    }

    dex

    .eval mask = %10101010
    .for (var i = 0; i < 8; i++) {
        lda bars+32,x
        and #mask
        sta Configuration.CharsetBarsStart + $100,y
        dey
        .eval mask = mask ^ $ff
    }

    dex

!:
    lda bars+32,x
    .for (var i = 0; i < 8; i++) {
        sta Configuration.CharsetBarsStart + $100,y
        dey
    }
    dex
    bpl !-


    ldx #29
    ldy #8*32-1

!:
    lda bars+2,x
    .for (var i = 0; i < 8; i++) {
        sta Configuration.CharsetBarsStart,y
        dey
    }
    dex
    bpl !-

    ldx #1

    .eval mask = %10101010
    .for (var i = 0; i < 8; i++) {
        lda bars,x
        and #mask
        sta Configuration.CharsetBarsStart,y
        dey
        .eval mask = mask ^ $ff
    }

    dex

    .eval mask = %11001100
    .for (var i = 0; i < 8; i++) {
        lda bars,x
        and #mask
        sta Configuration.CharsetBarsStart,y
        dey
        .eval mask = mask ^ $ff
    }

    //dec $d020

// Speedcode would be ~1100 bytes and save 13 Rasterlines, not worth it for now.
//    .for (var columns = 0; columns < 40; columns++) {
//        lda bars + columns
//        .for (var charBytes = 0; charBytes < 8; charBytes++)
//        {
//            sta Configuration.CharsetBarsStart + columns * 8 + charBytes
//        }
//    }
    

//    lda charData
//    ldx #column
//    lda ramOffLo,x
//    sta targetLo
//    lda ramOffHi,x
//    sta targetHi
//    ldx #xcoord
//
//    ldy #7
//!:
//    lsr
//    bcc doBlack
//    lda #grey
//doGrey:
//    sta $d800,y
//    dey
//    bmi !-
//
//doBlack:
//    lda #grey
//    sta $d800,y
//    dey
//    bmi !-

   // inc $d020
loopMultichars:
//label iconCounter1 = * + 1
//   ldx #$2
//   lda charsLo,x
//   sta charSourceAddress1Lo
//   lda charsHi,x
//   sta charSourceAddress1Hi//
//   // zoom charset data of 1 char to 8x8 "pixel" in color ram
//   lda #<(VIC.ColorRamBase + 9 * 40 + 4)
//   sta colorRamTargetLo
//   lda #>(VIC.ColorRamBase + 9 * 40 + 4)
//   sta colorRamTargetHi//
//   lda #$8
//   sta charRowValue//
//   jsr zoomCharTo8Rows//
//label multiCharIteration = * + 1
//   ldx #3
//   dex    
//   bpl continueWithLogo
//   ldx #3
//ontinueWithLogo:
//   stx multiCharIteration//
//   lda charSourceAddress1Lo
//   adc #8
//   sta charSourceAddress1Lo //
//   jmp loopMultichars
// inc $d020
// 
.label iconCounter1 = * + 1
    ldx #$2
    lda charsLo,x
    sta charSourceAddress1Lo
    lda charsHi,x
    sta charSourceAddress1Hi

    // zoom charset data of 1 char to 8x8 "pixel" in color ram
    lda #<(VIC.ColorRamBase + 6 * 40 + 4)
    sta colorRamTarget1Lo
    sta colorRamTarget2Lo
    lda #>(VIC.ColorRamBase + 6 * 40 + 4)
    sta colorRamTarget1Hi
    sta colorRamTarget2Hi
    jsr zoomCharTo8Rows

.label iconCounter2 = * + 1
    ldx #$2
    lda charsLo,x
    clc
    adc #8
    sta charSourceAddress1Lo
    lda charsHi,x
    sta charSourceAddress1Hi

    lda #<(VIC.ColorRamBase + 6 * 40 + 12)
    sta colorRamTarget1Lo
    sta colorRamTarget2Lo
    lda #>(VIC.ColorRamBase + 6 * 40 + 12)
    sta colorRamTarget1Hi
    sta colorRamTarget2Hi

    jsr zoomCharTo8Rows

.label iconCounter3 = * + 1
    ldx #$2
    lda charsLo,x
    clc
    adc #16
    sta charSourceAddress1Lo
    lda charsHi,x
    sta charSourceAddress1Hi

    lda #<(VIC.ColorRamBase + 14 * 40 + 4)
    sta colorRamTarget1Lo
    sta colorRamTarget2Lo
    lda #>(VIC.ColorRamBase + 14 * 40 + 4)
    sta colorRamTarget1Hi
    sta colorRamTarget2Hi

    jsr zoomCharTo8Rows

.label iconCounter4 = * + 1
    ldx #$2
    lda charsLo,x
    clc
    adc #24
    sta charSourceAddress1Lo
    lda charsHi,x
    sta charSourceAddress1Hi

    lda #<(VIC.ColorRamBase + 14 * 40 + 12)
    sta colorRamTarget1Lo
    sta colorRamTarget2Lo
    lda #>(VIC.ColorRamBase + 14 * 40 + 12)
    sta colorRamTarget1Hi
    sta colorRamTarget2Hi

    jsr zoomCharTo8Rows

  //  dec $d020

    // modify charset charwise
    
    // save leftmost char
    lda bars
    sta LeftMostChar

    ldy #(bars_end - bars - 1)
    ldx #0
!:
    lda bars+1,x
    sta bars,x
    inx
    dey
    bne !-    

.label LeftMostChar = * + 1
    lda #$ff
    sta bars_end - 1

//inc $d020
//inc $d020

// scroll lines smooth, subchar pixels 
//    ldy #3
//!:    
//    ldx #(bars_end - bars -1)
//    lda bars
//    rol
//!:
//    rol bars, x
//    dex
//    bpl !-
//    dey
//    bne !--
//    clc
//dec $d020
//dec $d020

exitFromInterrupt:
    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack
    rti

    // modify color ram in an 8x8 area
zoomCharTo8Rows:
    lda #$8
    sta charRowValue

rowLoop:
.label charRowValue = * + 1    
    ldx #$ff
    dex
    bmi endOfCurrentIteration
    stx charRowValue

.label charSourceAddress1Lo = * + 1
.label charSourceAddress1Hi = * + 2
    lda $dead
    ldx #7
zoom8PixelsWideLoop:
    lsr
    tay
    bcc pixelNotSet
pixelSet:
    lda #LIGHT_GREY
.label colorRamTarget1Lo = * + 1
.label colorRamTarget1Hi = * + 2
    sta $dead,x
    tya    
    dex
    bpl zoom8PixelsWideLoop
    jmp doneWithByte
pixelNotSet:  
.label zoomerBackgroundColor = * + 1
    lda #DARK_GREY
.label colorRamTarget2Lo = * + 1
.label colorRamTarget2Hi = * + 2
    sta $dead,x
    tya    
    dex
    bpl zoom8PixelsWideLoop

doneWithByte:
    inc charSourceAddress1Lo
    // no hi check, is always one same page

noPageIncreaseCharSource:
    lda colorRamTarget1Lo
    clc
    adc #40
    sta colorRamTarget1Lo
    sta colorRamTarget2Lo
    bcc rowLoop

pageIncreaseColorRamTarget:
    inc colorRamTarget1Hi
    inc colorRamTarget2Hi
    jmp rowLoop

endOfCurrentIteration:
    rts



//    // modify color ram in an 8x8 area
//zoomCharTo8Rows:
//    lda #$8
//    sta charRowValue
//
//rowLoop:
//.label charRowValue = * + 1    
//    ldx #$ff
//    dex
//    bmi endOfCurrentIteration
//    stx charRowValue
//
//.label charSourceAddress1Lo = * + 1
//.label charSourceAddress1Hi = * + 2
//    lda $dead
//    //sta currentShiftedCharsetValue
//
//    ldx #7
//zoom8PixelsWideLoop:
//.label currentShiftedCharsetValue = * + 1
//    //lda #$ff
//    lsr
//    tay
//    //sta currentShiftedCharsetValue
//    bcc pixelNotSet
//pixelSet:
//    lda #LIGHT_GREY
//    bne setPixel
//
//pixelNotSet:  
//    lda #DARK_GREY
//
//setPixel:
//.label colorRamTargetLo = * + 1
//.label colorRamTargetHi = * + 2
//    sta $dead,x
//    tya    
//    dex
//    bpl zoom8PixelsWideLoop
//
//    inc charSourceAddress1Lo
////    bne noPageIncreaseCharSource
////    inc charSourceAddress1Hi
//
//noPageIncreaseCharSource:
//    lda colorRamTargetLo
//    clc
//    adc #40
//    sta colorRamTargetLo
//    bcc noPageIncreaseColorRamTarget
//    inc colorRamTargetHi
//
//noPageIncreaseColorRamTarget:
//    jmp rowLoop
//
//endOfCurrentIteration:
//    rts

.align $100

chars:
chars_1:
	.byte	$07, $1F, $3D, $71, $61, $E1, $C1, $C1
	.byte	$E0, $F8, $BC, $8E, $86, $87, $83, $83
	.byte	$C7, $CF, $FD, $79, $71, $3D, $1F, $07
	.byte	$E3, $F3, $BF, $9E, $8E, $BC, $F8, $E0
chars_2:
    .byte	$00, $00, $00, $01, $3F, $1F, $07, $01
	.byte	$30, $30, $40, $80, $FC, $F8, $E0, $80
	.byte	$01, $01, $01, $01, $01, $01, $07, $3F
	.byte	$80, $80, $80, $80, $80, $80, $E0, $FC
chars_3:
	.byte	$1C, $3E, $7F, $7F, $7F, $3F, $3F, $1F
	.byte	$38, $7C, $FE, $FE, $FE, $FC, $FC, $F8
	.byte	$1F, $0F, $07, $07, $03, $03, $01, $00
	.byte	$F8, $F0, $E0, $E0, $C0, $C0, $80, $00

charsLo:
    .byte <chars_2, <chars_1, <chars_3
charsHi:
    .byte >chars_2, >chars_1, >chars_3 

buffer1:
    .fill 40, 0
buffer2:
    .fill 40, 0
bufferPointer:
    .byte 0
sourceBufferLo:
    .byte <buffer1
    .byte <buffer2
sourceBufferHi:
    .byte >buffer1
    .byte >buffer2
targetBufferLo:
    .byte <buffer2
    .byte <buffer1
targetBufferHi:
    .byte >buffer2
    .byte >buffer1

.segment Default "bars"

bars: // 40 + 21 = 61 bars
    .fill 40, 0
    .byte %00000001, %00000000, %00000001, %00000001, %00000011, %00000011, %00000111, %0001111
    .byte %00111111 
    .byte %01111100, %00111100, %00111000, %00110000, %00110000, %0110000, %10000000, %10000000, %00000000, %10000000, %00000000, %10000000
bars_end:

.segment Default "flash colors"
colors: // 11 + 50 = 61
    .fill 40, BLACK
    .byte LIGHT_GREY, WHITE, WHITE, WHITE, LIGHT_GREY, LIGHT_GREY, GREY, GREY, DARK_GREY
    .byte DARK_GREY, BLUE
    .fill 9, BLACK
    .byte BLACK | $80
colors_end:

.segment Default "stuff"
colorRamOffsetsLo:
    .fill 25, <($d800 + i * 40)
colorRamOffsetsHi:
    .fill 25, >($d800 + i * 40)


lastBarValue:
    .byte


