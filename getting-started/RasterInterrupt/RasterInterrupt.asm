#import "../includes/vic_constants.asm"
#import "../includes/cia1_constants.asm"
#import "../includes/internals.asm"

.const RasterInterruptLine = 102
.const RasterInterruptLineEnd = 140

BasicUpstart2(main)

main:
    sei

    lda #RasterInterruptLine                // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG          // low byte of raster line
    lda VIC.SCREEN_CONTROL_REG              // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK     // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG              // write back to VIC control register

    lda #<interruptHandlerStart             // low byte of our raster interrupt handler
    sta $0314                               // store to RAM interrupt handler
    lda #>interruptHandlerStart             // high byte of our raster interrupt handler
    sta $0315                               // store to RAM interrupt handler

    lda VIC.INTERRUPT_ENABLE                // load current value of VIC interrupt control register
    ora #VIC.ENABLE_RASTER_INTERRUPT_MASK   // set bit 0 - enable raster line interrupt
    sta VIC.INTERRUPT_ENABLE                // store back to enable raster interrupt

    cli                                     // allow interrupts to happen again
    rts                                     // return back to caller

interruptHandlerStart:
    lda VIC.INTERRUPT_EVENT                 // is this triggered by VIC?
    bmi rasterInterruptHandler              // VIC interrupt == bit 7, negative flag is copy of bit 7 of accumulator

    lda CIA1.INTERRUPT_CONTROL_REG          // then it's a timer irq. ack timer interrupt, reading resets bits
    jmp Internals.InterruptHandlerPointer   // call system interrupt handler
 
rasterInterruptHandler:
    lda #VIC.white
    sta VIC.BORDER_COLOR                    // set border to white

waitForEndRasterLine:
    lda VIC.CURRENT_RASTERLINE_REG          // load current line
    cmp #RasterInterruptLineEnd             // is already end raster line?
    bne waitForEndRasterLine                // nope. high bit not checked, end raster < 256 

    lda #VIC.lblue
    sta VIC.BORDER_COLOR                    // set border back to light blue

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK   // load mask with bit for raster irq
    sta VIC.INTERRUPT_EVENT                 // store to this register acks irq associated with bis
    
    ReturnFromInterrupt()                   // leave interrupt handler

