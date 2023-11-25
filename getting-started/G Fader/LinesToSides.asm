#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/internals.inc"
#import "../../includes/cia2_constants.inc"

BasicUpstart2(main)

*= $2000 "Code"
main:
    jsr Kernel.ClearScreen

!:
    BusyWaitForNewScreen()    
    jsr drawOneColumn
    bpl !-

    lda #19
    sta leftIndex
    lda #20
    sta rightIndex

    dec currentCharIndex
    bpl !-

!: jmp !-

drawOneColumn:
    dec $d020
    ldx leftIndex
    ldy currentCharIndex
    lda charTableStart,y
!:
    .for (var row=0; row < 25; row++) {
        sta $0400 + row * 40,x
    }
    ldx rightIndex
    .for (var row=0; row < 25; row++) {
        sta $0400 + row * 40,x
    }
    inc $d020
    
    inc rightIndex
    dec leftIndex
    rts

currentCharIndex:
    .byte charTableEnd-charTableStart

leftIndex:
    .byte 19

rightIndex:
    .byte 20

charTableStart:
    .byte $a0, $e3, $f7, $f8, $62, $79, $6f
charTableEnd:

