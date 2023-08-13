#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = $34

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
    
    jsr Kernel.ClearScreen
  !:
    jmp !-

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
    lda #VIC.lred                               // (2 cycles) already load color, do something useful
    ldy #VIC.black                              //(2 TZ) 'Zeilenfarbe' schwarz ins Y-Reg. laden
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
    ldx #9                      //  5: 2
 !: dex
    bne !-                      // 49: 9*5cycles-1cycle=44cycle
    ldy #0                      // 51: 2, y will be indexer in tables
    lda colors,y                // 55: 4
    nop                         // 57: 2
    nop                         // 59: 2
    
// 4 raster lines happened before
rasterbarLine:
    sta VIC.BORDER_COLOR                // 63|20: 4
    sta VIC.SCREEN_COLOR                // 4: 4
    nop                                 // 6: 2
    nop                                 // 8: 2
    iny                                 // 10: 2
    tax                                 // 12: 2
    bmi exit                            // 14: no jump when more colors exist, 
                                        // otherwise it does not matter, when last color is background color
    ldx #3                              // 16: 2
 !: dex                                 // 
    bne !-                              // 30: 3*5cycles-1cycle= 14cycle

    nop                                 // 32: 2
    nop                                 // 34: 2
    nop                                 // 36: 2
    lda VIC.CURRENT_RASTERLINE_REG      // 40: 4
    and #%00000111                      // 42: 2
    cmp #%00000010                      // 44: 2
    beq preloadForBadLine               // 46: 2 on most normal lines, 47: 3 on last line before bad line        

restOfNormalLine: 
    nop                         // 48: 2
    nop                         // 50: 2
    nop                         // 52: 2
    lda colors,y                // 56: 4
    jmp rasterbarLine           // 59: 3

preloadForBadLine:
    lda colors,y                // 51: 4
    iny                         // 53: 2
    ldx colors,y                // 57: 4
    nop                         // 59: 2
 
badLine:
    // the last line before this one needs to store the color already in x reg
    // also the 
    sta VIC.BORDER_COLOR        //  4: 4  set border color first, this needs to be done before cycle 0
    sta VIC.SCREEN_COLOR        //  8: 4
    and #%10000000              // 10: 2
    bmi exit                    // 12: no jump when more colors exist, otherwise it does not matter
    txa                         // 14: 2
    bit $01                     // 17: 3
    jmp rasterbarLine           // 20: 3

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

.align $100
colors:
    .byte VIC.blue, VIC.black, VIC.lblue, VIC.blue, VIC.black, VIC.cyan, VIC.lgrey, VIC.lblue
    .byte VIC.black, VIC.lgreen, VIC.cyan, VIC.cyan, VIC.lgrey, VIC.black, VIC.yellow, VIC.lgreen
    .byte VIC.lgreen, VIC.lgreen, VIC.cyan, VIC.black, VIC.white, VIC.yellow, VIC.yellow, VIC.yellow
    .byte VIC.yellow, VIC.lgreen, VIC.black, VIC.yellow, VIC.white, VIC.white, VIC.white, VIC.white
    .byte VIC.white, VIC.white, VIC.white, VIC.black, VIC.white, VIC.yellow, VIC.yellow, VIC.yellow
    .byte VIC.yellow, VIC.lgreen, VIC.black, VIC.yellow, VIC.lgreen, VIC.lgreen, VIC.lgreen, VIC.cyan
    .byte VIC.black, VIC.lgreen, VIC.cyan, VIC.cyan, VIC.lgrey, VIC.black, VIC.cyan, VIC.lgrey
    .byte VIC.lblue, VIC.black, VIC.lblue, VIC.blue, VIC.black, VIC.blue
    .byte $f0
