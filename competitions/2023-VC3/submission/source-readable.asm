//#import "../../includes/common_gfx_functions.asm"

.const chrout = $ffd2
.const plot = $fff0
.const width = 19
.const height = 19
.const startOffsetX = 0
.const startOffsetY = 0
.const basicLineNumberLsb = $39

*=$0801
.byte $0c,$08,startOffsetX+3,$01,$9e,$20,$32,$30,$36,$32,$00,$00,$00

*=$080e
// uncomment next two lines to change char colors to see which ones are written by this code.
 lda #'e'  
 jsr chrout
main:  
    ldy basicLineNumberLsb // low byte of line number is initialized with "#startOffsetX + 3"

printAndMoveRightDown:
    jsr clearCarryPlotAndChrout
    inx
    iny
    cpy #startOffsetX + width
    bne printAndMoveRightDown
    dey
    dey

printAndMoveLeftDown:
    jsr clearCarryPlotAndChrout
    dey
    inx
    cpx #startOffsetY + height
    bne printAndMoveLeftDown
    dex
    dex

printAndMoveLeftUp:
    jsr clearCarryPlotAndChrout
    dex
    dey
    bne printAndMoveLeftUp

printAndMoveRightUp:
    jsr clearCarryPlotAndChrout
    iny
    dex
    bne printAndMoveRightUp
    
    lda basicLineNumberLsb
    adc #6
    sta basicLineNumberLsb

    cmp #startOffsetX + 3 + 3 * 6
    bne main   

!:    beq !-

clearCarryPlotAndChrout:
    clc
    jsr plot
    lda #'*'
    jsr chrout
    rts