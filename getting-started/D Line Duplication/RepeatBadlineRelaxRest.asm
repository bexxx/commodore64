BasicUpstart2(main)


 main:

    ldy #25
!:
    lda char: #'a'
    ldx #39
!:
    sta screenaddress: $0400,x
    dex
    bpl !-

    clc
    lda screenaddress
    adc #40
    sta screenaddress
    bcc !+
    inc screenaddress+1
!:
    inc char
    dey
    bne !---

!:    jmp !-



    // we multiplay this code 25 times, but we might be done earlier and need to
    // skip some of these fragments

    ldy $d012           // n-1
    iny                 // n                 
    iny                 // n + 1

    ldx #repetition
!:
    tya
    and #%11111000
    lda $d011
    lda #00             // 2: 02
    sta $d011           // 4: 06
    lda #00             // 2: 08
    dex                 // 2: 10
    bpl !-              // 2,3
    bne !+              // 3: 11
    cpy #$fa            // 2: 13
    bmi                 //
    jmp ende
!:  



    ldx #repetition

ende: