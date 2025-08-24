.namespace Configuration {
    .label screenRamStart = $0400
}

BasicUpstart2(init)


* = $c000
init:
    ldx #39
!:
    .for (var y=0;y<25;y++) {
        lda #y+1
        sta $0400 + y * 40,x
    }
    dex
    bpl !+ 
    jmp !++
!: jmp !--
!:

    lda #'1'
    sta $0400 + 24

main:
    lda #$fd
!:    cmp $d012
    bne !-
.break

    inc $d020
    ldx #$0e
!:
    lda #0
.for (var row=23; row >=0; row--) {
    lda Configuration.screenRamStart + row * 40 + 1 + (23 - row) + 00,x
    sta Configuration.screenRamStart + row * 40 + 1 + (23 - row) + 39,x
}
    dex
    bmi !+
    jmp !-
!:
    inc $d020

    ldx #6
!:
    .for (var row=0;row<7;row++){
    lda tempChars + row*8 + 1,x
    sta tempChars + row*8 + 0,x
    }
    dex
    bpl !-


    dec $d020
    dec $d020
    jmp main



    tempChars:
        .fill 8*8, 0