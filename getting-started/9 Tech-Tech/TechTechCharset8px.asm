#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = $34
.const LogoWidthInChars = 19
.const SwingWidthInChars = 3
.const LogoHeightInChars = 8
.const LogoHeightInRasterLines = (LogoHeightInChars + 1) * 8
.const sineSteps = LogoHeightInRasterLines * 2

BasicUpstart2(main)

main:
    jsr Kernel.ClearScreen

    // Draw the logo, in our case just increasing characters until we have a nice
    // multicolor logo. To see TechTech in action, this should be enough, although
    // really not too fancy.

    ldy #0
writeLine:    
    ldx #0
writeCharacter:
.label character = *+1
    lda #SwingWidthInChars
.label screenAddressLo = *+1    
.label screenAddressHi = *+2    
    sta $0428 + SwingWidthInChars
    inc character

    // determine next write address
    clc
    inc screenAddressLo
    bne !+
    inc screenAddressHi
 !:
    // are we done with the line?
    inx
    cpx #LogoWidthInChars
    bne writeCharacter

    iny
    cpy #LogoHeightInChars
    beq charsDone

    // determine next characterat start of next line
    clc
    lda #SwingWidthInChars
    adc character
    sta character

    // determine write address of next line
    lda #(40 - LogoWidthInChars - SwingWidthInChars) + SwingWidthInChars
    clc
    adc screenAddressLo
    sta screenAddressLo
    bcc writeLine
    jmp charsDone
    inc screenAddressHi

    jmp writeLine

charsDone:
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
                                                //  3
    ldx #9                                      //  5: 2
 !: dex
    bne !-                                      // 49: 9*5cycles-1cycle=44cycle
    ldy CurrentSineIndex                        // 53: 4, y will be indexer in tables
    lda SineTable,y                             // 57: 4, current sine value
    nop                                         // 59: 2

// 4 raster lines happened before
fullGoodRasterLine:
    sta VIC.CONTR_REG                           // 63|20: 4 // store exctly before new line starts
    iny                                         // 6: 2
.label sineTableIndexEnd1 = *+1          
    cpy #LogoHeightInRasterLines                // 8: 2
    beq exit                                    // 10: 2 no jump when y is within sine table
    nop                                         // 12: 2
    nop                                         // 14: 2
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
    lda SineTable,y                             // 56: 4
    jmp fullGoodRasterLine                      // 59: 3

preloadForBadLine:                              // 47: beq take == 2 + 1
    lda SineTable,y                             // 51: 4
    iny                                         // 53: 2
    ldx SineTable,y                             // 57: 4
    nop                                         // 59: 2
 
badLine:
    // the last line before this one needs to store the sine value already in x reg
    sta VIC.CONTR_REG                           //  4: 4  
    nop                                         //  6: 2
    nop                                         //  8: 2
.label sineTableIndexEnd2 = *+1 
    cpy #LogoHeightInRasterLines                // 10: 2
    beq exit                                    // 12: 2 normal, 3 on jump

    txa                                         // 14: 2
    bit $01                                     // 17: 3
    jmp fullGoodRasterLine                      // 20: 3

exit:
    lda #<interruptHandler                      // restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo
    lda #>interruptHandler
    sta Internals.InterruptHandlerPointerRamHi

    lda #RasterInterruptLine                    // restore first raster line
    sta VIC.CURRENT_RASTERLINE_REG

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt
    sta VIC.INTERRUPT_EVENT

    lda #%00001011
    sta VIC.CONTR_REG

setCurrentSineIndex:
    //inc $d020
    inc CurrentSineIndex
    lda CurrentSineIndex
    cmp #LogoHeightInRasterLines
    bne noSineIndexReset
    lda #0
    sta CurrentSineIndex
noSineIndexReset:
    clc
    adc #LogoHeightInRasterLines
    sta sineTableIndexEnd1
    sta sineTableIndexEnd2

    //dec $d020

    jmp Internals.InterruptHandlerPointer       // jump to system timer interrupt code

CurrentSineIndex:
    .byte $0

.align $100
.segment Default "sine table source"
SineTable:
    .fill LogoHeightInRasterLines * 2, 7 * abs(sin(toRadians((i*360)/(sineSteps)))) | %000001000
SineTableEnd:

