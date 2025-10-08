.filenamespace DiagonalScroller

#import "../../../commodore64/includes/irq_helpers.asm"
#import "../../../commodore64/includes/common_gfx_functions.asm"

.namespace Configuration {
    .label ScreenRamStart = $0400
    .label FaderInterruptRasterLine = $fd
    .label AccuZpLocation = $f0
    .label XRegZpLocation = $f1
    .label YRegZpLocation = $f2
}

BasicUpstart2(main)

main:
    sei                                         // don't allow other irqs to happen during setup
    lda #<NmiHandler                            // change nmi vector to unacknowledge "routine"
    sta $0318
    lda #>NmiHandler
    sta $0319
    lda #$00
    sta $dd0e                                   // stop timer a
    sta $dd04                                   // set timer a to 0, after starting nmi will occur immediately
    sta $dd05
    lda #$81
    sta $dd0d                                   // set timer a as source for nmi
    lda #$01
    sta $dd0e                                   // start timer a and trigger nmi

    lda #%01111111                              // disable timer on CIAs mask
    sta $dc0d                                   // disable all CIA1 irqs
    sta $dd0d                                   // disable all CIA2 irqs

    lda #$35
    sta $1                                      // disable ROM

init:
    ldx #39
!:
    .for (var y=0;y<25;y++) {
        lda #y+1
        sta $0400 + y * 40,x
        sta $d800 + y * 40,x
    }
    dex
    bpl !+ 
    jmp !++
!: jmp !--
!:

    lda #'1'
    sta $0400 + 24

    lda $d011
    and #%01110111
    ora #%00000000
    sta $d011

    lda $d016
    and #%11110111
    ora #%00000111
    sta $d016


.break
    irq_set(irq_scroller, Configuration.FaderInterruptRasterLine)

    lsr $d019                                   // ack raster interrupt
    jsr busyWaitForNewScreen

.break
    cli

!:  jmp !-

NmiHandler:
    rti   

* = $3000

irq_scroller:
.break
    sta Configuration.AccuZpLocation        // save register values
    stx Configuration.XRegZpLocation
    sty Configuration.YRegZpLocation

    clc
    lda $d011
    adc #1
    and #%00000111
    ora #%00010000
    sta $d011

    sec
    lda $d016
    sbc #1
    and #%00000111
    sta $d016

    lda counter: #1
    and #%00001111
    beq moveData
    jmp end

moveData:
    inc $d020
    ldx #$0e
!:
    lda #0
.for (var row=23; row >=0; row--) {
    lda Configuration.ScreenRamStart + row * 40 + 1 + (23 - row) + 00,x
    sta Configuration.ScreenRamStart + row * 40 + 1 + (23 - row) + 39,x
    lda $d800 + row * 40 + 1 + (23 - row) + 00,x
    sta $d800 + row * 40 + 1 + (23 - row) + 39,x
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

end:
    inc counter

    lsr $d019

    ldy Configuration.YRegZpLocation
    ldx Configuration.XRegZpLocation
    lda Configuration.AccuZpLocation

    rti

    tempChars:
        .fill 8*8, 0