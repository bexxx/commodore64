#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = 140
.const ScrollerWidth = 38
.const ScreenPointer = Zeropage.Unused_FB
.const CharsetPointer = Zeropage.Unused_FD
.const ScreenMemoryBase = $0400

BasicUpstart2(main)

main:
    sei

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

    lda VIC.CONTR_REG
    and #VIC.ENABLE_40_COLUMNS_CLEAR_MASK
    sta VIC.CONTR_REG

    cli

waitForever:
    jmp waitForever

interruptHandler:
    inc VIC.BORDER_COLOR
    lda VIC.CONTR_REG                           
    and #%11111000                              
    ora currentXScrollOffset                       
    sta VIC.CONTR_REG 

    ldx #ScrollerWidth - 1
    ldy currentSineIndex
createYPositionData:
    lda sinetable,y
    and #%0000111
    sta yposOffsetWithinChar,x          // lower 3 bits as offset into the character data
    lda sinetable,y
    lsr
    lsr
    lsr
    sta yposOffsetInFullChars,x         // y offset in full character counts (divided by 8)
    iny
    dex
    bpl createYPositionData
//.break
    ldx #ScrollerWidth - 1
drawCharacters:
    ldy yposOffsetInFullChars,x         // this is the row number
    lda screenRowOffsetsLo,y
    sta ScreenPointer
    lda screenRowOffsetsHi,y
    sta ScreenPointer+1
    lda #0
    ldy #0
    sta (ScreenPointer),y
    ldy #120
    sta (ScreenPointer),y
    lda #1
    ldy #40
    sta (ScreenPointer),y
    lda #2
    ldy #80
    sta (ScreenPointer),y
    inc currentSineIndex
    inc ScreenPointer
    bne !+
    inc ScreenPointer+1   
!:
    dex
    bpl drawCharacters

//    lda currentXScrollOffset                    // we determine the next xscroll value and move the characters
//    sec                                         // of the line if needed.
//    .label forwardSpeed = *+1
//    sbc #$01
//    and #%00000111
//    sta currentXScrollOffset


readNextScrollTextCharacter:
.label scrollTextLo = *+1                   
.label scrollTextHi = *+2
    lda scrollText                              // we need to modify either this lda target by code 
    bne moreScrollTextAvailable                 // or use indirect addressing to have a scroll text
                                                // longer than 255 characters (limit of x/y indexing) 
    lda #<scrollText                            // reset to start when we observe 0 byte (end marker)
    sta scrollTextLo
    lda #>scrollText
    sta scrollTextHi
    jmp readNextScrollTextCharacter

moreScrollTextAvailable:  
    dec VIC.BORDER_COLOR

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt to enable next one       
    sta VIC.INTERRUPT_EVENT
    //inc $d020                                   // comment out to disable timing
    jmp $ea31

currentXScrollOffset:
    .byte $07

currentSineIndex:
    .byte $00

currentScrollTextOffet:
    .byte $00

.segment Default "scrolltext"
scrollText:
.text "bexxx is back! the cursor is getting strong in me."
.text "restart text now!..."
.byte $00 

.align $100
.segment Default "Sine data"
sinetable:
    .fill 256, 63 + 63 * sin(toRadians((i * 360.0) / 256))
    //.fill 256, 12*8+3

screenRowOffsetsLo:
    .fill 25, <(ScreenMemoryBase + i * 40)

screenRowOffsetsHi:
    .fill 25, >(ScreenMemoryBase + i * 40)

yposOffsetWithinChar:
    .fill ScrollerWidth, $0

yposOffsetInFullChars:
    .fill ScrollerWidth, $0