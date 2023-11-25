#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/internals.inc"
#import "../../includes/cia2_constants.inc"

BasicUpstart2(main)

*= $2000 "Code"
main:
    jsr Kernel.ClearScreen

waitHighBitRasterLine:
    lda VIC.SCREEN_CONTROL_REG
    and #VIC.RASTERLINE_BIT9_MASK
    bne waitHighBitRasterLine
waitRasterLine:
    lda VIC.CURRENT_RASTERLINE_REG
    bne waitRasterLine

    inc currentColorIndex
    ldx currentColorIndex
    lda fadeColors,x
    sta $d020
    sta $d021

    bpl waitHighBitRasterLine

waitForever:
    jmp waitForever

currentColorIndex:
    .byte $ff

fadeColors:
    .byte $0b, $0b, $0b
    .byte $04, $04, $04
    .byte $0e, $0e, $0e
    .byte $05, $05, $05
    .byte $03, $03, $03
    .byte $0d, $0d, $0d
    .byte $01, $01, $01
    .byte $07, $07, $07
    .byte $0f, $0f, $0f
    .byte $0a, $0a, $0a
    .byte $0c, $0c, $0c
    .byte $08, $08, $08
    .byte $02, $02, $02
    .byte $09, $09, $09
    .byte $00, $00, $00
    .byte $f0