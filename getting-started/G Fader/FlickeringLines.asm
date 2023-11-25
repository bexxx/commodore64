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

waitForSpecificRasterLine:
    lda VIC.CURRENT_RASTERLINE_REG
    cmp #30
    bne waitForSpecificRasterLine

    ldy #$f0
    lda currentScrollIndex
    lda VIC.CONTR_REG



    inc currentColorIndex
    sta VIC.CONTR_REG

    bpl waitHighBitRasterLine

waitForever:
    jmp waitForever

currentScrollIndex:
    .byte $0

xscroll:
    .byte $00 | %000001000
    .byte $04 | %000001000
    .byte $02 | %000001000
    .byte $01 | %000001000
    .byte $01 | %000001000
    .byte $00 | %000001000
    .byte $07 | %000001000
    .byte $04 | %000001000
    .byte $02 | %000001000
    .byte $06 | %000001000
    .byte $06 | %000001000
    .byte $01 | %000001000
    .byte $04 | %000001000
    .byte $03 | %000001000
    .byte $00 | %000001000
    .byte $f0 | %000001000