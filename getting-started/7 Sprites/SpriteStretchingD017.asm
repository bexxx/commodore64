BasicUpstart2(main)

.namespace Configuration {
    .label SpriteYCoordinate = $40
    .label ZpStretchTable = ZpStretchTableLo
    .label ZpStretchTableLo = $2
    .label ZpStretchTableHi = $3

    .label Irq1AccuZpLocation = $4
    .label Irq1XRegZpLocation = $5
    .label Irq1YRegZpLocation = $6
}

#define TIMING

* = $1000
main:
    sei                                         // block other interrupts

    lda #$35                                    // configure ram, no basic, ...
    sta $01

    lda #$7f                                    // no CIA interrupts
    sta $dc0d
    sta $dd0d

    lda #$1b                                    // set default screen config, no raster MSB
    sta $d011

    lda #250
    sta $d012                                   // set raster IRQ at line 250
    lda #<irqBottom                             // start with switching off screen
    sta $fffe
    lda #>irqBottom
    sta $ffff

    lda #$01
    sta $d01a                                   // select Raster as a source of VIC IRQ
    lsr $d019                                   // ack any pending raster IRQ if any

    lda #<nmi                                   // just rti here
    sta $fffa
    lda #>nmi
    sta $fffb

    lda $dc0d                                   // read CIAs
    lda $dd0d

    lda #BLACK                                  // set colors
    sta $d020
    //sta $d021                                 // uncomment to hide ghost byte

    jsr updateStretchTable                      // initially update table

	lda #%11111111                              // 1 = sprite enable
	sta $d015                                   // enable all 8 sprites

	ldx #8 * 2 - 2                              // $d000=sprite0x, $d001=sprite0y, $d002=sprite1x
	lda #$f0                                    // x position
setXCoordinates:
	sta $d000,x                                 // set x position
	sec
	sbc #24                                     // reduce x position for next sprite
	dex                                         // previous sprite y offset
	dex                                         // previous sprite x offset
	bpl setXCoordinates

	ldx #8 * 2 - 2
	lda #Configuration.SpriteYCoordinate
setYCoordinates:
	sta $d001,x                                 // $d000=sprite0x, $d001=sprite0y, $d002=sprite1x
	dex                                         // previous sprite x offset
	dex                                         // previous sprite y offset
	bpl setYCoordinates

    // set sprite pointers
    ldx #0
	ldy #(spriteData / 64)
	tya
    sta $07f8 + 0,x                             // Set sprite pointers to display this code :).
    sta $07f8 + 4,x                             // Set sprite pointers to display this code :).
    iny
    inx
	tya
    sta $07f8 + 0,x                             // Set sprite pointers to display this code :).
    sta $07f8 + 4,x                             // Set sprite pointers to display this code :).
    iny
    inx
	tya
    sta $07f8 + 0,x                             // Set sprite pointers to display this code :).
    sta $07f8 + 4,x                             // Set sprite pointers to display this code :).

    // use all 8 sprites to have the same timing as a full sprite row, just have empty ones on the side
    ldx #0
	ldy #(emptySprite / 64)
    iny
    tya
    sta $07f8 + 3,x                             // Set sprite pointers to display this code :).
    sta $07f8 + 7,x                             // Set sprite pointers to display this code :).

	ldx #7
	lda #LIGHT_GREY
setSpriteColor:
	sta $d027,x                                 // set x position
	dex                                         // previous sprite y offset
	bpl setSpriteColor

    lda #%11111111
    sta $d01b                                   // set sprite priority to go behind background (which is the ghost byte in our case)

    lda #$ff                                    // set ghost byte, last byte in current VIC bank, pattern when VIC could not read new data
	sta $3fff

    cli                                         // setup done, now allow irqs like raster interrupt

waitForever:
    jmp waitForever

.align $100
.segment Default "SpriteStretcher"

irq0: {                                         // classic double irq stabilization first
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
    .fill 20, NOP                                // 6: 55
    lda $d012                                   // 4: 59
    cmp $d012                                   // 4: 63 or 64 (1 on new raster lines)
    beq fixcycle                                // 2 or 3, depending on 1 cycle jitter
fixcycle:
    // now stable on cycle 3 of raster line
    txs                                         // 2: 5 get stack pointer from first irq back

    // the sprite y coordinate is not the same as the raster line, but instead one less. This is why
    // we compare against the same value (Configuration.SpriteYCoordinate), because the sprite(s) will
    // only be drawn in the next raster line (see section "Sprites", rule 3, VIC bible).

    //.fill 19, NOP                             // 38: 43 (ok, this is wasteful, use a loop instead)
    ldx #7                                      // 2: 7
!:  dex                                         // 14: 21  
    bne !-                                      // 6*3+2: 41
    nop                                         // 2: 43

	ldx #0                                      // 2: 45 (it's already 0 from loop before in case we need 2 bytes or 2 cycles)
    ldy #0                                      // 2: 47, just the invert of the ghostbyte, because in the initial iteration, this is not set before
stretchLoop:
    // the y-duplication bits must be set and kept stable between cycles 56 and 16. If they are set, the line will be drawn
    // again (duplicated), otherwise the next sprite row will be used.
	lda d017Values,x                            // 4: 51 $ff will stretch, 0 will step one line of graphics in the sprite
    sta $d017                                   // 4: 55

    // here sprite data fetch stalls the CPU and we restart in the beginning of the next line after 10 cycles
    // FLTs chart shows fetch between 58 and 10 == 16 cycles plus 3 cycles BA before 58
    sty $3fff                                   // 4: 14
    lda #0                                      // 2: 16
	sta $d017                                   // 4: 20, just for demonstration purposes, this can go later too

    nop                                         // 2: 22
    bit $02                                     // 3: 25
    lda timingValues,x                          // 4: 29
    bne delayWithSprites                        // 3,2: 32, 31

delayWithoutSprites:
    // we need to fill 19 cycles that we lost for sprites before
    bit $02                                     // 3: 3
    ldy #3                                      // 2: 5
!:  dey                                         // 3*2: 11
    bne !-                                      // 2*3+2: 19

delayWithSprites:
    lda $3fff                                   // 4: 36, load current ghostbyte
    eor #%11111111                              // 2: 38, invert bit pattern
    tay                                         // 2: 40, store into y register to store on start of screen

	inx                                         // 2: 42
	cpx #150                                    // 2: 44
	bne stretchLoop                             // 3, 2: 47 when looping, otherwise we do not really care

	lda #$1b                                    // default screen confg, stop FLD
	sta $d011

    lda #%00110101                              // change ghostbyte pattern again
	sta $3fff

    lda #250                                    // set up bottom irq to switch off screen
    sta $d012
    lda #<irqBottom
    sta $fffe
    lda #>irqBottom
    sta $ffff

    cli                                         // clear interrupt flag to allow bottom irq to get executes while
                                                // long running table updates run

#if TIMING
    inc $d020
#endif
	jsr updateStretchTable                      // update stretch table for the next frame
#if TIMING
    dec $d020
#endif

exitInterrupt:
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

irqBottom:
    pha
    lsr $d019
    lda #$0                                     // switch off screen, set 24 lines mode
    sta $d011

    lda #51                                     // next interrupt on line 51
    sta $d012
    lda #<irqTop
    sta $fffe
    lda #>irqTop
    sta $ffff
    pla
    rti

irqTop:
    pha
    lsr $d019
    lda #$1b                                    // screen on, 25 lines mode (switch off top and bottom border, screen only on for sprites, no bad lines, no backgound)
    sta $d011

    lda #Configuration.SpriteYCoordinate - 2    // 2 rasters needed for double raster irq stabilization
    sta $d012
    lda #<irq0
    sta $fffe
    lda #>irq0
    sta $ffff
    pla
    rti

nmi: 
    rti

updateStretchTable:
    // determine start address to read sine values from
    lda sineStartIndex: #<sineValues
    sta sineValueLo
    lda #>sineValues
    sta sineValueHi

    lda #21
    sta spriteRowCounter
    lda #$ff
    sta currentStretchValue

    ldx #0                                      // x register is our index into the data tables
newSineValue:
.label sineValueLo = * + 1
.label sineValueHi = * + 2
    ldy sineValues                              // pure sine value, need to

sineValuesLoop:
    // precalculate values to check whether we need to burn more cycles
    lda spriteRowCounter: #$ff
    sta timingValues,x                          // positive or 0 values

    beq !+

    lda currentStretchValue: #$ff               // first data must be 0
!:
    sta d017Values,x
    bne notFirstStretchRow
    lda #$ff
    sta currentStretchValue
notFirstStretchRow:

    inx
    cpx #131
    beq exit

    dey
    bpl sineValuesLoop

    lda spriteRowCounter
    beq noMoreSpriteData
    dec spriteRowCounter
noMoreSpriteData:

    inc sineValueLo

    lda #$0
    sta currentStretchValue

    jmp newSineValue

exit:
    inc sineStartIndex                          // next frame start with the next sine values
    rts

.align $100
    .segment Default "sine table"
sineValues:
    .fill $100, 4 + 4 * cos(toRadians(i*360/32))

	.align $100                                 // avoid page crossing when accessing this table, with this, all lda's will take 4 cycles.
d017Values:
	.fill $100, 0
timingValues:
	.fill $100, 0
colors:
	.fill $100, random() * 16

* = $0900
.align 64
.segment Default "Sprites"
spriteData:

// Sprite #1
	.byte 255, 255, 255
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   3
	.byte  12,   3, 225
	.byte  15,   7, 240
	.byte  15, 231,  48
	.byte  15, 230,  48
	.byte  14,  54,  48
	.byte  12,  22,  96
	.byte  12,  23, 224
	.byte  12,  23, 128
	.byte  14, 119,   0
	.byte   7, 227, 254
	.byte   7, 192, 254
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

.align 64
// Sprite #2
	.byte 255, 255, 255
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   6
	.byte 195,  98, 196
	.byte 103,  38,  76
	.byte  54,  52, 108
	.byte  28,  20,  40
	.byte   8,  12,  56
	.byte  28,   8,  24
	.byte  62,  28,  24
	.byte  50,  22,  60
	.byte  97,  18,  36
	.byte  65, 178,  98
	.byte  64,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

.align 64
// Sprite #3
	.byte 255, 255, 255
	.byte   0,   8,   6
	.byte   0, 124,   6
	.byte  15, 248,  14
	.byte 127, 226,  14
	.byte  63, 199,  24
	.byte  25, 195, 152
	.byte   0, 193, 248
	.byte   0, 225, 240
	.byte   0, 224, 240
	.byte   0, 240, 112
	.byte   0, 112,  96
	.byte   0, 112,  32
	.byte   0,  32,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

emptySprite:
.align 64
    .byte 255, 255, 255
    .fill 63-6, 0
    .byte 255, 255, 255