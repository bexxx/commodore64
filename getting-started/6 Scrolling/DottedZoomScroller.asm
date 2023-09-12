#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"
#import "../../includes/cia1_constants.inc"

.segmentdef Virtual1 [startAfter= "Default", virtual]

.const FontName = "roger.64c"
.const scrollerStartRow = 10
.const CharsPerLine = 40
.const scrollStartPointer = VIC.ColorRamBase + (CharsPerLine * scrollerStartRow)
.const screenStart = $0400
.const screenStartPointer = screenStart + (CharsPerLine * scrollerStartRow)
.const SkipFrames = 2
.const RasterInterruptLine = $d0

BasicUpstart2(main)

main:
    sei

    // clear screen and set background and border to black
    lda #VIC.black
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR
    jsr Kernel.ClearScreen
    jsr fillScrollerBackgroundWithChars
   
    lda #<interruptHandler                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandler                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    lda #RasterInterruptLine                    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    cli                                         // allow interrupts to happen again
  
!: jmp !-

.align $100
.segment Default "raster irq"
interruptHandler:
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt
    sta VIC.INTERRUPT_EVENT

//    inc $d020    
    // slow down scroller to skip frames if desired
    dec currentFrameCounter
    beq scrollText
    jmp exitInterrupt

scrollText:
    lda #SkipFrames
    sta currentFrameCounter

    dec currentCharIndex
    bpl noCharIndexReset
    lda #$7
    sta currentCharIndex
    
newCharacter:
.label scrollTextPointerLo = *+1
.label scrollTextPointerHi = *+2
    ldx scrolltext
    bne noScrollIndexReset
    lda #<scrolltext
    sta scrollTextPointerLo
    lda #>scrolltext
    sta scrollTextPointerHi
    jmp newCharacter
noScrollIndexReset:
    txa
    cmp #$20
    bne noSpaceFixup
    ldy #2
    sty currentCharIndex

noSpaceFixup:
    jsr copyCharBitmapToBuffer

    inc scrollTextPointerLo
    bne !+
    inc scrollTextPointerHi
!:
noCharIndexReset:
    jsr scrollOneCharToLeft
    jsr insertColumnFromBitmap
      
exitInterrupt:
//    dec $d020
    ReturnFromInterrupt()   

.align $100
.segment Default "scroll text"
scrolltext:
  .text "my first zoom scroller with a custom font. nooiiice! i like it. setting color ram instead of chars looks cute too. bexxx out.         "
  .byte 0

currentCharIndex:
    .byte $00

currentFrameCounter:
    .byte SkipFrames

.align $1000
.segment Default "charset"
charsetBase:
.import c64 FontName

.segment Virtual1 "Bitmap Buffer"   
currentCharacterBitmapBuffer:
    .byte $00,$00,$00,$00,$00,$00,$00,$00


.segment Default "Functions"
scrollOneCharToLeft: {
    ldx #00
!:  lda scrollStartPointer + 0 * 40 + 1,x
    sta scrollStartPointer + 0 * 40 + 0,x
    lda scrollStartPointer + 1 * 40 + 1,x
    sta scrollStartPointer + 1 * 40 + 0,x    
    lda scrollStartPointer + 2 * 40 + 1,x
    sta scrollStartPointer + 2 * 40 + 0,x    
    lda scrollStartPointer + 3 * 40 + 1,x
    sta scrollStartPointer + 3 * 40 + 0,x    
    lda scrollStartPointer + 4 * 40 + 1,x
    sta scrollStartPointer + 4 * 40 + 0,x    
    lda scrollStartPointer + 5 * 40 + 1,x
    sta scrollStartPointer + 5 * 40 + 0,x    
    lda scrollStartPointer + 6 * 40 + 1,x
    sta scrollStartPointer + 6 * 40 + 0,x
    lda scrollStartPointer + 7 * 40 + 1,x
    sta scrollStartPointer + 7 * 40 + 0,x
    inx
    cpx #39
    bne !-

    rts
}

fillScrollerBackgroundWithChars: {
    ldx #00

    // store dots in screen memory
!:  lda #$51 // dot char
    sta screenStartPointer - 1 * 40,x
    sta screenStartPointer + 0 * 40,x
    sta screenStartPointer + 1 * 40,x    
    sta screenStartPointer + 2 * 40,x    
    sta screenStartPointer + 3 * 40,x    
    sta screenStartPointer + 4 * 40,x    
    sta screenStartPointer + 5 * 40,x    
    sta screenStartPointer + 6 * 40,x
    sta screenStartPointer + 7 * 40,x
    sta screenStartPointer + 8 * 40,x

    // write background colors of dot matrix into color ram
    lda #VIC.brown
    sta scrollStartPointer + 0 * 40,x
    sta scrollStartPointer + 1 * 40,x    
    sta scrollStartPointer + 2 * 40,x    
    sta scrollStartPointer + 3 * 40,x    
    sta scrollStartPointer + 4 * 40,x    
    sta scrollStartPointer + 5 * 40,x    
    sta scrollStartPointer + 6 * 40,x
    sta scrollStartPointer + 7 * 40,x
    lda #VIC.dgrey
    sta scrollStartPointer - 1 * 40,x 
    sta scrollStartPointer + 8 * 40,x

    inx
    cpx #40
    bne !-

    rts
}

insertColumnFromBitmap: {
    ldx #0
columnLoop:
    lda #VIC.brown     // color when 0
    asl currentCharacterBitmapBuffer,x
    bcc !+
    lda #VIC.white     // color when 1
.label destinationAddressLo = * + 1
.label destinationAddressHi = * + 2
!:  sta scrollStartPointer + 0 * 40 + 39
    clc
    lda #40
    adc destinationAddressLo
    sta destinationAddressLo
    bcc !+
    inc destinationAddressHi
!:
    inx
    cpx #8
    bne columnLoop

    lda #<(scrollStartPointer + 0 * 40 + 39)
    sta destinationAddressLo
    lda #>(scrollStartPointer + 0 * 40 + 39)
    sta destinationAddressHi

    rts
}

// char is in accumulator
// address will be char value * 8 + charset base
copyCharBitmapToBuffer: {
    // calculate source bitmap address
    // shift left accu 3x to get char val * 8 as low address
    sta sourceBitmapAddressLo
    lda #>charsetBase
    sta sourceBitmapAddressHi

    clc
    asl sourceBitmapAddressLo
    bcc !+
    inc sourceBitmapAddressHi
    clc
!:
    asl sourceBitmapAddressLo
    bcc !+
    inc sourceBitmapAddressHi
    clc
!:
    asl sourceBitmapAddressLo
    bcc startCopy
    inc sourceBitmapAddressHi

startCopy:
    ldx #7
!:
.label sourceBitmapAddressLo = *+1
.label sourceBitmapAddressHi = *+2
    lda charsetBase,x
    sta currentCharacterBitmapBuffer,x
    dex
    bpl !-
    lda #<charsetBase
    sta sourceBitmapAddressLo
    lda #>charsetBase
    sta sourceBitmapAddressLo

    rts
}