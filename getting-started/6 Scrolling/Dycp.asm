#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/cia2_constants.inc"

.const RasterInterruptLine = 2                          // raster line to start with dycp irq
.const ScrollerWidth = 40                               // how wide is the scroller (in characters)

.const ScreenMemoryBase1 = $4400                        // base address of screen ram, buffer 1
.const ScreenMemoryBase2 = $6000                        // base address of screen ram, buffer 2
.const CharsetBase1 = $7800                             // base address of charset, buffer 1
.const CharsetBase2 = $7000                             // base address of charset, buffer 1
.const WaitFrames = 0                                   // how many frames need to pass before doing a dycp step

.const ScreenBufferPointer = Zeropage.Unused_FB         // ZP pointer, used write to screen ram
.const SourceCharsetPointer = Zeropage.Unused_FD        // ZP pointer, used to read from charset data
.const TargetCharsetPointer = Zeropage.Unused_FB        // ZP pointer, used to write to charset data
.const CurrentChar = Zeropage.Unused_02                 // current char from scroll text

.var music = LoadSid("../E Custom Charset/retrospectful.sid")

* = music.location "Music" 
.fill music.size, music.getData(i)

BasicUpstart2(main)
* = $2000

main:
    jsr disableDisplay

    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)    

    lax #0
    tay
    lda #music.startSong - 1
    jsr music.init

    jsr clearScreen1
    jsr clearScreen2

    lda #VIC.black
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    jsr setupBackgroundColors
    jsr setupSprites

    sei
    // clear the @ character which is used around the 2 dycp characters to clear the screen
    lda #$0
    ldx #7
!:
    sta CharsetBase1,x
    sta CharsetBase2,x
    dex
    bpl !-

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

    // set 38 column mode to hide partial chars at the sides
    lda VIC.CONTR_REG
    and #VIC.ENABLE_40_COLUMNS_CLEAR_MASK
    sta VIC.CONTR_REG

    // initialize scroll text buffer with first 39 characters
    ldx #ScrollerWidth - 1
    lda #' '
!:  sta scrollTextBuffer,x
    dex
    bpl !-

    cli

    // GO!
    jsr enableDisplay

waitForever:
    jmp waitForever

interruptHandler:
    //inc VIC.BORDER_COLOR.
   
    // wait for given number of frames if necessary
    dec framesToWait
    bpl waitMore
    lda #WaitFrames
    sta framesToWait
    jmp dycp
waitMore:
    jmp exitDycp

dycp:
    // configure VIC to use new charset and screen location
    // (use the buffers that were written before)
    ldy currentTargetBuffer
    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora charsetPointerMasks,y
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    ora screenramPointerMasks,y
    sta VIC.GRAPHICS_POINTER

    // set x scroll to current value
    lda VIC.CONTR_REG                           
    and #%11111000                              
    ora currentXScrollOffset                       
    sta VIC.CONTR_REG      

    dec currentXScrollOffset                    // determine next x scroll offset
    bpl !+                                      // if less then 0, we need to reset to 7
    lda #$7
    sta currentXScrollOffset   
    jsr scrollOneCharacter

!:
    // create two buffers with the positional data.
    // yposOffsetWithinChar will contain all offsets 0-7 within the first of the two chars per column
    // yposOffsetInFullChars will contain the offset in char rows for the first of two characters per column
    ldx #ScrollerWidth - 1
    ldy currentSineIndex1
createYPositionData:
    lda sinetable,y
    and #%0000111
    sta yposOffsetWithinChar,x                  // lower 3 bits as offset into the character data
    lda sinetable,y
    lsr
    lsr
    lsr
    sta yposOffsetInFullChars,x                 // y offset in full character counts (divided by 8)
    iny                                         // advance sine index
    dex
    bpl createYPositionData

    // fix up code to write to current screen ram buffer
    ldy currentTargetBuffer
    lda screenRowOffsetsTableLo,y
    sta screenPointerLo
    lda screenRowOffsetsTableHi,y
    sta screenPointerHi

    // draw the two characters in a column based on the offset in rows (yposOffsetInFullChars)
    lda #(ScrollerWidth * 2) | $80              // we use 2 characters per column, starting at 1 AND the upper 128 chars of the charset
    sta CurrentChar
    ldx #ScrollerWidth - 1                      // iterate through all columns (x coords)
drawCharacters:
    ldy yposOffsetInFullChars,x                 // get row offset for current column
    txa                                         // store current column in accu
    clc                     
    adc screenRowOffsetsLo,y                    // add x (in rows) to y offset
    sta ScreenBufferPointer
.label screenPointerLo = *+1
.label screenPointerHi = *+2
    lda $dead,y
    sta ScreenBufferPointer+1
    bcc !+
    inc ScreenBufferPointer+1
!:
    lda #'@'                                    // write @ as clearning character above and below two characters of this column
    ldy #(0 * 40)                               // above column
    sta (ScreenBufferPointer),y
    ldy #(3 * 40)                               // below column
    sta (ScreenBufferPointer),y
    lda CurrentChar
    ldy #(2 * 40)                               // second row of column
    sta (ScreenBufferPointer),y
    dec CurrentChar
    lda CurrentChar
    ldy #(1 * 40)                               // first row of column
    sta (ScreenBufferPointer),y
    dec CurrentChar
    dex
    bpl drawCharacters

    // clear charset data for the characters used in the columns
    ldy currentTargetBuffer
    lda clearCharsetLo,y
    sta clearCharsetPointerLo
    lda clearCharsetHi,y
    sta clearCharsetPointerHi
.label clearCharsetPointerLo = *+1
.label clearCharsetPointerHi = *+2
    jsr $dead

    ldy currentTargetBuffer
    lda charsetOffsetRowsTableLo,y
    sta TargetCharsetAddressLo
    lda charsetOffsetRowsTableHi,y
    sta TargetCharsetAddressHi

    // now copy the character data into the charset based on the offset within the first of the 
    // two characters used in the column
    ldx #ScrollerWidth - 1
copyScrollCharacterDataIntoColumnCharacters:
    lda scrollTextBuffer,x                      // load scroll text character for this x position
    asl                                         // multiply with 8 to get source offset
    asl                                         // if we only use 32 characters max in scroll text
    asl
    sta SourceCharsetPointer                    // store into ZP pointer
    lda #>CharsetBase1                           
    sta SourceCharsetPointer + 1                
    bcc !+
    inc SourceCharsetPointer + 1                // fix hi address for chars > 32
    clc
!:
    lda yposOffsetWithinChar,x                  // get y offset within character
    adc charsetOffsetRowsLo,x                   // add to the offset of the character
    sta TargetCharsetPointer                    // store in ZP pointer (lo)

.label TargetCharsetAddressLo = *+1
.label TargetCharsetAddressHi = *+2
    lda $dead,x                                 // here we need to set hi part of address as well
    sta TargetCharsetPointer + 1                // store in ZP pointer (hi)

    ldy #7          
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey            
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y
    dey
    lda (SourceCharsetPointer),y
    sta (TargetCharsetPointer),y

    dex
    bpl copyScrollCharacterDataIntoColumnCharacters

setupNextIterationValues:
    inc currentSineIndex1                       // determine next sine value index

    lda currentTargetBuffer
    eor #$1  // 00 -> 01, 01 -> 00
    sta currentTargetBuffer

exitDycp:  
    //dec VIC.BORDER_COLOR

    jsr music.play

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt to enable next one       
    sta VIC.INTERRUPT_EVENT
    jmp $ea31

scrollOneCharacter:
    ldx #0
!:
    lda scrollTextBuffer+1,x
    sta scrollTextBuffer+0,x
    inx
    cpx #39
    bne !-
    
.label scrollTextPointerLo = *+1
.label scrollTextPointerHi = *+2
!:  lda scrollText
    bne !+
    lda #<scrollText
    sta scrollTextPointerLo
    lda #>scrollText
    sta scrollTextPointerHi
    jmp !-
!:  sta scrollTextBuffer,x
    inc scrollTextPointerLo
    bne !+
    inc scrollTextPointerHi

!:  rts

clearScreen1:
MakeClearScreenFunction(VIC.Bank0, ScreenMemoryBase1)

clearScreen2:
MakeClearScreenFunction(VIC.Bank0, ScreenMemoryBase2)

clearCharset1:
    lda #$0
    ldx #(ScrollerWidth * 2) - 1
!:
    sta (CharsetBase1 + $0400 + 8 + 0 * 80),x    // + 8 because we do need to overwrite @ == 0 character
    sta (CharsetBase1 + $0400 + 8 + 1 * 80),x    // + 0-8 to unroll this loop and overwrite all 8 bytes of a character
    sta (CharsetBase1 + $0400 + 8 + 2 * 80),x    // + $0400 to target upper 128 characters of charset (| $80)
    sta (CharsetBase1 + $0400 + 8 + 3 * 80),x
    sta (CharsetBase1 + $0400 + 8 + 4 * 80),x
    sta (CharsetBase1 + $0400 + 8 + 5 * 80),x
    sta (CharsetBase1 + $0400 + 8 + 6 * 80),x
    sta (CharsetBase1 + $0400 + 8 + 7 * 80),x
    dex
    bpl !-
    rts

clearCharset2:
    lda #$0
    ldx #(ScrollerWidth * 2) - 1
!:
    sta (CharsetBase2 + $0400 + 8 + 0 * 80),x    // + 8 because we do need to overwrite @ == 0 character
    sta (CharsetBase2 + $0400 + 8 + 1 * 80),x    // + 0-8 to unroll this loop and overwrite all 8 bytes of a character
    sta (CharsetBase2 + $0400 + 8 + 2 * 80),x    // + $0400 to target upper 128 characters of charset (| $80)
    sta (CharsetBase2 + $0400 + 8 + 3 * 80),x
    sta (CharsetBase2 + $0400 + 8 + 4 * 80),x
    sta (CharsetBase2 + $0400 + 8 + 5 * 80),x
    sta (CharsetBase2 + $0400 + 8 + 6 * 80),x
    sta (CharsetBase2 + $0400 + 8 + 7 * 80),x
    dex
    bpl !-
    rts

setupBackgroundColors:
    lda #VIC.white
    ldx #$0
!:  sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    dex
    bne !-

    .for (var i=0;i<25;i++) {
        lda #VIC.dgrey
        sta $d800+0+i*40
        lda #VIC.grey
        sta $d800+1+i*40
        lda #VIC.lgrey
        sta $d800+2+i*40
    }

    .for (var i=0;i<25;i++) {
        lda #VIC.lgrey
        sta $d800+36+i*40
        lda #VIC.grey
        sta $d800+37+i*40
        lda #VIC.dgrey
        sta $d800+38+i*40
    }
    rts

setupSprites:
    lda #VIC.black
    sta VIC.SPRITE_MULTICOLOR_1
    lda #VIC.grey
    sta VIC.SPRITE_MULTICOLOR_2

    lda #VIC.lgrey
    sta VIC.SPRITE_MULTICOLOR_3_0
    sta VIC.SPRITE_MULTICOLOR_3_1
    sta VIC.SPRITE_MULTICOLOR_3_2
    sta VIC.SPRITE_MULTICOLOR_3_3
    sta VIC.SPRITE_MULTICOLOR_3_4
    sta VIC.SPRITE_MULTICOLOR_3_5
    sta VIC.SPRITE_MULTICOLOR_3_6
    sta VIC.SPRITE_MULTICOLOR_3_7

    lda #$ff
    sta VIC.SPRITE_BG_PRIORITY

    lda #$ff
    sta VIC.SPRITE_ENABLE                   

    // stretch all sprites
    lda #$ff
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y

    // set x coords
    lda #(71 + 0 * 48)
    sta VIC.SPRITE_0_X
    lda #<(71 + 1 * 48)
    sta VIC.SPRITE_1_X
    lda #<(71 + 2 * 48)
    sta VIC.SPRITE_2_X
    lda #<(71 + 3 * 48)
    sta VIC.SPRITE_3_X

    lda #<(71 + 0 * 48)
    sta VIC.SPRITE_4_X
    lda #<(71 + 1 * 48)
    sta VIC.SPRITE_5_X
    lda #<(71 + 2 * 48)
    sta VIC.SPRITE_6_X
    lda #<(71 + 3 * 48)
    sta VIC.SPRITE_7_X

    // set y coords
    lda #(51 + 0 * 48)
    sta VIC.SPRITE_0_Y
    sta VIC.SPRITE_1_Y
    sta VIC.SPRITE_2_Y
    sta VIC.SPRITE_3_Y
    
    lda #(93 + 0 * 48)
    sta VIC.SPRITE_4_Y
    sta VIC.SPRITE_5_Y
    sta VIC.SPRITE_6_Y
    sta VIC.SPRITE_7_Y

    // configure sprite pointers for all 8 sprites
    // because of double buffering, we need to set up sprite pointers 
    // at the two locations (end of screen mem buffer)
    lda #(sprite_1 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_0_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_0_OFFSET
    lda #(sprite_2 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_1_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_1_OFFSET
    lda #(sprite_3 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_2_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_2_OFFSET
    lda #(sprite_4 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_3_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_3_OFFSET
    lda #(sprite_5 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_4_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_4_OFFSET
    lda #(sprite_6 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_5_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_5_OFFSET
    lda #(sprite_7 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_6_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_6_OFFSET
    lda #(sprite_8 / 64)
    sta ScreenMemoryBase1 + VIC.SPRITE_POINTER_7_OFFSET
    sta ScreenMemoryBase2 + VIC.SPRITE_POINTER_7_OFFSET

    // set them all to multicolor mode
    ldx #$ff
    stx VIC.SPRITE_HIRES
    
    rts

#import "../../includes/common_gfx_functions.asm"


currentXScrollOffset:
    .byte $07
currentSineIndex1:
    .byte $00
currentSineIndex2:
    .byte $04
framesToWait:
    .byte WaitFrames
scrollTextBuffer:
    .fill ScrollerWidth, $0
scrollText:
    .text "hello beautiful people of the c-64 demoscene! "
    .byte $00 

screenramPointerMasks:
    .byte VIC.SELECT_SCREENBUFFER_AT_2000_MASK
    .byte VIC.SELECT_SCREENBUFFER_AT_0400_MASK
charsetPointerMasks:
    .byte VIC.SELECT_CHARSET_AT_3000_MASK
    .byte VIC.SELECT_CHARSET_AT_3800_MASK
currentTargetBuffer:
    .byte $00
doubleBufferSourceAddressesHi:
    .byte $38
    .byte $30

.align $100
sinetable:
    .import binary "output.bin"

.align $100
screenRowOffsetsLo:
    .fill 25, <(ScreenMemoryBase1 + i * 40)
screenRowOffsets1Hi:
    .fill 25, >(ScreenMemoryBase1 + i * 40)
screenRowOffsets2Hi:
    .fill 25, >(ScreenMemoryBase2 + i * 40)

screenRowOffsetsTableLo:
    .byte <screenRowOffsets1Hi, <screenRowOffsets2Hi
screenRowOffsetsTableHi:
    .byte >screenRowOffsets1Hi, >screenRowOffsets2Hi

clearCharsetLo:
    .byte <clearCharset1, <clearCharset2
clearCharsetHi:
    .byte >clearCharset1, >clearCharset2

yposOffsetWithinChar:
    .fill ScrollerWidth, $0
yposOffsetInFullChars:
    .fill ScrollerWidth, $0
charsetOffsetRowsLo:
    .fill ScrollerWidth, i * 16 + 8

charsetOffsetRowsTableLo:
    .byte <charsetOffsetRows1Hi, <charsetOffsetRows2Hi
charsetOffsetRowsTableHi:
    .byte >charsetOffsetRows1Hi, >charsetOffsetRows2Hi

.align $100
charsetOffsetRows1Hi:
    .fill ScrollerWidth, >(CharsetBase1 + $0400 + i * 16 + 8)
charsetOffsetRows2Hi:
    .fill ScrollerWidth, >(CharsetBase2 + $0400 + i * 16 + 8)

* = CharsetBase1
    .import c64 "cuddly.64c"

* = $5800

// Byte 64 of each sprite contains multicolor (high nibble) & color (low nibble) information
.align $100 
// sprite 0 / multicolor / color: $0f
sprite_1:
    .byte $2a,$a0,$00,$25,$70,$00,$25,$70
    .byte $00,$25,$70,$00,$25,$70,$00,$25
    .byte $70,$00,$25,$70,$00,$25,$70,$00
    .byte $25,$70,$00,$25,$70,$00,$25,$70
    .byte $00,$25,$70,$00,$25,$70,$00,$25
    .byte $70,$00,$25,$70,$00,$25,$70,$00
    .byte $25,$70,$00,$25,$70,$00,$25,$70
    .byte $00,$25,$7a,$a0,$25,$55,$58,$8f

// sprite 1 / multicolor / color: $0f
sprite_2:
    .byte $2a,$aa,$a8,$25,$55,$57,$25,$7f
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$7e,$57,$25,$55,$57,$8f

// sprite 2 / multicolor / color: $0f
sprite_3:
    .byte $2a,$aa,$a8,$25,$55,$57,$25,$55
    .byte $57,$25,$55,$57,$25,$55,$57,$2f
    .byte $fe,$57,$00,$02,$57,$00,$02,$57
    .byte $00,$02,$57,$00,$02,$57,$00,$02
    .byte $57,$00,$02,$57,$00,$02,$57,$00
    .byte $02,$57,$00,$02,$57,$00,$02,$57
    .byte $00,$02,$57,$00,$02,$57,$00,$02
    .byte $57,$0a,$aa,$57,$09,$55,$5c,$8f

// sprite 3 / multicolor / color: $0f
sprite_4:
    .byte $2a,$a2,$aa,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$ff,$25,$70
    .byte $00,$25,$7a,$a8,$09,$55,$57,$8f

// sprite 4 / multicolor / color: $0f
sprite_5:
    .byte $25,$7e,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$7a
    .byte $57,$25,$55,$57,$2f,$ff,$fc,$8f

// sprite 5 / multicolor / color: $0f
sprite_6:
    .byte $25,$7f,$fc,$25,$70,$00,$25,$70
    .byte $00,$25,$70,$00,$25,$70,$00,$25
    .byte $70,$00,$25,$70,$00,$25,$70,$00
    .byte $25,$70,$00,$25,$70,$00,$25,$70
    .byte $00,$25,$70,$00,$25,$70,$00,$25
    .byte $70,$00,$25,$70,$00,$25,$7a,$aa
    .byte $25,$55,$57,$25,$55,$57,$25,$55
    .byte $57,$25,$55,$57,$0f,$ff,$ff,$8f

// sprite 6 / multicolor / color: $0f
sprite_7:
    .byte $0f,$fe,$57,$00,$02,$57,$00,$02
    .byte $57,$00,$02,$57,$00,$02,$57,$00
    .byte $02,$57,$00,$02,$57,$00,$02,$57
    .byte $00,$02,$57,$00,$02,$57,$00,$02
    .byte $57,$00,$02,$57,$00,$02,$57,$00
    .byte $02,$57,$00,$02,$57,$2a,$aa,$57
    .byte $25,$55,$57,$25,$55,$57,$25,$55
    .byte $57,$25,$55,$57,$3f,$ff,$fc,$8f

// sprite 7 / multicolor / color: $0f
sprite_8:
    .byte $03,$ff,$57,$00,$02,$57,$2a,$a2
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$25,$72,$57,$25
    .byte $72,$57,$25,$72,$57,$25,$72,$57
    .byte $25,$72,$57,$25,$72,$57,$25,$72
    .byte $57,$25,$72,$57,$2f,$f2,$ff,$8f
