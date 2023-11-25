#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/internals.inc"
#import "../../includes/cia2_constants.inc"

BasicUpstart2(main)

*= $2000 "Code"
main:
    jsr Kernel.ClearScreen

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
    BusyWaitForNewScreen()    

    lda lastLine
    cmp #25 + (charTableBlindsEnd - charTableBlindsStart)
    bne blindsLoop

!: jmp !-

drawOneLine:
    ldx #39
.label screenLineLo = * + 1
.label screenLineHi = * + 2
!:  sta $0400,x
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

charTable:
    .fill 25, $a0
charTableBlindsStart:
    .byte $a0, $e3, $f7, $f7, $f8, $f8, $62, $62, $79, $79, $6f, $6f, $6f
    .fill 14, $64
.label charTableBlindsEnd = *-1

lineStartAddressesLo:
    .fill 25, <($0400 + (i * 40))
lineStartAddressesHi:
    .fill 25, >($0400 + (i * 40))
    .fill (charTableBlindsEnd - charTableBlindsStart + 1), $0
