#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

// YSCROLL is 3 by default and stable raster routine end on 4th line, so
// pick $57/87 as a start for the IRC
.const RasterInterruptLine = $5f
.const YScrollResetIrqRasterLine = $20
.const SkipFrames = 8
.const MaxDuplicateLines = 12

BasicUpstart2(main)

main:
    ldx #$00
drawCharacters:
.label character = *+1
    lda #1                                          // draw alphabet on column 0 to fill screen
.label screenTargetLo = *+1
.label screenTargetHi = *+2
    sta $0400
    inx
    cpx #$19                                        // draw on all 25 columns (notice missing lines on bottom)
    beq start

    inc character                                   // next character
    lda screenTargetLo
    clc
    adc #$28                    
    sta screenTargetLo
    bcc drawCharacters
    inc screenTargetHi
    jmp drawCharacters

start:
    sei

    lda #<interruptHandler                          // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo      // store to RAM interrupt handler
    lda #>interruptHandler                          // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi      // store to RAM interrupt handler

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK           // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                        // store to this register acks irq associated with bits

    lda #RasterInterruptLine                        // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG                  // low byte of raster line

    lda VIC.SCREEN_CONTROL_REG                      // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK             // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                      // write back to VIC control register

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG                  // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG                  // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK           // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                         // store back to enable raster interrupt

    cli                                             // allow interrupts to happen again

!:
    jmp !-

.align $100                                         // align on the start of a new page
.segment Default "raster interrupt"                 // shows the bytes for this code, when using -showmem
                                                    // helpful to check whether it all fits into the same page

interruptHandler: {
    // line $57, #59
    // when this code is started, 38-45 cycles already passed
    // in the current raster line (completing asm instruction, saving return address and registers)
    // Now we create a new raster interrupt, but this time, we are in control of excuted commands
    // The remaining cycles in this raster line are not sufficient to set this up, so we select
    // the current rasterline + 2.
    lda #<secondRasterInterrupt                     // (2 cycles) configure 2nd raster interrupt
    sta Internals.InterruptHandlerPointerRamLo      // (4 cycles)
    lda #>secondRasterInterrupt                     // (2 cycles)
    sta Internals.InterruptHandlerPointerRamHi      // (4 cycles)
    tsx                                             // (2 cycles) get stack pointer into x register
    stx secondRasterInterrupt.stackpointerValue     // (4 cycles) modify code of 2nd interrupt handler to return correct SP
    nop                                             // (2 cycles)
    nop                                             // (2 cycles)
    nop                                             // (2 cycles)
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK           // (2 cycles) ack raster interrupt to enable 2nd one
                                                    // total
                                                    // 26 cycles
                                                    // start was 38 + 26 cycles passed, we're now in the next raster line

    // since first interrupt started 64-71 cycles have passed
    // and we are definitely on raster line start+1.
    // From this line, we already used 1-8 cycles.
    inc VIC.CURRENT_RASTERLINE_REG                  // (6 cycles) set raster interrupt to raster start + 2
                                                    // $d012 was increased to start+1 by vic already
    sta VIC.INTERRUPT_EVENT                         // (4 cycles) ack interrupt
    cli                                             // (2 cycles) enable interrupts again                                            

    // Still on raster line start + 1 
    // so far we used up 13-20 cycles

    // waste some more cycles
    ldx #$08                                        // 2 cycles
!:
    dex                                             // 8 * 2 cycles = 16 cycles
    bne !-                                          // 7 * 3 cycles = 21 cycles
                                                    // 1 * 2 cycles =  2 cycles
                                                    // total:
                                                    //                41 cycles

    // Up to here 54-61 cycles we used, now we are waiting with NOPs for
    // the next raster interrupt to be in full control of the command executed
    // when the interrupt started. Any fixed 2 cyle operaton would work, but
    // NOPs do not have any side effect.
    nop                                             // 2 cycles (56)
    nop                                             // 2 cycles (58)
    nop                                             // 2 cycles (60)
    nop                                             // 2 cycles (62)
    nop                                             // 2 cycles (64)
    nop                                             // 2 cycles (66)
}

secondRasterInterrupt: {
    // $59, #61
    // we used exactly 38 or 39 cycles.
    // This is safe to assume, because the interrupt happened on execution of NOPs.
    //
    // Now we can waste exactly the amount of cycles that are left on this raster line 
    // (24 or 25 because 63-(38 or 39)).
    .label stackpointerValue = *+1
    ldx #$00                                        // (2 cycles) Dummy for 1. stack pointer
    txs                                             // (2 cycles) Transfer to stack
    nop                                             // (2 cycles)
    nop                                             // (2 cycles)
    nop                                             // (2 cycles)
    bit $01                                         // (3 cycles) modifies flags, but we need an odd cycle count
    ldx VIC.CURRENT_RASTERLINE_REG                  // (4 cycles) granted that we are still on raster + 2
    nop                                             // (2 cycles)
    nop                                             // (2 cycles)
    cpx VIC.CURRENT_RASTERLINE_REG                  // (4 cycles) still on raster line start + 2?
                                                    // total:
                                                    // 25 cycles, here we are either on cycles 63 or 64

    beq finalRasterInterruptStart                   // (3 cycles) still on raster + 2, waste one cycle for branch taken on beq
                                                    // (2 cycles) just continue running, we are on raster + 3
                                                    // make sure this command and target are in the same page, otherwise
                                                    // this beq takes an extra cycle and messes up the precise timing.
}

finalRasterInterruptStart:
    // $5a, #62 #%01011010, one before a bad line
                                                    //  3
    ldx #7                                          //  5: 2
 !: dex
    bne !-                                          // 39: 7*5cycles-1cycle=34cycle
    nop                                             // 41
    nop                                             // 43
    ldy duplicateLines                              // 49
    beq changeFrameCounter
createBadLineCondition:
    dec $d011                                       // 55 create bad line condition between cycle 54 and 57
    nop                                             // 57
    nop                                             // 59
    nop                                             // 61
    nop                                             // 63

    // 4 raster lines happened before
    // $3f, #63, bad line, we need to cancel bad line condition on cycle 8
startOfBadLineWith63Cycles:
    nop                                             // 2
    nop                                             // 4
    ldx #9                                          // 6
 !: dex                                             // 
    bne !-                                          // 50: 9*5cycles-1cycle=44cycle
    dey                                             // 52
    beq cleanYScrollAndExit                         // 54
    bit $01                                         // 57
    inc $d011                                       // 63 

startOfNormalLine:                                  // 0
    ldx #6                                          // 2
 !: dex                                             // 
    bne !-                                          // 31: 6*5cycles-1cycle=29cycle
    lda VIC.CURRENT_RASTERLINE_REG                  // 35
    and #%00000111                                  // 37
    cmp #%00000010                                  // 39
    bne restOfNormalLine                            // 42 for another normal line, 41 on last normal line before a bad line
    nop                                             // 43
    bit $01                                         // 46
    jmp createBadLineCondition                      // 49

restOfNormalLine:                                   // 42
    ldx #3                                          // 44
 !: dex                                             // 
    bne !-                                          // 58: 3*5cycles-1cycle=14cycle
    nop                                             // 60
    jmp startOfNormalLine                           // 63

cleanYScrollAndExit:                                // 55
    nop                                             // 57
    inc $d011                                       // 63

changeFrameCounter:                                 // slow down by skipping some frames and leave dupe counter as is
    dec frameCounter
    lda frameCounter
    beq changeDuplicateLines
    jmp exit

changeDuplicateLines:
    lda #SkipFrames
    sta frameCounter

    inc duplicateLines                              // one more duplication next frame
    lda duplicateLines
    cmp #MaxDuplicateLines
    bne exit
    lda #$0                                         // no duplication in the beginning
    sta duplicateLines

exit:                                           
    lda #<interruptHandler                          // restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo
    lda #>interruptHandler
    sta Internals.InterruptHandlerPointerRamHi

    lda #RasterInterruptLine
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK           // ack interrupt
    sta VIC.INTERRUPT_EVENT

    jmp Internals.InterruptHandlerPointer

duplicateLines:
    .byte 0
frameCounter:
    .byte SkipFrames