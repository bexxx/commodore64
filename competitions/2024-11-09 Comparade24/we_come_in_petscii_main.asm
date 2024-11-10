#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/cia2_constants.inc"
#import "../../../commodore64/includes/common.inc"

#import "configuration.asm"

BasicUpstart2(main)
.segment Default "main"

main:
    // disable NMI by no acking one which prevents new ones.
    // taken from codebase 64: https://codebase64.org/doku.php?id=base:nmi_lock
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

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta $dc0d                                   // disable all CIA1 irqs
    sta $dd0d                                   // disable all CIA2 irqs

    lda #$35
    sta $1                                      // disable ROM

    // set up ZP pointer
    lda #<$03ff
    sta Configuration.ScreenPointerZP
    sta Configuration.ScreenPointer2ZP
    lda #>$03ff
    sta Configuration.ScreenPointerHiZP
    sta Configuration.ScreenPointer2HiZP
    lda #<$d7ff
    sta Configuration.ColorPointerZP
    sta Configuration.ColorPointer2ZP
    lda #>$d7ff
    sta Configuration.ColorPointerHiZP
    sta Configuration.ColorPointer2HiZP

    // set up raster irq
    lda #$1b
    sta $d011                                   // set MSB of raster line, it's bit 7
    lda #Configuration.RasterLineFaderInitialIrq
    sta $d012
    lda #<Fader.irqFader                        // setup custom irq handler address
    sta $fffe
    lda #>Fader.irqFader
    sta $ffff
    lda #%00000001
    sta $d01a                                   // enable raster irq

    BusyWaitForNewScreen()

    lda $dc0d                                   // ACK CIA 1 interrupts in case there are pending ones
    lsr $d019                                   // ACK VIC interrupt in case there is a pending one

    cli                                         // now we are done and can enable interrupts again

#if DebugView
    lda #206
    sta (Configuration.ScrollerYOffset - 1)*40+20+$400
    sta (Configuration.ScrollerYOffset - 1)*40+0+$400
    sta (Configuration.ScrollerYOffset - 1)*40+39+$400

    lda #0
    sta (Configuration.ScrollerYOffset + 0)*40+39+$d800
    lda #1
    sta (Configuration.ScrollerYOffset + 1)*40+39+$d800
    lda #2
    sta (Configuration.ScrollerYOffset + 2)*40+39+$d800
    lda #3
    sta (Configuration.ScrollerYOffset + 3)*40+39+$d800
    lda #4
    sta (Configuration.ScrollerYOffset + 4)*40+39+$d800
    lda #5
    sta (Configuration.ScrollerYOffset + 5)*40+39+$d800

    // draw some chars in colums to whether scolling works with filling in columns on the right
    ldx #Configuration.ScrollerYOffset
printrows:
    lda rowStartAddressesLo,x
    sta targetAddressLo
    lda rowStartAddressesHi,x
    sta targetAddressHi

    lda letter: #'a' + 39
    ldy #39
printChar:
.label targetAddressLo = * + 1
.label targetAddressHi = * + 2
    sta $dead,y
    sec
    sbc #1
    dey
    bpl printChar
    inx
    cpx #25
    bne printrows
#endif

waitForever:
    jmp waitForever

NmiHandler:
    rti                                         // just rti, no ack

.import source "we_come_in_petscii_scroller.asm"
.import source "we_come_in_petscii_fader.asm"

#if TheWholeShebang

#if EnableMusic
* = music.location "Music"
.fill music.size, music.getData(i)
#endif

* = Configuration.PetsciiScrollerAnimationCodeAddress
.segment Default "LDX#40 petscii animation code"
.import binary "comparade_ldx_$4000.prg", 2

#endif