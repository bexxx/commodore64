.const d=19
.const ln=$39
*=$0801
.byte $0c,$08,3,$01,$9e,$20,$32,$30,$36,$32,$00,$00,$00
m:  ldy ln
!:  jsr s
    inx;iny
    cpy #d
    bne !-
    dey;dey
!:  jsr s
    dey;inx
    cpx #d
    bne !-
    dex;dex
!:  jsr s
    dex;dey
    bne !-
!:  jsr s
    iny;dex
    bne !-  
    lda ln
    adc #6
    sta ln
    cmp #3+3*6
    bne m   
!:  beq !-
s:  clc
    jsr $fff0
    lda #'*'
    jsr $ffd2
    rts