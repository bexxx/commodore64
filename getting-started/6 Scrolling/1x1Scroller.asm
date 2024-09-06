#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

// badlines on $33, $3b, $43, $4b, $53, $5b, YSCROLL is 3 by default
.const RasterInterruptLine = ($33 + 3*8 - 1)    // fire on good line before bad line of char line
.const TextBufferOffset = ($0400 + 3*40)        // scroll 3rd text line
.const ControlCommandBoundary = $f7             // value before speed bytes. speed byte
                                                // this value will be used to add or sub from xscroll
.const ColorRamOffsetScroller = ($d800 + 3*40)

BasicUpstart2(main)

main:
    jsr Kernel.ClearScreen

    ldx #39
!:  lda borderTop,x
    sta ($0400 + 2*40),x        
    lda borderBottom,x
    sta ($0400 + 4*40),x 
    dex
    bpl !-

    lda #$00
    sta $d020
    sta $d021

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
    

    lda #<scrollText
    sta scrollTextLo
    lda #>scrollText
    sta scrollTextHi

    lda VIC.CONTR_REG
    and #VIC.ENABLE_40_COLUMNS_CLEAR_MASK
    sta VIC.CONTR_REG

    cli                                         // allow interrupts to happen again
    //rts
  !:                                          // remove line before and uncomment to not go back to basic
    jmp !-

.align $100                                     // align on the start of a new page
.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem
                                                // helpful to check whether it all fits into the same page
interruptHandler:
    //dec $d020                                   // comment out, leave in to check timing
    lda VIC.CONTR_REG                           
    and #%11111000                              
    ora currentXScrollOffset                       
    tax                                         // wait until we hit border before changing xscroll
    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora #VIC.SELECT_CHARSET_AT_2000_MASK
    stx VIC.CONTR_REG       
    sta VIC.GRAPHICS_POINTER                       
                                               
    lda VIC.CONTR_REG                           // already calculate the 0 xscroll value for the next
    and #11111000                               // character line after the scrolling line
    ora #00000011
waitToCharacterLineEnd:
    ldx VIC.CURRENT_RASTERLINE_REG              // wait until we hit the last raster line of the scroller
    cpx #(RasterInterruptLine + 8)              
    bne waitToCharacterLineEnd

    ldx #8                                      // waste some more cycles until we are in the border of
!:  dex                                         // the line to again avoiding that the next line will
    bne !-                                      // be scrolled too
    nop
    nop
    nop
    sta VIC.CONTR_REG    
    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora #VIC.SELECT_CHARSET_AT_1000_MASK
    sta VIC.GRAPHICS_POINTER        

scrollForward:                                  // not that we are passed the scrolled line with the raster
    lda currentXScrollOffset                    // we determine the next xscroll value and move the characters
    sec                                         // of the line if needed.
    .label forwardSpeed = *+1
    sbc #$01
    and #%00000111
    sta currentXScrollOffset
    bcc scrollBufferForward
    jmp noCharacterInsertForward

scrollBufferForward:    
    ldx #0                                      // move all characters one position to the left
!:                                              // loop forward to not overwrite character before
    lda TextBufferOffset+1,x                    // reading
    sta TextBufferOffset,x
    inx
    cpx #39
    bne !-

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
    cmp #ControlCommandBoundary                 // if there is a character, check whether it's a special one
    bcc insertCharacterForward                  // nope, just insert into buffer
    sec
    sbc #ControlCommandBoundary                 // first speed byte is one more than control bounday value
    sta forwardSpeed                            // store are new speed (modify code)

    inc scrollTextLo                            // increment scroll text pointer, lo (carry is clear)
    bne !+                                      // increment pointer hi on overflow
    inc scrollTextHi
!:  jmp readNextScrollTextCharacter             // read next character after special one

insertCharacterForward:
    sta TextBufferOffset+39                     // after moving the line to the left,
    inc scrollTextLo                            // insert new character on the right
    bne noCharacterInsertForward                // and update scroll text pointer
    inc scrollTextHi

noCharacterInsertForward:
    ldx #$00
!:  lda ColorRamOffsetScroller+1,x
    sta ColorRamOffsetScroller,x
    inx
    cpx #39
    bne !-
    
    ldx currentColorCycleOffset
!:
    lda colorCycle,x
    bpl !+
    ldx #$0
    stx currentColorCycleOffset
    jmp !-
!:
    sta ColorRamOffsetScroller+39
    inc currentColorCycleOffset

//    .break
    ldx currentColorFlashOffset
 !: lda colorFlash,x
    bpl !+
    ldx #$00
    stx currentColorFlashOffset
    jmp !-

!:  ldx #39
!:  sta ($d800+2*40),x
    sta ($d800+4*40),x
    dex
    bpl !-
    inc currentColorFlashOffset

exit:
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt to enable next one       
    sta VIC.INTERRUPT_EVENT
    //inc $d020                                   // comment out to disable timing
    jmp $ea31

currentXScrollOffset:
    .byte $07
currentColorCycleOffset:
    .byte $00
currentColorFlashOffset:
    .byte $00

.segment Default "scrolltext"
scrollText:
.text "speed 1: bexxx is back! the cursor is getting strong in me."
.byte $f9
.text "speed 2: bexxx is back! the cursor is getting strong in me."
.byte $fa
.text "speed 3: bexxx is back! the cursor is getting strong in me."
.byte $fb
.text "speed 4: bexxx is back! the cursor is getting strong in me."
.byte $fc
.text "speed 5: bexxx is back! the cursor is getting strong in me."
.byte $fd
.text "speed 6: bexxx is back! the cursor is getting strong in me."
.byte $fe
.text "speed 7: bexxx is back! the cursor is getting strong in me."
.byte $ff
.text "speed 8: bexxx is back! the cursor is getting strong in me."
.byte $f8
.text "restart text now!..."
.byte $00 

borderTop:
	.byte $20, $64, $64, $6F, $6F, $79, $62, $62, $62, $20, $0E, $16, $12, $20, $32, $20, $0F, $0C, $04, $20, $14, $0F, $20, $03, $0F, $04, $05, $2E, $2E, $2E, $20, $62, $62, $62, $79, $6F, $6F, $64, $64, $20
borderBottom:	
    .byte $20, $63, $63, $77, $77, $78, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $E2, $78, $77, $77, $63, $63, $20

.align $100
.segment Default "color cycle"
colorCycle:
.byte BROWN, BROWN, ORANGE, ORANGE,LIGHT_RED, LIGHT_RED,YELLOW, YELLOW,WHITE
.byte YELLOW, YELLOW,LIGHT_RED, LIGHT_RED,ORANGE, ORANGE,BROWN, BROWN
.byte $f0 

colorFlash:
.byte DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY 
.byte DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY 
.byte DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY,DARK_GREY 
.byte GREY, GREY, GREY, GREY, GREY
.byte GREY, GREY, GREY, GREY, GREY
.byte LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY
.byte LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY
.byte YELLOW, WHITE, WHITE, WHITE, WHITE 
.byte YELLOW, WHITE, WHITE, WHITE, WHITE 
.byte LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY
.byte LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY, LIGHT_GREY
.byte GREY, GREY, GREY, GREY, GREY
.byte GREY, GREY, GREY, GREY, GREY
.byte GREY, GREY, GREY, GREY, GREY




.byte $f0

.align $2000
.segment Default "charset"
.import c64 "roger.64c"