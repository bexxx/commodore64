#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"

.const RasterInterruptLine = $2f

BasicUpstart2(main)

main:
    sei

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

    cli                                         // allow interrupts to happen again
    rts

.align $100                                     // align on the start of a new page
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
    lda #LIGHT_RED                              // (2 cycles) already load color, do something useful
    ldy #BLACK                                  // (2 cycles) load black
    cpx VIC.CURRENT_RASTERLINE_REG              // (4 cycles) still on raster line start + 2?
                                                // total:
                                                // 25 cycles, here we are either on cycles 63 or 64

    beq finalRasterInterruptStart               // (3 cycles) still on raster + 2, waste one cycle for branch taken on beq
                                                // (2 cycles) just continue running, we are on raster + 3
                                                // make sure this command and target are in the same page, otherwise
                                                // this beq takes an extra cycle and messes up the precise timing.
}

finalRasterInterruptStart:
                                                // started exactly on cycle 3 of raster start + 2
    ldx #$09                                    // 5: 2
 !: dex
    bne !-                                      // 49: 9 * 5cycles-1cycle= 44cycles
    nop                                         // 51: 2            
    ldx #$19                                    // 53: 2            
    stx blockCount                              // 57: 4            
    ldy #$2f                                    // 59: 2     
                                                // 59 cycles

//// all lines before top border ends have 63 cycles for cpu
//loopTopBorder:
//    sta $d020                                   // 63: 4
//    ldx #9                                      // 2: 2
// !: dex
//    bne !-                                      // 46: 9*5cycles-1cycle = 44cycles
//    eor #%00001010                              // 48: 2                  
//    dey                                         // 50: 2
//    beq lastTopBorderLineEnd                    // 53: 2 no jump, all top lines, 53: 3 jump, end of top
//    nop                                         // 2: 54
//    nop                                         // 2: 56
//    jmp loopTopBorder                           // 3: 59
//
//lastTopBorderLineEnd:
//                                                // 53
//    nop                                         // 2: 55
//    nop                                         // 2: 57
//    nop                                         // 2: 59

// there is always one badline followed by 7 lines with full 63 cycles
// so we only count 25 of those "char lines" before we need to handle the
// bottom border.   
badLine:
    // after a badline, there are always 7 more good lines,
    // so use up all cycles (16)
    sta $d020                                   //  63: 4
    ldy #7                                      //  2: 2    number of good lines after bad lines, 1+7=8 == 1 char line  
    eor #%00001010                              //  4: 2
    nop                                         //  6: 2
    nop                                         //  8: 2
    nop                                         // 10: 2
    nop                                         // 12: 2
    nop                                         // 14: 2
    nop                                         // 16: 2
 
normalLine:
    sta $d020                                   // 20/63: 4TZ
    eor #%00001010                              //  2: 2 
    ldx #6                                      //  4: 2
 !: dex
    bne !-                                      // 33: 6*5cycles-1cycle= 29cycles
    nop                                         // 35: 2
    nop                                         // 37: 2
    nop                                         // 39: 2
    dey                                         // 41: 2
    beq endOfLastCharLine                       // 43: 2, no jump for 6 lines; 44: 3, jump on last line before badline or bottom                                                 
    nop                                         // 45: 2
    nop                                         // 47: 2
    nop                                         // 49: 2
    nop                                         // 51: 2
    nop                                         // 53: 2
    bit $01                                     // 56: 3                    
    jmp normalLine                              // 59: 3
    
endOfLastCharLine:
                                                // 44
    nop                                         // 46
    ldy #$34                                    // 48  number of bottom lines with 63 cycles
    dec blockCount                              // 50: 6
    beq wasteBeforeBottom                       // 56: 2 for all upper char lines; 3 last char line
    jmp badLine                                 // 59: 3

wasteBeforeBottom:
                                                // 57
    nop                                         // 59: 2

loopBottomBorder:
    sta $d020                                   // 63: 4
    ldx #9                                      //  2: 2
 !: dex
    bne !-                                      // 46: 9*5cycles-1cycle= 44cycles
    eor #%00001010                              // 48: 2                             
    dey                                         // 50: 2
    beq endRaster                               // 52: 2; 53: 3
    nop                                         // 54: 2
    nop                                         // 56: 2
    jmp loopBottomBorder                        // 59: 3

 endRaster:
    lda #BLACK                                  // 55
    nop                                         // 57
    nop                                         // 59
    sta $d020                                   // 63


    lda #<interruptHandler                      // restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo
    lda #>interruptHandler
    sta Internals.InterruptHandlerPointerRamHi

    lda #RasterInterruptLine                    // restore first raster line
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt
    sta VIC.INTERRUPT_EVENT

    jmp Internals.InterruptHandlerPointer       // jump to system timer interrupt code

blockCount:
    .byte 0