#import "../../../commodore64/includes/vic_constants.inc"

.filenamespace Scroller
#import "configuration.asm"

* = Configuration.ScrollerInterruptAddress      // align to $100 to avoid page crossing and branches (costs 1 extra cycle)
.segment Default "Scroller"

irq0:                                           // classic double irq stabilization first
    sta Configuration.Irq1AccuZpLocation        // save register values
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    inc $d012                                   // set irq for next line
    lsr $d019                                   // ack current irq

    cli                                         // we allow irqs again during this one

    lda #<irq1
    sta $fffe
    lda #>irq1
    sta $ffff

    tsx                                         // save stack pointer in x register
    .fill 14, NOP                               // more NOPs to fill more than rest of this raster line

// gets called with after 7 cycles of irq setup (push status and PC to stack & jmp to this code)
irq1:
    // and additional jitter of 2 or 3 (we know it was a NOP before)
    lsr $d019                                   // 6: 15
    .fill 20, NOP                               // 40: 55, yeah, a loop has less bytes
    lda $d012                                   // 4: 59
    cmp $d012                                   // 4: 63 or 64 (1 on new raster lines)
    beq fixcycle                                // 2 or 3, depending on 1 cycle jitter

fixcycle:
    // now stable on cycle 3 of raster line
    txs                                         // 2: 5 get stack pointer from first irq back

scrollerTop: {

fldLoop:
    lda fldCounter: #Configuration.FldLines     // 2: 7
    beq doneFld                                 // 2: 9
    lda $d011                                   // 4: 13
    clc                                         // 2: 15
    adc #1                                      // 2: 17
    and #$7                                     // 2: 19
    eor #%00011000                              // 2: 21
    sta $d011                                   // 4: 25
    .fill 15, NOP                               // 32: 57
    bit $2
    dec fldCounter                              // 6: 63
    jmp fldLoop                                 // 4: as before

doneFld:
    lda currentXOffset                          // set current xscroll for the scroller
    sta $d016

#if EnableMusic
#if Timing
    inc $d020
#endif
    jsr music.play                              // while scroller is displaying, we have enough time to play music (~7*8 raster lines)
#if Timing
    dec $d020
#endif
#endif

    lda #Configuration.RasterLineScrollerBottomIrq  // set next irq for after the scroller
    sta $d012

    lda #<scrollerBottom
    sta $fffe
    lda #>scrollerBottom
    sta $ffff

exitInterrupt:
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

scrollerBottom: {
    sta Configuration.Irq1AccuZpLocation
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    lsr $d019                                   // ack event
    bcs rasterIrq                               // check whether carry is set to see if it's really coming from a raster
    jmp exitInterrupt

rasterIrq:
    lda #%00001000                              // restore default value for $d016 to not mess up top of screen
    sta $d016

    lda #%00011011                              // restore default value for $d011 to not mess up top of screen
    sta $d011

    ldx sineIndex: #0                           // update fld code for next frame
    lda sineValues,x
    sta scrollerTop.fldCounter
    inc sineIndex

#if Timing
    inc $d020
#endif

    lda currentXOffset                          // calc next d016 / x offset value
    sec
    sbc #Configuration.ScrollSpeed
    sta currentXOffset
    bmi insertColumnOnRight
    jmp setupNextInterrupt

insertColumnOnRight:                            // need to scroll more than one, so we need to insert a column on the right
    and #7
    sta currentXOffset

    // unrolled loop to copy screen memory and color ram ine column to the left,
    // just wanted to learn how to do speed code.
!:
    .for (var j = 0; j < Configuration.CharHeight ; j++) {
        .for (var i = 0; i < 39 ; i++) {
            lda Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + j) * 40 + i + 1
            sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + j) * 40 + i + 0
            lda $d800 + (Configuration.ScrollerYOffset + j) * 40 + i + 1
            sta $d800 + (Configuration.ScrollerYOffset + j) * 40 + i + 0
        }
    }

loadNextScrollTextCharacter:
    // insert new column of a character to the rightmost character
.label scrollTextAddressLo = * + 1
.label scrollTextAddressHi = * + 2
    ldx scrolltext
    bne stillMoreScrollText
    lda #<scrolltext
    sta scrollTextAddressLo
    lda #>scrolltext
    sta scrollTextAddressHi
    jmp loadNextScrollTextCharacter

stillMoreScrollText:
    lda charWidths,x
    sta currentCharWidth

    lda charStartLo,x
    clc
    adc currentCharSlice
    sta Configuration.CharSourceLoZp
    sta Configuration.CharColorSourceLoZp

    lda charStartHi,x
    sta Configuration.CharSourceHiZp
    lda charColorsStartHi,x
    sta Configuration.CharColorSourceHiZp
    bcc noPageCrossing
    inc Configuration.CharSourceHiZp
    inc Configuration.CharColorSourceHiZp

noPageCrossing:
    ldy #0
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 0) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 0) * 40 + 39

    ldy #40
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 1) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 1) * 40 + 39

    ldy #80
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 2) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 2) * 40 + 39

    ldy #120
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 3) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 3) * 40 + 39

    ldy #160
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 4) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 4) * 40 + 39

    ldy #200
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 5) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 5) * 40 + 39

    ldy #240
    lda (Configuration.CharSourceLoZp),y
    sta Configuration.ScreenRamStartAddress + (Configuration.ScrollerYOffset + 6) * 40 + 39
    lda (Configuration.CharColorSourceLoZp),y
    sta $d800 + (Configuration.ScrollerYOffset + 6) * 40 + 39

    inc currentCharSlice
    lda currentCharSlice
    cmp currentCharWidth: #4
    bne setupNextInterrupt

    lda #0                                      // reset to first column of char
    sta currentCharSlice

    inc scrollTextAddressLo                     // update code to read next scrolltext char
    bne setupNextInterrupt                      // this supports more than 256 characters in scroller
    inc scrollTextAddressHi

setupNextInterrupt:
#if Timing
    dec $d020
#endif

#if Integrated
    lda #Configuration.RasterLinePetsciiIrq
    sta $d012
    lda #<Configuration.PetsciiScrollerAnimationCodeAddress
    sta $fffe
    lda #>Configuration.PetsciiScrollerAnimationCodeAddress
    sta $ffff
#else
    lda #Configuration.RasterLineScrollerTopIrq
    sta $d012
    lda #<irq0
    sta $fffe
    lda #>irq0
    sta $ffff
#endif

exitInterrupt:
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

    .align $100
sineValues:
    .fill $100,24 - abs(24 * cos(toRadians(i*360/64)))

currentXOffset:
    .byte 7
currentCharSlice:
    .byte 0

rowStartAddressesLo:
    .fill 25, <Configuration.ScreenRamStartAddress + i * 40
rowStartAddressesHi:
    .fill 25, >Configuration.ScreenRamStartAddress + i * 40

// define a datastructure with coordinates in the petmate screen for each used character and its width
.struct CharCoords{x, y, width}
.var charCoords = List().add(
    CharCoords(00, 36, 4), // 00, @, unused
    CharCoords(00, 00, 4), // 01, a
    CharCoords(04, 00, 4), // 02, b
    CharCoords(08, 00, 4), // 03, c
    CharCoords(12, 00, 4), // 04, d
    CharCoords(16, 00, 4), // 05, e
    CharCoords(20, 00, 4), // 06, f
    CharCoords(24, 00, 4), // 07, g
    CharCoords(28, 00, 4), // 08, h
    CharCoords(32, 00, 2), // 09, i
    CharCoords(34, 00, 3), // 10, j
    CharCoords(00, 14, 4), // 11, k
    CharCoords(04, 14, 3), // 12, l
    CharCoords(07, 14, 5), // 13, m
    CharCoords(12, 14, 4), // 14, n
    CharCoords(16, 14, 4), // 15, o
    CharCoords(20, 14, 4), // 16, p
    CharCoords(24, 14, 4), // 17, q
    CharCoords(29, 14, 4), // 18, r
    CharCoords(33, 14, 4), // 19, s
    CharCoords(00, 21, 4), // 20, t
    CharCoords(04, 21, 4), // 21, u
    CharCoords(08, 21, 4), // 22, v
    CharCoords(12, 21, 5), // 23, w
    CharCoords(17, 21, 4), // 24, x
    CharCoords(21, 21, 4), // 25, y
    CharCoords(25, 21, 4), // 26, z

    // 5 non supported chars like []
    CharCoords(00, 36, 4), // 27
    CharCoords(00, 36, 4), // 28
    CharCoords(00, 36, 4), // 29
    CharCoords(00, 36, 4), // 30
    CharCoords(00, 36, 4), // 31

    CharCoords(04, 36, 2), // 32 space
    CharCoords(00, 29, 3), // 33, !
    CharCoords(24, 36, 4), // 34, "
    CharCoords(24, 29, 6), // 35, #

    // 3 non supported chars
    CharCoords(00, 36, 4), // 36
    CharCoords(00, 36, 4), // 37
    CharCoords(00, 36, 4), // 38

    CharCoords(07, 29, 2), // 39, '
    CharCoords(30, 29, 3), // 40, (
    CharCoords(33, 29, 4), // 41, )

    // 1 non supported chars
    CharCoords(00, 36, 4), // 42

    CharCoords(14, 33, 4), // 43, +
    CharCoords(05, 29, 2), // 44, ,
    CharCoords(15, 29, 4), // 45, -
    CharCoords(03, 29, 2), // 46, .

    // 1 non supported char
    CharCoords(00, 36, 4), // 47

    CharCoords(36, 43, 4), // 48, 0
    CharCoords(00, 42, 4), // 49, 1
    CharCoords(04, 42, 4), // 50, 2
    CharCoords(08, 42, 4), // 51, 3
    CharCoords(12, 43, 4), // 52, 4
    CharCoords(26, 42, 4), // 53, 5
    CharCoords(20, 42, 4), // 54, 6
    CharCoords(24, 42, 4), // 55, 7
    CharCoords(28, 42, 4), // 56, 8
    CharCoords(32, 42, 4), // 57, 9

    CharCoords(09, 29, 2), // 58, :

    // 2 non supported chars
    CharCoords(00, 36, 4), // 59
    CharCoords(00, 36, 4), // 60

    CharCoords(11, 29, 4), // 61, =
    CharCoords(30, 36, 6), // 62, mapped to <3
    CharCoords(19, 29, 4) // 63, ?
)

// now with the coordinates it's easy to calculate the addresses of each character
charStartLo:
    .fill charCoords.size(), <Configuration.PetsciiCharsStartAddress + charCoords.get(i).y * 40 + charCoords.get(i).x
charStartHi:
    .fill charCoords.size(), >Configuration.PetsciiCharsStartAddress + charCoords.get(i).y * 40 + charCoords.get(i).x
charColorsStartLo:
    .fill charCoords.size(), <Configuration.PetsciiCharsColorsStartAddress + charCoords.get(i).y * 40 + charCoords.get(i).x
charColorsStartHi:
    .fill charCoords.size(), >Configuration.PetsciiCharsColorsStartAddress + charCoords.get(i).y * 40 + charCoords.get(i).x
charWidths:
    .fill charCoords.size(), charCoords.get(i).width

scrolltext:
    .text "                                                        "
    .text @"the question \"where the fuck is emmering?\""
    .text " was not hard enough to stop us from attending, because free beer and barbeque, a "
    .text "huge screen and good old school fun is the natural habitat for the real slackers!  we come thirsty, hungry and most "
    .text "importantly  -  we come in petscii!"
    .text "  "
    .text "we had no idea what to bring as a present, but as a great philosopher once wrote: "
    .byte 34
    .text "scroller gehn immer!"
    .byte 34
    .text ".  i "
    .text "learned a lot while coding this scroller.  now it's like a new pair of underwear.  at first it's constrictive, but after "
    .text "a while it becomes a part of you."
    .text "  "
    .byte 62, 62, 62
    .text " thanks for setting up this nice event far out in the boondocks (actually in my neighborhood) -bexxx"
    .text "    "
    .text "least but not last, a warm beer to welcome the new member of the slackers spielmannskorps, the one and "
    .text "only spider jerusalem.  i'm sure we will go through some brutal hangovers (and maybe also work on some demos) together!!!elf -el jefe."
    .text "    "
    .text "hold my beer. -ldx#40"
    .text "    "
    .text "have a drink on me! -higgie"
    .text "    "
    .byte 62, 62, 62
    .text "    "
    .text "graphics by ldx#40, clayboy, higgie and bexxx.  dirart by copass.  music by spider jerusalem.  code by ldx#40 and "
    .text "bexxx.  text wrangling by el jefe."
    .text "  "
    .text "slackers - partytime! excellent!"
    .text "  "
    .byte 62, 62, 62
    .byte $0

* = Configuration.PetsciiCharsStartAddress
    .segment Default "Petscii Screens"
petsciiScreens:
    .import source "charset.asm"