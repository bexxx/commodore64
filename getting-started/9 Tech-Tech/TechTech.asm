#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = $37
.const LogoWidthInChars = 19
.const SwingWidthInChars = 3
.const LogoHeightInChars = 8
.const LogoHeightInRasterLines = (LogoHeightInChars) * 8
.const sineSteps = LogoHeightInRasterLines * 2

BasicUpstart2(main)

main:
    // clear screen with spaces (20)
    jsr Kernel.ClearScreen
    // for the lines with the "logo" we need a character which is empty, this is "0" in our case
    ldx #39
    lda #0
 !:
    sta $0400+40,x
    sta $0400+80,x
    sta $0400+120,x
    sta $0400+160,x
    sta $0400+200,x
    sta $0400+240,x
    sta $0400+280,x
    sta $0400+320,x
    dex
    bpl !-

    // Draw the logo, in our case just increasing characters until we have a nice
    // multicolor logo. To see TechTech in action, this should be enough, although
    // really not too fancy.

    ldy #0
writeLine:    
    ldx #0
writeCharacter:
.label character = *+1
    lda #0
.label screenAddressLo = *+1    
.label screenAddressHi = *+2    
    sta $0428
    inc character
    clc
    inc screenAddressLo
    bne !+
    inc screenAddressHi
 !:
    // are we done with the line?
    inx
    cpx #LogoWidthInChars + SwingWidthInChars
    bne writeCharacter

    iny
    cpy #LogoHeightInChars
    beq charsDone

    // determine write address of next line
    lda #(40 - LogoWidthInChars - SwingWidthInChars)
    clc
    adc screenAddressLo
    sta screenAddressLo
    bcc writeLine
    jmp charsDone
    inc screenAddressHi

    jmp writeLine

charsDone:

    // now we need to create at least one more charset shifted by one character and we need to
    // empty the leading/trailing characters

    sei

    lda $01     // clear charrom bit (active low)
    and #%11111011
    sta $01     // ...at $D000 by storing %00110011 into location $01

    // we keep the current vic bank (0) and we clone the rom charset from $d000 to
    // $2000 
    ldy #$f
!copyCharacterDataOuter:
    ldx #$0
!copyCharacterDataInner:    
.label charsetSourceHi = *+2    
    lda $d000,x
.label charsetDestinationHi = *+2    
    sta $2000,x
    dex
    bne !copyCharacterDataInner-
    inc charsetSourceHi
    inc charsetDestinationHi
    dey
    bpl !copyCharacterDataOuter-

    // now we need to empty the padding characters
    ldy #LogoHeightInChars
emptyCharOuter:    
    lda #0
    ldx #(SwingWidthInChars * 8)-1
emptyCharInner:
.label targetAddressLo = *+1
.label targetAddressHi = *+2
    sta $2000,x
    dex
    bpl emptyCharInner
    dey
    bmi emptyCharDone
    clc
    lda targetAddressLo
    adc #LogoWidthInChars*8+SwingWidthInChars*8
    sta targetAddressLo
    bcc emptyCharOuter
    inc targetAddressHi
    jmp emptyCharOuter
emptyCharDone:

    // now we shift by one character (for every line of the logo) and insert a new empty one

    // copy first
    // now we need to empty the padding characters
    ldy #LogoHeightInChars
!emptyCharOuter:    
    ldx #0
!emptyCharInner:
.label sourceAddressLo2 = *+1
.label sourceAddressHi2 = *+2
    lda $2000+8,x
.label targetAddressLo2 = *+1
.label targetAddressHi2 = *+2
    sta $3000,x
    inx 
    cpx #((LogoWidthInChars+SwingWidthInChars) * 8)
    bne !emptyCharInner-
    dey
    bmi !emptyCharDone+
    clc
    lda sourceAddressLo2
    adc #LogoWidthInChars*8+SwingWidthInChars*8
    sta sourceAddressLo2
    bcc updateTargetAddress
    inc sourceAddressHi2

updateTargetAddress:
    clc
    lda targetAddressLo2
    adc #LogoWidthInChars*8+SwingWidthInChars*8
    sta targetAddressLo2
    bcc !emptyCharOuter-
    inc targetAddressHi2
    jmp !emptyCharOuter-

!emptyCharDone:

    lda $01                                     // switch in I/O mapped registers again...
    ora #%00000100
    sta $01                                     // ... with %00110111 so CPU can see them
    cli

    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora #VIC.SELECT_CHARSET_AT_3000_MASK
    sta VIC.GRAPHICS_POINTER
      
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
    // line $37, #55
    // when this code is started, 38-45 cycles already passed
    // in the current raster line (completing asm instruction, saving return address and registers)
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
    // $39, #57
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
    // $3a, #58
                                                //  3
    ldx #8                                      //  5: 2
 !: dex
    bne !-                                      // 44: 9*5cycles-1cycle=39cycle
    ldy CurrentSineIndex                        // 48: 4, y will be indexer in tables
    lda SineTable,y                             // 52: 4, current sine value
    ldx CharsetTable,y                          // 56: 4
    bit $01                                     // 59: 3

// 4 raster lines happened before
// $3b, #59
fullGoodRasterLine:
    sta VIC.CONTR_REG                           // 63: 4 // store exactly before new line starts
    stx VIC.GRAPHICS_POINTER                    // 4: 4
    iny                                         // 6: 2
.label sineTableIndexEnd1 = *+1          
    cpy #(LogoHeightInRasterLines - 1)          // 8: 2
    bpl exit                                    // 10: 2 no jump when y is within sine table
    ldx #3                                      // 12: 2
 !: dex                                         // 
    bne !-                                      // 26: 3*5cycles-1cycle= 14cycle

    nop                                         // 28: 2
    nop                                         // 30: 2
    lda VIC.CURRENT_RASTERLINE_REG              // 34: 4
    and #%00000111                              // 36: 2
    cmp #%00000010                              // 38: 2
    beq preloadForBadLine                       // 40: 2 on most normal lines, 41: 3 on last line before bad line        

restOfNormalLine: 
    nop                                         // 42: 2
    lda SineTable,y                             // 46: 4
    ldx CharsetTable,y                          // 50: 4
    nop                                         // 52
    nop                                         // 54
    nop                                         // 56
    jmp fullGoodRasterLine                      // 59: 3

preloadForBadLine:                              // 41: beq take == 2 + 1
    lda SineTable,y                             // 45: 4
    ldx CharsetTable,y                          // 49: 4
    nop                                         // 51: 2
    nop                                         // 53: 2
    nop                                         // 55: 2
    nop                                         // 57: 2
    nop                                         // 59: 2
 
badLine:
    // the last line before this one needs to store the sine value already in x reg
    stx VIC.GRAPHICS_POINTER                    // 63: 4
    sta VIC.CONTR_REG                           //  4: 4  
    lda SineTable,y                             //  8: 4
    ldx CharsetTable,y                          // 12: 4
    iny                                         // 14: 2
    nop                                         // 16: 2
    jmp fullGoodRasterLine                      // 19: 3

exit:                                           // 11
    // we need to wait until the line is drawn completely before switching back to defaults
    lda #<interruptHandler                      // 13: 2 restore first interrupt handler address
    sta Internals.InterruptHandlerPointerRamLo  // 17: 4
    lda #>interruptHandler                      // 19: 2
    sta Internals.InterruptHandlerPointerRamHi  // 23: 4

    lda #RasterInterruptLine                    // 25: 2 restore first raster line
    sta VIC.CURRENT_RASTERLINE_REG              // 29: 4

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // 31: 2 ack interrupt
    sta VIC.INTERRUPT_EVENT                     // 35: 4

    nop                                         // 37
    nop                                         // 39
    nop                                         // 41
    nop                                         // 43
    nop                                         // 45
    nop                                         // 47
    nop                                         // 49
    nop                                         // 51

    lda #%00001000                              // 53: 2
    sta VIC.CONTR_REG                           // 57: 4

    lda #(VIC.SELECT_SCREENBUFFER_AT_0400_MASK | VIC.SELECT_CHARSET_AT_1000_MASK)   // 59: 2
    sta VIC.GRAPHICS_POINTER                    // 63: 4


setCurrentSineIndex:
    inc CurrentSineIndex
    lda CurrentSineIndex
    cmp #LogoHeightInRasterLines
    bne noSineIndexReset
    lda #0
    sta CurrentSineIndex
noSineIndexReset:
    clc
    adc #(LogoHeightInRasterLines - 1)
    sta sineTableIndexEnd1

    jmp Internals.InterruptHandlerPointer       // jump to system timer interrupt code

CurrentSineIndex:
    .byte $0

.align $100
.segment Default "sine table"
SineTable:
    .for(var i=0; i<LogoHeightInRasterLines * 2; i++) {    
        .var sineValue = 15 * abs(sin(toRadians((i*360)/(sineSteps))))
        .if (sineValue >= 8) {
            .byte (sineValue - 8) | %000001000
        } else {
            .byte sineValue | %000001000
        }
    }
SineTableEnd:

.align $100
.segment Default "charset values"
CharsetTable:
    .for(var i=0; i<LogoHeightInRasterLines * 2; i++) {
        .var sineValue = 15 * abs(sin(toRadians((i*360)/(sineSteps))))
        .if (sineValue >= 8) {
            .byte (VIC.SELECT_SCREENBUFFER_AT_0400_MASK | VIC.SELECT_CHARSET_AT_2000_MASK)
        } else {
            .byte (VIC.SELECT_SCREENBUFFER_AT_0400_MASK | VIC.SELECT_CHARSET_AT_3000_MASK)
        }
    }
CharsetTableEnd: