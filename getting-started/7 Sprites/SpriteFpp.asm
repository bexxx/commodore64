#import "../../includes/cia2_constants.inc"
#import "../../includes/vic_constants.inc"

BasicUpstart2(main)

.namespace Configuration {
    .label ScrollerStartRasterLine = $3a

    .label Irq1AccuZpLocation = $4
    .label Irq1XRegZpLocation = $5
    .label Irq1YRegZpLocation = $6
}

main:
    sei                                         // block other interrupts

    lda #$35                                    // configure ram, no basic, ...
    sta $01                                     // common "demo" memory setup :)

    // we are using vic bank 1 because that one can be used completely
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)
    
    // move screen to the end of bank 1. So last sprite pointer is the ghost byte, but this is ok.
    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_3C00_MASK, VIC.SELECT_CHARSET_AT_0000_MASK)   
    
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
    lda #WHITE
    sta $d021

	lda #%11111111                              // 1 = sprite enable
	sta $d015                                   // enable all 8 sprites
	lda #%11111111                              // 1 = sprite x duplication
	sta $d01d                                   // double x all 8 sprites

	ldx #8 * 2 - 2                              // $d000=sprite0x, $d001=sprite0y, $d002=sprite1x
	lda #<(24 + 7 * 48)                         // x position
setXCoordinates:
	sta $d000,x                                 // set x position
	sec
	sbc #(2 * 24)                               // reduce x position for next sprite
	dex                                         // previous sprite y offset
	dex                                         // previous sprite x offset
	bpl setXCoordinates

    // only sprite 6, 7 and 8 needs to have the MSB set
    lda #%11100000
    sta $d010

	ldx #8 * 2 - 2
	lda #Configuration.ScrollerStartRasterLine - 7
setYCoordinates:
	sta $d001,x                                 // $d000=sprite0x, $d001=sprite0y, $d002=sprite1x
	clc                                         // in order to reuse the same sprite on the whole raster line
    adc #1                                      // the sprites must have different y positions (+1)
    dex                                         // previous sprite x offset
	dex                                         // previous sprite y offset
	bpl setYCoordinates

	ldx #7
	lda #3
    //lda #BLACK
setSpriteColor:
	sta $d027,x
    clc
    adc #1
	dex    
	bpl setSpriteColor

    lda #%11111111
    sta $d01b                                   // set sprite priority to go behind background (which is the ghost byte in our case)

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

    lda #<irq1
    sta $fffe
    lda #>irq1
    sta $ffff

    tsx                                         // save stack pointer in x register

    cli                                         // we allow irqs again during this irq one

    .fill 14, NOP                               // more NOPs to fill more than rest of this raster line

// gets called after 7 cycles of irq setup (push status and PC to stack & jmp to this code)
irq1:
    // Because there are sprites and VIC was blocking the CPU when the previous irq happened
    // this irq is already stabilized at this point.
    // In this line sprites 3-7 are active and will use up the first 10 cycles of the raster line
    // we are at 11 (end of sprite 3-7 fetch) + 7 cycles for irq setup = 18

#if TIMING
    inc $d021                                   // 6: 24
    dec $d021                                   // 6: 30
#else 
    .fill 6, NOP                                // 12: 30
#endif

    txs                                         // 2: 32 get stack pointer from first irq back

    // the sprite y coordinate is not the same as the raster line, but instead one less. This is why
    // we compare against the same value (Configuration.SpriteYCoordinate), because the sprite(s) will
    // only be drawn in the next raster line (see section "Sprites", rule 3, VIC bible).

    ldx #0                                      // 2: 34 sprite extension mask, none extended
    ldy #-1                                     // 2: 36 sprite extension mask, all extended

    .fill 9, NOP                               // 20: 56 (now vic takes over to fetch sprite 0 data)

spriteStretcher:
.for (var i = 0; i < 190; i++) {
    lda #(mod(i,200))                           // 2:  2, select sprite pointer
    sta $7ff8                                   // 4:  6, set sprite 0 pointer
    sta $7ff9                                   // 4: 10, set sprite 1 pointer
    sta $7ffa                                   // 4: 14, set sprite 2 pointer
    sta $7ffb                                   // 4: 18, set sprite 3 pointer
    sta $7ffc                                   // 4: 22, set sprite 4 pointer
    sta $7ffd                                   // 4: 26, set sprite 5 pointer
    sta $7ffe                                   // 4: 30, set sprite 6 pointer
    stx $d017                                   // 4: 34, set sprite extension to off
    sty $d017                                   // 4: 38, set it on or not based on function
    lda #(%1001001 << mod(i, 8)   )             // 2: 40, load ghost byte pattern, 1 = black
    sta $7fff                                   // 4: 44, store ghost byte
//    .if (i != 0 && mod(i, 3) == 0) {
//    lda #(mod(i,16))                            // 2: 46
//    sta $d021                                   // 4: 50
//    }
}

    lda #250                                    // set up bottom irq to switch off screen
    sta $d012
    lda #<irqBottom
    sta $fffe
    lda #>irqBottom
    sta $ffff

    // wait a bit to not start hiding sprites in the middle of the line
    .fill 12, NOP
    ldx #$ff
    stx $7fff

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

    lda #0                                      // 1 = sprite enable
	sta $d015                                   // disnable all 8 sprites

    pla
    rti

irqTop:
    pha
    lsr $d019
    lda #$1b                                    // screen on, 25 lines mode (switch off top and bottom border, screen only on for sprites, no bad lines, no backgound)
    sta $d011

    lda #Configuration.ScrollerStartRasterLine - 1    // 2 rasters needed for double raster irq stabilization
    sta $d012
    lda #<irq0
    sta $fffe
    lda #>irq0
    sta $ffff

    lda #%11111111                              // 1 = sprite enable
	sta $d015                                   // enable all 8 sprites

    pla
    rti

nmi:
    rti

* = $4000

spriteData:

.for (var i=0; i < 200; i++) {
.align 64
spriteLine:
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .byte %10000000, i+1, %00000001
    .fill 14, 0   
}
