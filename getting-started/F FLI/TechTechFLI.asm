#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = $2e
.const LogoHeightInChars = 11
.const TechTechHeight = LogoHeightInChars * 8
// ram location of the FLI-bug cover sprite
.const CoverSpriteLocation = $7f80

BasicUpstart2(main)

.segment Default "main"
main:
    sei

    // set border and background color to black
    lda #VIC.black
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    lda #VIC.blue
    sta VIC.TXT_COLOUR_1
    lda #VIC.lblue
    sta VIC.TXT_COLOUR_2

    //jsr drawAlphabetOnFirstColumn             // to see which lines move around
    jsr fillColorRam
    jsr spreadScreenBuffer    
    //jsr copyCharsetToBank1
    jsr generateDataTables
    jsr generateCoverSprite
    jsr enableCoverSprites
    jsr updateUnrolledFliCode                   // initialize the unrolled code with first values

    lda #<interruptHandler                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandler                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    lda #RasterInterruptLine                    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    lda #$02
    sta $dd00

    cli                                         // allow interrupts to happen again

  !:
    jmp !-

.align $1000                                    // align on the start of a new page
.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem
                                                // helpful to check whether it all fits into the same page
interruptHandler:
    // when this code is started, 38-45 cycles already passed
    // in the current raster line (completing asm instruction, saving return address and rgisters)
    // Now we create a new raster interrupt, but this time, we are in control of excuted commands
    // The remaining cycles in this raster line are not sufficient to set this up, so we select
    // the current rasterline + 2.
    lda #<secondRasterInterrupt                 // (2 cycles) configure 2nd raster interrupt
    sta Internals.InterruptHandlerPointerRamLo  // (4 cycles)
    lda #>secondRasterInterrupt                 // (2 cycles)
    sta Internals.InterruptHandlerPointerRamHi  // (4 cycles)
    tsx                                         // (2 cycles) get stack pointer into x register
    stx secondRasterInterrupt.stackpointerValue // (4 cycles) modify code of 2nd interrupt handler to return correct SP
    nop                                         // (2 cycles)
    nop                                         // (2 cycles)
    nop                                         // (2 cycles)
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // (2 cycles) ack raster interrupt to enable 2nd one
                                                // total
                                                // 26 cycles
                                                // start was 38 + 26 cycles passed, we're now in the next raster line
    // since first interrupt started 64-71 cycles have passed
    // and we are definitely on raster line start+1.
    // From this line, we already used 1-8 cycles.
    inc VIC.CURRENT_RASTERLINE_REG              // (6 cycles) set raster interrupt to raster start + 2
                                                // $d012 was increased to start+1 by vic already
    sta VIC.INTERRUPT_EVENT                     // (4 cycles) ack interrupt
    cli                                         // (2 cycles) enable interrupts again                                            

    // Still on raster line start + 1 
    // so far we used up 13-20 cycles

    // waste some more cycles
    ldx #$08                                    // 2 cycles
!:
    dex                                         // 8 * 2 cycles = 16 cycles
    bne !-                                      // 7 * 3 cycles = 21 cycles
                                                // 1 * 2 cycles =  2 cycles
                                                // total:
                                                //                41 cycles

    // Up to here 54-61 cycles we used, now we are waiting with NOPs for
    // the next raster interrupt to be in full control of the command executed
    // when the interrupt started. Any fixed 2 cyle operaton would work, but
    // NOPs do not have any side effect.
    
    nop                                         // 2 cycles (56)
    nop                                         // 2 cycles (58)
    nop                                         // 2 cycles (60)
    nop                                         // 2 cycles (62)
    nop                                         // 2 cycles (64)
    nop                                         // 2 cycles (66)

secondRasterInterrupt: {
    // we are now in rasterline start + 2 and so 
    // we used exactly 38 or 39 cycles.
    // This is safe to assume, because the interrupt happened on execution of NOPs.
    //
    // Now we can waste exactly the amount of cycles that are left on this raster line 
    // (24 or 25 because 63-(38 or 39)).
    .label stackpointerValue = *+1
    ldx #$00                                    // (2 cycles) Dummy for 1. stack pointer
    txs                                         // (2 cycles) Transfer to stack
    nop                                         // (2 cycles)
    nop                                         // (2 cycles)
    nop                                         // (2 cycles)
    bit $01                                     // (3 cycles) modifies flags, but we need an odd cycle count
    ldx VIC.CURRENT_RASTERLINE_REG              // (4 cycles) granted that we are still on raster + 2
    nop                                         // (2 cycles) 
    nop                                         // (2 cycles) 
    cpx VIC.CURRENT_RASTERLINE_REG              // (4 cycles) still on raster line start + 2?
                                                // total:
                                                // 25 cycles, here we are either on cycles 63 or 64

    beq finalRasterInterruptStart               // (3 cycles) still on raster + 2, waste one cycle for branch taken on beq
                                                // (2 cycles) just continue running, we are on raster + 3
                                                // make sure this command and target are in the same page, otherwise
                                                // this beq takes an extra cycle and messes up the precise timing.
}

finalRasterInterruptStart:
                                                // 03
    lda #2                                      // 05: 2
    sta $dd00                                   // 09: 4
    nop; nop; nop;                              // 15: 6
    bit $01                                     // 18: 3
    bit $01                                     // 21: 3
    nop                                         // 23: 2

    nop; nop; nop; nop; nop;                    // 33: 10
    nop; nop; nop; nop; nop;                    // 43: 10
    nop; nop; nop; nop; nop;                    // 53: 10
    nop;                                        // 55: 2

    // unroll code to handle each raster line (will be bad lines, 20-23 cycles)
.var unrolledFliSegmentSize = 0
startFliTechTech:
.var actualRasterLine = 0
.for (var row = 0; row < TechTechHeight+2; row++) {
    .eval actualRasterLine = row + RasterInterruptLine + 3
    .label unrolledFliSegmentStart = *
    lda #$18 | (actualRasterLine & 7)           // 57/17: 2 set YSCROLL to last 3 bits of current rasterline to cause a bad line condition
    sta VIC.SCREEN_CONTROL_REG                  // 61/21: 4   
    lda #$20                                    // 63/23: 2 (gets modified through code later)
    sta VIC.GRAPHICS_POINTER                    // 04: 4 
    lda #%00001000                              // 06: 2 (gets modified through code later)
    sta VIC.CONTR_REG                           // 10: 4
    //nop                                       // 12: 2 the cover sprites will take these cycles, uncomment when sprites are left out
    //bit $01                                   // 13: 2
    .label unrolledFliSegmentEnd = *
    .eval unrolledFliSegmentSize = unrolledFliSegmentEnd-unrolledFliSegmentStart
}

    // use invalid graphics mode to cover bugs
    lda #$7b
    sta VIC.SCREEN_CONTROL_REG
    lda #$15
    sta $d018
    lda #$03
    sta $dd00
    lda #8
    sta $d016

    ldx #89         // waste cycles until we've covered a full screen row
!:  dex
    bne !-
    lda #%00010011
    sta VIC.SCREEN_CONTROL_REG

    // update lda values in unrolled loop
    jsr updateUnrolledFliCode

exit:
    lda #<interruptHandler                      // restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo
    lda #>interruptHandler
    sta Internals.InterruptHandlerPointerRamHi

    lda #RasterInterruptLine                    // restore first raster line
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt
    sta VIC.INTERRUPT_EVENT

    jmp Internals.InterruptHandlerPointer       // jump to system timer interrupt code

.align $1000
.segment Default "Data Tables" 

.align $100
SineValues:
    .fill 256, 55.5 + 56 * cos(toRadians((i * 360.0) / 256))
SineValuesEnd:

SineValuesForD016:
    .fill $100, $0
SineValuesForD016Overflow:
    .fill $100, $0

SineValuesForD018:
    .fill $100, $0
SineValuesForD018Overflow:
    .fill $100, $0

.segment Default "Functions"

// we could simple generate this data, but then we would use bytes stored on disk which
// slows down loading and needs time decrunching. Instead we are transforming the sine cosine values
// and generate 2 tables out of it with double length (to allow x-indexing to overflow after 256 bytes) 
generateDataTables:
    ldx #$0
    ldy #$0
!:  lda SineValues,y
    and #7                                  // take lower 3 bits only for XScroll in $d016
    ora #VIC.ENABLE_MULTICOLOR_MASK         // multi color mode
    sta SineValuesForD016,x                 // 
    sta SineValuesForD016Overflow,x         // 
    lda SineValues,y                        // divide by 8, multiply by 16 to get videoram index
    asl                                     // equals multiply by two
    and #$f0
    adc #$20                                // carry is clear from asl because sine values < 128
    sta SineValuesForD018,x
    sta SineValuesForD018Overflow,x
    iny
    inx
    bne !-

    rts

spreadScreenBuffer:
    // Set up the videoram banks for the tech-tech effect
    //
    // The first videoram bank at $4800 contains the 'logo' in its
    // default (left-aligned) position, every next videoram bank contains
    // the 'logo' shifted one column to the right. This is what makes the
    // tech-tech effect possible.
    //
    // optional:
    // Right now, for the 'logo', we simply copy the BASIC screen data
    // from $0400

    ldx #$0
!:
    lda $4800,x                                 // make this $0400 when using start screen
    //sta $4800 +  0,x                          // screen in bank 1,  0 chars offset, uncomment when using start screen
    sta $4c00 +  1,x                            // screen in bank 1,  1 chars offset
    sta $5000 +  2,x                            // screen in bank 1,  2 chars offset
    sta $5400 +  3,x                            // screen in bank 1,  3 chars offset
    sta $5800 +  4,x                            // screen in bank 1,  4 chars offset
    sta $5c00 +  5,x                            // screen in bank 1,  5 chars offset
    sta $6000 +  6,x                            // screen in bank 1,  6 chars offset
    sta $6400 +  7,x                            // screen in bank 1,  7 chars offset
    sta $6800 +  8,x                            // screen in bank 1,  8 chars offset
    sta $6c00 +  9,x                            // screen in bank 1,  9 chars offset
    sta $7000 + 10,x                            // screen in bank 1, 10 chars offset
    sta $7400 + 11,x                            // screen in bank 1, 11 chars offset
    sta $7800 + 12,x                            // screen in bank 1, 12 chars offset
    sta $7c00 + 13,x                            // screen in bank 1, 13 chars offset
    
    lda $4900,x                                 // make this $0500 when using start screen
    //sta $4900 +  0,x                          // uncomment when using start screen
    sta $4d00 +  1,x
    sta $5100 +  2,x
    sta $5500 +  3,x
    sta $5900 +  4,x
    sta $5d00 +  5,x
    sta $6100 +  6,x
    sta $6500 +  7,x
    sta $6900 + 08,x
    sta $6d00 + 09,x
    sta $7100 + 10,x
    sta $7500 + 11,x
    sta $7900 + 12,x    
    sta $7d00 + 13,x
    inx
    bne !-

    rts

copyCharsetToBank1:
    lda Zeropage.PORT_REG                       // enable rom charset at $d000
    and #Zeropage.ENABLE_CHAREN_MASK
    sta Zeropage.PORT_REG               

    ldx #0
!:  lda $d000,x
    sta $4000,x
    lda $d100,x
    sta $4100,x
    lda $d200,x
    sta $4200,x
    lda $d300,x
    sta $4300,x
    lda $d400,x
    sta $4400,x
    lda $d500,x
    sta $4500,x
    lda $d600,x
    sta $4600,x
    lda $d700,x
    sta $4700,x
    inx
    bne !-

    lda Zeropage.PORT_REG                       // disable rom charset at $d000 again
    ora #Zeropage.ENABLE_CHAREN_CLEAR_MASK
    sta Zeropage.PORT_REG                       
    
    rts

updateUnrolledFliCode:
    // inc $d020

.label indexValue = *+1
    ldx #0
.for (var row=0; row < TechTechHeight; row++) {
    lda SineValuesForD018 + row,x
    sta startFliTechTech + (row * unrolledFliSegmentSize) + 6
    lda SineValuesForD016 + row,x
    sta startFliTechTech + (row * unrolledFliSegmentSize) + 11
}

    lda indexValue
    clc
    adc #1
    sta indexValue
    
    //dec $d020
    rts

generateCoverSprite:
    ldx #$3f
    lda #$ff
!:  sta CoverSpriteLocation,x
    dex
    bpl !-

    // set cover sprite pointers for each videoram bank used
    lda #$f8
    ldx #$4b
    sta Zeropage.Unused_FB
    stx Zeropage.Unused_FC
    ldx #0
!:
    lda #(CoverSpriteLocation & $3fff) / 64
    ldy #0
    sta (Zeropage.Unused_FB),y
    iny
    sta (Zeropage.Unused_FB),y
    lda Zeropage.Unused_FC
    clc
    adc #4
    sta Zeropage.Unused_FC
    inx
    cpx #14
    bne !-

    rts    

enableCoverSprites:
    clc
    lda #$32
    sta VIC.SPRITE_0_Y
    adc #42
    sta VIC.SPRITE_1_Y
    lda #VIC.black
    sta VIC.SPRITE_MULTICOLOR_3_0
    sta VIC.SPRITE_MULTICOLOR_3_1
    lda #%00000011                              // stretch cover sprites in X and Y direction
    sta VIC.SPRITE_DOUBLE_Y
    sta VIC.SPRITE_ENABLE
    sta VIC.SPRITE_DOUBLE_X
    lda #$08                                    // we need to conver the first four chars on screen
    sta VIC.SPRITE_0_X                          
    sta VIC.SPRITE_1_X                          

    rts

drawAlphabetOnFirstColumn: {
    ldx #$00
drawCharacters:
.label character = *+1
    lda #$01                                    // draw alphabet on column 0 to fill screen
.label screenTargetLo = *+1
.label screenTargetHi = *+2
    sta $0400
    inx
    cpx #$19                                    // draw on all 25 columns (notice missing lines on bottom)
    beq exit

    inc character                               // next character
    lda screenTargetLo
    clc
    adc #$28                    
    sta screenTargetLo
    bcc drawCharacters
    inc screenTargetHi
    jmp drawCharacters

exit:
    rts
}

fillColorRam:
    ldx #$00
    lda #VIC.cyan_mc
!:  sta $d800,x
    sta $d900,x
    inx
    bne !-
    rts

* = $4000 "charset"
.import binary "../E Custom Charset/font.bin"

* = $4800 "screen data blank"
.fill 3 * 40, $ff // fill 3 rows with solid characters

* = $4800+120 "screen data"
.import binary "../E Custom Charset/screen.bin"