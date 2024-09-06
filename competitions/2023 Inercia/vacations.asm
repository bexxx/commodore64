#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = $e2

BasicUpstart2(main)

main:
    jsr drawGraphics

    sei

    lda #<topInterruptHandler                   // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>topInterruptHandler                   // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    lda #1                                      // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    cli                                         // allow interrupts to happen again
    
waitForever:
    jmp waitForever


.align $100                                     // align on the start of a new page
                                                // helpful to check whether it all fits into the same page
.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem

topInterruptHandler:
    lda #BLUE                               // start with a blue top on line 1
    sta VIC.BORDER_COLOR

    // when this code is started, 38-45 cycles already passed
    // in the current raster line (completing asm instruction, saving return address and rgisters)
    // Now we create a new raster interrupt, but this time, we are in control of excuted commands
    // The remaining cycles in this raster line are not sufficient to set this up, so we select
    // the current rasterline + 2.
    lda #<bottomInterruptHandler                // (2 cycles) configure 2nd raster interrupt
    sta Internals.InterruptHandlerPointerRamLo  // (4 cycles)
    lda #>bottomInterruptHandler                // (2 cycles)
    sta Internals.InterruptHandlerPointerRamHi  // (4 cycles)
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // (2 cycles) ack raster interrupt to enable 2nd one
                                                // total
                                                // 26 cycles
                                                // start was 38 + 26 cycles passed, we're now in the next raster line

    // since first interrupt started 64-71 cycles have passed
    // and we are definitely on raster line start+1.
    // From this line, we already used 1-8 cycles.
    lda #RasterInterruptLine                    // (6 cycles) set raster interrupt to raster start + 2
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK
    sta VIC.INTERRUPT_EVENT                     // (4 cycles) ack interrupt
    ReturnFromInterrupt()
    
bottomInterruptHandler:
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
    lda #LIGHT_RED                               // (2 cycles)
    ldy #BLACK                              // (2 cycles)
    cpx VIC.CURRENT_RASTERLINE_REG              // (4 cycles) still on raster line start + 2?
                                                // total:
                                                // 25 cycles, here we are either on cycles 63 or 64

    beq finalRasterInterruptStart               // (3 cycles) still on raster + 2, waste one cycle for branch taken on beq
                                                // (2 cycles) just continue running, we are on raster + 3
                                                // make sure this command and target are in the same page, otherwise
                                                // this beq takes an extra cycle and messes up the precise timing.
}

finalRasterInterruptStart:
                                                //  3
    ldx #9                                      //  5: 2
 !: dex
    bne !-                                      // 49: 9*5cycles-1cycle=44cycle
    ldy #0                                      // 51: 2, y will be indexer in tables
    lda colors,y                                // 55: 4
    nop                                         // 57: 2
    nop                                         // 59: 2
    
// 4 raster lines happened before
rasterbarLine:
    sta VIC.BORDER_COLOR                        // 63|20: 4
    nop
    nop
    nop                                         // 6: 2
    nop                                         // 8: 2
    iny                                         // 10: 2
    tax                                         // 12: 2
    bmi exit                                    // 14: no jump when more colors exist, 
                                                // otherwise it does not matter, when last color is background color
    ldx #3                                      // 16: 2
 !: dex                                         // 
    bne !-                                      // 30: 3*5cycles-1cycle= 14cycle

    nop                                         // 32: 2
    nop                                         // 34: 2
    nop                                         // 36: 2
    lda VIC.CURRENT_RASTERLINE_REG              // 40: 4
    and #%00000111                              // 42: 2
    cmp #%00000010                              // 44: 2
    beq preloadForBadLine                       // 46: 2 on most normal lines, 47: 3 on last line before bad line        

restOfNormalLine: 
    nop                                         // 48: 2
    nop                                         // 50: 2
    nop                                         // 52: 2
    lda colors,y                                // 56: 4
    jmp rasterbarLine                           // 59: 3

preloadForBadLine:
    lda colors,y                                // 51: 4
    iny                                         // 53: 2
    ldx colors,y                                // 57: 4
    nop                                         // 59: 2
 
badLine:
    // the last line before this one needs to store the color already in x reg
    // also the 
    sta VIC.BORDER_COLOR                        //  4: 4  set border color first, this needs to be done before cycle 0
    nop
    nop
    and #%10000000                              // 10: 2
    bmi exit                                    // 12: no jump when more colors exist, otherwise it does not matter
    txa                                         // 14: 2
    bit $01                                     // 17: 3
    jmp rasterbarLine                           // 20: 3

exit:
    lda #<topInterruptHandler                   // restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo
    lda #>topInterruptHandler
    sta Internals.InterruptHandlerPointerRamHi

    lda #1                                      // restore first raster line interrupt
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt
    sta VIC.INTERRUPT_EVENT

    jmp Internals.InterruptHandlerPointer       // jump to system timer interrupt code

.align $100
colors:
    .byte CYAN, CYAN, BLUE, BLUE, BLUE
    .byte ORANGE| $f0
 
drawGraphics:
	// set to 25 line text mode and turn on the screen
	lda #$1B
	sta $D011

	// disable SHIFT-Commodore
	lda #$80
	sta $0291

	// set background color
	lda #BLUE
	sta VIC.SCREEN_COLOR

    ldx #$00
!:
    lda screenData + $000,x
    sta $0400,x
    lda screenData + $100,x
    sta $0500,x
    lda screenData + $200,x
    sta $0600,x
    lda screenData + $300,x
    sta $0700,x

    lda colorData + $000,x
    sta $d800,x
    lda colorData + $100,x
    sta $d900,x
    lda colorData + $200,x
    sta $da00,x
    lda colorData + $300,x
    sta $db00,x

    dex
    bne !-
    rts

* = $2800
.segment Default "screen data"
screenData:
	.byte	$20, $20, $20, $20, $20, $20, $20, $64, $6F, $6F, $6F, $64, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $2E, $20, $20, $20, $20, $20, $20, $2E, $20, $20, $20, $20, $20, $20, $2A, $20
	.byte	$68, $E8, $F8, $F8, $F8, $62, $6F, $64, $20, $64, $20, $64, $62, $62, $F8, $F8, $E8, $68, $2E, $20, $2E, $20, $20, $2C, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $6F, $6F, $64, $64, $77, $63, $63, $63, $63, $77, $20, $62, $62, $62, $62, $20, $20, $20, $20, $20, $02, $20, $20, $20, $2A, $20, $2E, $20, $2E, $F8, $F8, $F8, $43, $22, $20, $20, $20
	.byte	$79, $6F, $62, $79, $64, $20, $63, $A3, $E6, $AE, $E6, $A3, $63, $78, $20, $64, $64, $79, $79, $D8, $68, $2E, $27, $A0, $F8, $20, $20, $2C, $20, $20, $2E, $DC, $E0, $E0, $78, $20, $20, $2E, $20, $20
	.byte	$78, $78, $77, $63, $A3, $E6, $AE, $A1, $E6, $AC, $E6, $E6, $A1, $A1, $E6, $A3, $63, $77, $78, $78, $20, $E1, $E0, $E8, $E0, $E0, $F8, $11, $20, $2E, $DC, $E0, $A0, $78, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $A3, $E6, $E6, $E6, $AC, $AE, $AC, $BB, $A1, $A1, $E6, $E6, $E6, $E6, $20, $20, $20, $22, $E2, $20, $20, $E2, $E0, $E0, $E0, $2E, $DC, $E0, $E0, $E7, $2E, $E0, $E0, $E0, $E0, $E8, $40
	.byte	$20, $20, $A3, $E6, $AB, $AC, $BA, $BA, $AE, $AE, $BA, $AC, $BA, $A1, $E6, $A5, $E6, $A3, $20, $20, $20, $20, $2E, $20, $2E, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $A0, $E0, $E0, $22, $F9, $78, $20, $20
	.byte	$20, $3B, $E6, $E6, $DC, $AE, $AC, $AE, $A0, $AE, $A0, $AE, $A2, $BA, $AC, $AB, $E6, $A3, $20, $2C, $20, $2E, $DC, $A0, $A0, $A0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $22, $20, $20, $20, $20, $20
	.byte	$20, $20, $BA, $E6, $DC, $A0, $AC, $AE, $A0, $A0, $A0, $AE, $AE, $AC, $BA, $E8, $E6, $E6, $20, $2C, $2E, $DC, $A0, $A0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $20, $20, $20, $20, $20
	.byte	$2C, $20, $20, $E6, $DC, $A0, $AE, $A0, $A0, $A0, $AE, $A0, $AE, $BB, $BA, $E6, $A3, $7E, $20, $2E, $DC, $A0, $A0, $E2, $E1, $A0, $E0, $E0, $E0, $E0, $E0, $22, $22, $22, $E0, $E7, $20, $20, $20, $2E
	.byte	$20, $20, $20, $7C, $E6, $BA, $AE, $A0, $A0, $A0, $A0, $A0, $A0, $AE, $BA, $66, $7E, $20, $20, $DC, $A0, $E8, $20, $2E, $DC, $78, $20, $E5, $E0, $E0, $E0, $E0, $20, $20, $22, $E0, $E7, $20, $20, $20
	.byte	$20, $2C, $20, $20, $A3, $DC, $AE, $AE, $A0, $A0, $A0, $A0, $AE, $A0, $BA, $A3, $5C, $20, $E1, $A0, $E8, $20, $22, $E2, $78, $E1, $A0, $E0, $E0, $E0, $E0, $E0, $E0, $20, $20, $22, $E0, $20, $20, $20
	.byte	$20, $2E, $20, $20, $20, $22, $7C, $DC, $AC, $A0, $AE, $A0, $A0, $7E, $22, $22, $2C, $20, $E1, $78, $20, $20, $2E, $20, $6F, $A0, $F6, $F5, $E0, $22, $E0, $E0, $E0, $E7, $20, $20, $21, $20, $20, $20
	.byte	$20, $20, $20, $2C, $2E, $2C, $68, $E6, $C9, $A0, $A0, $D5, $E8, $68, $2C, $2E, $20, $2E, $20, $20, $20, $20, $20, $20, $78, $78, $20, $F5, $E0, $74, $22, $22, $E0, $E0, $20, $20, $2E, $20, $20, $20
	.byte	$20, $20, $2E, $20, $20, $2C, $20, $20, $E6, $A0, $D9, $5C, $20, $20, $2C, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $F5, $E0, $74, $20, $20, $22, $E0, $E7, $20, $20, $20, $2E, $20
	.byte	$20, $20, $2E, $20, $2E, $20, $20, $20, $C7, $DC, $D9, $5C, $20, $20, $2E, $20, $20, $20, $20, $2E, $20, $20, $20, $20, $2E, $20, $76, $E0, $A0, $74, $20, $20, $20, $22, $E0, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $2E, $64, $64, $64, $DC, $DC, $D9, $64, $64, $64, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $E0, $E0, $F6, $20, $2E, $20, $20, $20, $E0, $64, $6F, $79, $79, $68
	.byte	$20, $20, $2E, $46, $68, $E8, $E8, $E6, $DC, $A0, $A0, $E6, $E8, $E8, $68, $46, $2E, $20, $20, $20, $20, $20, $20, $20, $20, $76, $E0, $A0, $F6, $20, $20, $20, $20, $20, $21, $20, $20, $63, $77, $63
	.byte	$22, $79, $20, $20, $20, $20, $20, $20, $DC, $A0, $D9, $20, $20, $20, $20, $20, $79, $79, $22, $20, $2E, $20, $20, $20, $76, $E0, $E0, $E0, $74, $20, $2A, $20, $64, $68, $68, $6F, $20, $68, $68, $2E
	.byte	$F9, $F9, $62, $6F, $20, $20, $20, $20, $DC, $A0, $D9, $5C, $20, $20, $6F, $62, $F9, $F9, $20, $20, $20, $20, $20, $2E, $E0, $E0, $E0, $F6, $20, $20, $6C, $F7, $A0, $69, $F5, $A0, $F7, $7B, $20, $20
	.byte	$20, $20, $63, $77, $E8, $20, $20, $DC, $DC, $AE, $D9, $5C, $20, $E8, $77, $63, $20, $20, $20, $20, $20, $20, $2E, $E0, $E0, $E0, $E7, $68, $68, $6C, $A0, $A0, $A0, $A0, $F5, $A0, $A0, $A0, $7B, $20
	.byte	$20, $20, $20, $20, $20, $22, $DC, $A2, $A2, $A0, $A2, $A2, $5C, $22, $20, $20, $20, $20, $20, $20, $20, $62, $E0, $E0, $E0, $E0, $74, $64, $64, $E5, $A0, $A0, $F6, $20, $20, $E9, $A0, $A0, $E7, $64
	.byte	$43, $43, $43, $3D, $4E, $E8, $E8, $E8, $AC, $A1, $AC, $E8, $E8, $E8, $4D, $3D, $43, $43, $43, $43, $43, $A0, $A0, $A0, $A0, $F6, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43
	.byte	$A0, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $DC, $E8, $A0, $A0, $A0, $A0, $E8, $E8, $E8, $E8, $43, $43, $43, $43, $43, $43, $43, $43, $43, $DC
	.byte	$A0, $A0, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $A2, $82, $85, $B3, $98, $E8, $A2, $E8, $E8, $E8, $E8, $E8, $E8, $E8, $A0, $A0

colorData:
// screen color data
* = $2be8
.segment Default "color data"
	.byte	$02, $0A, $0A, $0A, $0A, $0A, $0A, $02, $02, $02, $02, $02, $0A, $0A, $0A, $0A, $0A, $0A, $00, $00, $00, $00, $0E, $0E, $01, $0E, $0E, $0E, $0E, $0E, $0E, $01, $0E, $0E, $0E, $0E, $0E, $0E, $01, $0E
	.byte	$0C, $0E, $0E, $0E, $0E, $0E, $02, $0E, $0A, $02, $0A, $02, $0E, $0E, $0E, $0E, $0E, $0C, $0C, $06, $02, $0E, $0E, $00, $0C, $00, $0E, $0A, $0E, $0E, $0E, $0E, $0E, $00, $0E, $07, $0E, $0E, $0E, $0E
	.byte	$0A, $0A, $0A, $0C, $0C, $05, $03, $05, $03, $03, $03, $03, $05, $0A, $0E, $0E, $0C, $0C, $0A, $0E, $0E, $00, $0C, $00, $0C, $0E, $0E, $01, $0E, $01, $0E, $02, $00, $00, $00, $00, $0E, $0E, $0E, $0E
	.byte	$0E, $0E, $0E, $05, $03, $07, $03, $04, $04, $04, $04, $04, $03, $03, $07, $03, $05, $0E, $0E, $0C, $0C, $04, $00, $00, $00, $00, $00, $00, $0E, $0E, $02, $00, $00, $00, $00, $0E, $0E, $01, $0E, $0E
	.byte	$0C, $0C, $03, $03, $04, $04, $04, $0A, $03, $0D, $0D, $05, $08, $0A, $04, $04, $03, $05, $03, $0E, $0E, $04, $00, $00, $00, $00, $00, $00, $00, $02, $00, $00, $00, $00, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$0E, $04, $03, $04, $0A, $0A, $0A, $0D, $0D, $0D, $0D, $0D, $0D, $0D, $0A, $0E, $04, $07, $0F, $0E, $04, $04, $00, $0E, $00, $00, $00, $00, $02, $00, $00, $00, $00, $02, $00, $00, $00, $00, $0E, $0E
	.byte	$0E, $04, $04, $0A, $03, $0D, $0D, $0D, $0D, $07, $0D, $0D, $0D, $0D, $03, $03, $0E, $04, $03, $0E, $0E, $0E, $04, $0E, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $0E, $0E, $00, $0E
	.byte	$0E, $02, $0A, $0E, $03, $0D, $07, $07, $07, $01, $07, $07, $07, $07, $0D, $05, $0E, $04, $03, $02, $0E, $04, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$0E, $0E, $04, $0E, $03, $07, $07, $01, $01, $01, $01, $01, $07, $07, $0D, $0D, $0E, $04, $03, $02, $04, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $0E, $0E, $0E, $0E
	.byte	$04, $0E, $02, $0A, $0E, $07, $01, $01, $01, $01, $01, $01, $01, $07, $07, $03, $0E, $04, $04, $04, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $0E, $0E, $00, $00, $0E, $0E, $0E, $01
	.byte	$0E, $0E, $0E, $04, $0A, $0D, $07, $01, $01, $01, $01, $01, $01, $07, $05, $0E, $0E, $0E, $04, $04, $00, $00, $0E, $04, $00, $00, $0E, $00, $00, $00, $00, $00, $0E, $0E, $0E, $00, $00, $0E, $0E, $0E
	.byte	$0E, $04, $0E, $0E, $0E, $05, $07, $01, $01, $01, $01, $01, $01, $07, $05, $0E, $04, $0E, $04, $00, $00, $0E, $04, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $0E, $0E, $00, $0E, $0E, $0E
	.byte	$0E, $0C, $02, $0E, $05, $05, $0D, $07, $01, $01, $01, $01, $07, $0D, $05, $05, $0A, $0E, $04, $00, $06, $0E, $01, $0E, $04, $00, $00, $00, $00, $0E, $00, $00, $00, $00, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$02, $02, $0E, $04, $0E, $0D, $07, $07, $07, $07, $07, $07, $07, $07, $0D, $0E, $0C, $0C, $0E, $0E, $0E, $0E, $0E, $0E, $04, $00, $06, $00, $00, $0E, $0E, $0E, $00, $00, $0E, $0E, $01, $00, $0E, $0E
	.byte	$02, $02, $0C, $0E, $09, $0A, $0E, $01, $07, $07, $07, $07, $01, $04, $0A, $0C, $0E, $0E, $0C, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $00, $00, $0E, $0E, $0E, $0E, $00, $00, $0E, $0E, $0E, $01, $0E
	.byte	$0E, $0E, $0C, $09, $0C, $0E, $09, $09, $07, $07, $07, $07, $09, $09, $0C, $0C, $0E, $0E, $0E, $01, $0E, $0E, $0E, $0E, $01, $0E, $04, $00, $00, $0E, $0E, $0E, $0E, $0E, $00, $0E, $0E, $0E, $0E, $0E
	.byte	$0E, $0E, $0E, $0C, $0C, $01, $01, $01, $07, $07, $07, $01, $01, $01, $09, $0E, $0C, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $00, $00, $0E, $0E, $01, $0E, $0E, $0E, $00, $0E, $0E, $0E, $0E, $0E
	.byte	$0E, $0E, $0C, $0C, $0F, $0F, $0F, $03, $05, $05, $05, $03, $0F, $0F, $0F, $0C, $0C, $0E, $03, $0E, $0E, $0E, $0E, $0E, $0E, $04, $00, $00, $0E, $03, $0E, $0E, $0E, $0E, $0E, $03, $0E, $0F, $0F, $0E
	.byte	$03, $03, $0E, $0E, $0E, $0C, $0C, $0C, $0D, $0D, $0D, $0C, $0C, $0C, $0C, $0C, $03, $0E, $0E, $0E, $01, $0E, $0E, $0E, $04, $00, $00, $00, $0E, $00, $01, $0E, $0F, $01, $01, $0F, $0E, $0F, $0E, $0E
	.byte	$0C, $0C, $03, $03, $01, $01, $01, $01, $0D, $0A, $0D, $0D, $01, $01, $03, $03, $0E, $0C, $0E, $0E, $0E, $0E, $0E, $04, $00, $00, $00, $0E, $0E, $01, $0F, $01, $01, $01, $01, $01, $01, $0F, $01, $01
	.byte	$0E, $0E, $0E, $0E, $03, $0E, $0E, $0A, $0A, $0A, $0A, $0A, $0E, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $04, $00, $00, $00, $0E, $0E, $0F, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$0E, $0E, $0E, $0E, $0E, $04, $0A, $0A, $04, $04, $04, $0A, $0A, $04, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $04, $00, $00, $00, $00, $0E, $0D, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07, $07
	.byte	$03, $01, $01, $07, $0A, $04, $04, $04, $04, $04, $04, $04, $04, $04, $0A, $07, $01, $01, $03, $03, $03, $00, $00, $00, $00, $00, $03, $03, $03, $03, $0D, $0D, $01, $0F, $0F, $0F, $0F, $0D, $03, $03
	.byte	$08, $08, $08, $0C, $0F, $0F, $03, $03, $03, $03, $03, $07, $07, $03, $0F, $0F, $0C, $08, $08, $08, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B, $0E, $0E, $0E, $0F, $0B, $0B, $0E, $0E, $0E, $08
	.byte	$08, $08, $08, $0C, $0C, $0C, $0F, $0F, $0D, $0D, $0D, $0D, $07, $07, $0D, $0D, $0D, $0D, $08, $08, $08, $08, $08, $09, $0B, $00, $00, $00, $00, $00, $00, $00, $0B, $08, $08, $08, $08, $08, $08, $08

