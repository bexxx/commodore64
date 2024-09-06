#import "../../includes/vic_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/common.inc"

.const ActiveVicBank = $1
.const CharSetBuffer1Offset = $0000
.const CharSetBuffer2Offset = $0800
.const ScreenBufferOffset = $2000
.const VicRamBase = ActiveVicBank * $4000
.const CharSetBuffer1Start = VicRamBase + CharSetBuffer1Offset
.const CharSetBuffer2Start = VicRamBase + CharSetBuffer2Offset
.const ScreenBufferStart = VicRamBase + ScreenBufferOffset

BasicUpstart2(main)

.segment Default "main"

main:
    jsr init

    // 1. Merge down charachters to single line
    jsr mergeCharacterSetToSingleLine
    // 2. Draw lines from center to sides
    jsr startLinesToSide
    // 3. draw blinds
    jsr blindsLoop
    // 4. fade to white and then to black
    jsr startFadeToBlack
    // rest of demo would start here

waitForever:
    jmp waitForever

init:
    // setup
    jsr copyCharRom // copy chars to $4000
    jsr copyScreenRam // copy screen ram to $6000
    jsr busyWaitForNewScreen
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)
    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2000_MASK, VIC.SELECT_CHARSET_AT_0000_MASK)
    jsr setDefaultColors
    rts

setDefaultColors:
    // set border, screen and char colors to default ones
    lda #BLUE
    sta VIC.SCREEN_COLOR
    lda #LIGHT_BLUE
    sta VIC.BORDER_COLOR
    jsr setColorRamToSingleColor   
    rts

.segment Default "Merge down"
    // modifying the whole charset would take longer than we have cycles on a single frame.
    // however we are slowing down the effect for at least 3 frames per line, so we could
    // split the work during multiple frames (we are less than 2 here) and only switch the charset buffer
    // once modifications are done.

mergeCharacterSetToSingleLine:
    ldx currentTargetBuffer                 // 0 or 1
    lda doubleBufferSourceAddressesHi,x     // address of buffer to read from (previous write buffer)
    sta charSetSourceAddress1Hi
    sta charSetSourceAddress2Hi
    sta charSetSourceAddress3Hi
    lda doubleBufferTargetAddressesHi,x     // address of buffer to write to (previous read buffer)
    sta charSetTargetAddress1Hi
    sta charSetTargetAddress2Hi
    sta charSetTargetAddress3Hi
    
    lda #$8                                 // copy all 8 pages of charset
    sta currentPage

mergeDownByOnePage:
    ldy #$fe
mergeDownByOne:
    // or last two lines into last one ("melt effect")
.label charSetSourceAddress1Hi = * + 2
    lda $ff00,y // charline 6
.label charSetSourceAddress2Hi = * + 2    
    ora $ff01,y // charline 7
.label charSetTargetAddress1Hi = * + 2
    sta $ff01,y // charline 7
    dey

    // move n-1 into n-th line
    ldx #6
.label charSetSourceAddress3Hi = * + 2
!:  lda $ff00,y // charline 5, 4, 3, 2, 1, 0
.label charSetTargetAddress2Hi = * + 2
    sta $ff01,y // charline 6, 5, 4, 3, 2, 1
    dey
    dex
    bne !-

    // insert empty line as first char line
    lda #0
.label charSetTargetAddress3Hi = * + 2    
    sta $ff01,y // char line 0
    dey
    cpy #$fe
    beq doneMergeByOneForPage
    jmp mergeDownByOne

doneMergeByOneForPage:
    inc charSetSourceAddress1Hi
    inc charSetSourceAddress2Hi
    inc charSetSourceAddress3Hi

    inc charSetTargetAddress1Hi
    inc charSetTargetAddress2Hi
    inc charSetTargetAddress3Hi
    
    dec currentPage
    bne mergeDownByOnePage

doneMergeByOne:
    dec currentIteration
    beq doneWithMergingCharaterSet

    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ldx currentTargetBuffer
    ora charsetPointerMasks,x
    sta VIC.GRAPHICS_POINTER

    lda #4
    jsr waitNFrames
   
    txa
    eor #$1  // 00 -> 01, 01 -> 00
    sta currentTargetBuffer

    jmp mergeCharacterSetToSingleLine

doneWithMergingCharaterSet:
    rts

doubleBufferSourceAddressesHi:
    .byte $48
    .byte $40
doubleBufferTargetAddressesHi:
    .byte $40
    .byte $48
currentPage:
    .byte $08
currentTargetBuffer:
    .byte $01
currentIteration:
    .byte $08
charsetPointerMasks:
    .byte VIC.SELECT_CHARSET_AT_0000_MASK
    .byte VIC.SELECT_CHARSET_AT_0800_MASK

.segment Default "Line to sides"

startLinesToSide:
    // define new chars at the end
    ldx #blindsCharSetEnd - blindsCharSet - 1
!:  lda blindsCharSet,x
    sta CharSetBuffer2Start + (256 * 8) - (blindsCharSetEnd - blindsCharSet),x
    dex 
    bpl !-

drawLinesToSide:
    jsr busyWaitForNewScreen  
    jsr drawOneColumn
    bpl drawLinesToSide

    // overwrite the last white columns on the two sides. 
    // just two rows would be enough, but we already have this function
    // and enough time
    lda #LIGHT_BLUE
    jsr setColorRamToSingleColor   

    rts

drawOneColumn:
.label CurrentLeftColumnValue = * + 1
    ldx #19
    lda #$ff

    .for (var row=0; row < 25; row++) {
        sta ScreenBufferStart + row * 40,x
    }
    
    lda #WHITE
    .for (var row=0; row < 25; row++) {
        sta VIC.ColorRamBase + row * 40 + 0,x
    }
    lda #LIGHT_BLUE
    .for (var row=0; row < 25; row++) {
        sta VIC.ColorRamBase + row * 40 + 1,x
    }
    
    lda #$ff
.label CurrentRightColumnValue = * + 1
    ldx #20
    .for (var row=0; row < 25; row++) {
        sta ScreenBufferStart + row * 40,x
    }
    lda #WHITE
    .for (var row=0; row < 25; row++) {
        sta VIC.ColorRamBase + row * 40 - 0,x
    }  
    lda #LIGHT_BLUE
    .for (var row=0; row < 25; row++) {
        sta VIC.ColorRamBase + row * 40 - 1,x
    }   
    inc CurrentRightColumnValue
    dec CurrentLeftColumnValue

    rts

.segment Default "Blinds"

    .var BlindsWaitFrames = 3
blindsLoop:
    ldy firstLine
    sty currentLine
    ldy firstCharacterIndex
    sty currentCharacterIndex
drawBlindsOnScreen:
    ldy currentLine
    lda lineStartAddressesLo,y
    sta screenLineLo
    lda lineStartAddressesHi,y
    beq skipLineDrawing
    sta screenLineHi

    ldx currentCharacterIndex
    lda charTable,x
    jsr drawOneLine
skipLineDrawing:
    inc currentCharacterIndex
    inc currentLine
    lda lastLine
    cmp currentLine
    bpl drawBlindsOnScreen

    dec firstCharacterIndex
    inc lastLine

    lda #BlindsWaitFrames
    jsr waitNFrames   

    lda lastLine
    cmp #26 + (charTableBlindsEnd - charTableBlindsStart)
    bne blindsLoop
    
    rts

 drawOneLine:
    ldx #39
.label screenLineLo = * + 1
.label screenLineHi = * + 2
!:  sta $dead,x
    dex
    bpl !-
    rts   

currentLine:
    .byte 0
firstLine:
    .byte 0
lastLine:
    .byte 1
currentCharacterIndex:
    .byte charTableBlindsEnd-charTable-1
firstCharacterIndex:
    .byte charTableBlindsEnd-charTable-1

    .align $100
charTable:
    .fill 25, $f8
charTableBlindsStart:
    .byte $f9, $fa, $fb, $fc, $fd, $fe, $ff
.label charTableBlindsEnd = * - 1

blindsCharSet:
    .byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff // $f8
    .byte $00, $ff, $ff, $ff, $ff, $ff, $ff, $ff // $f9
    .byte $00, $00, $ff, $ff, $ff, $ff, $ff, $ff // $fa
    .byte $00, $00, $00, $ff, $ff, $ff, $ff, $ff // $fb
    .byte $00, $00, $00, $00, $ff, $ff, $ff, $ff // $fc
    .byte $00, $00, $00, $00, $00, $ff, $ff, $ff // $fd
    .byte $00, $00, $00, $00, $00, $00, $ff, $ff // $fe
    .byte $00, $00, $00, $00, $00, $00, $00, $ff // $ff
blindsCharSetEnd:

lineStartAddressesLo:
    .fill 25, <(ScreenBufferStart + (i * 40))
lineStartAddressesHi:
    .fill 25, >(ScreenBufferStart + (i * 40))
    .fill (charTableBlindsEnd - charTableBlindsStart + 1), $0       // needed to provide a shortcut, see "beq skipLineDrawing" above

.segment Default "Fade to Black"

    .var FadeToBlackWaitFrames = 3
startFadeToBlack:
    BusyWaitForNewScreen()
    
    // the screen is filled with $f8 characters. Instead of clearing screen ram
    // we simply change the 8 bytes of the single character.
    lda #0
    sta CharSetBuffer2Start + $f8 * 8 + 7
    sta CharSetBuffer2Start + $f8 * 8 + 6
    sta CharSetBuffer2Start + $f8 * 8 + 5
    sta CharSetBuffer2Start + $f8 * 8 + 4
    sta CharSetBuffer2Start + $f8 * 8 + 3
    sta CharSetBuffer2Start + $f8 * 8 + 2
    sta CharSetBuffer2Start + $f8 * 8 + 1
    sta CharSetBuffer2Start + $f8 * 8 + 0    

fadeToBlackLoop:
.label CurrentColorIndexValue = * + 1
    ldx #$00
    lda fadeColors,x    
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR
    bmi doneFadingToBlack

    inc CurrentColorIndexValue
    lda #FadeToBlackWaitFrames
    jsr waitNFrames
    jmp fadeToBlackLoop

doneFadingToBlack:
    rts

fadeColors:
    .byte DARK_GREY, VIC.purple, LIGHT_BLUE, GREEN, CYAN, LIGHT_GREEN
    .byte WHITE, YELLOW, LIGHT_GREY, LIGHT_RED, GREY, ORANGE
    .byte RED, BROWN, BLACK, BLACK | $f0

.segment Default "Functions"

copyCharRom: {
    MakeCopyCharRomFunction($01, $00)
}

copyScreenRam: {
    MakeCopyScreenRamFunction($00, $0400, $01, $2000)
}

#import "../../includes/common_gfx_functions.asm"