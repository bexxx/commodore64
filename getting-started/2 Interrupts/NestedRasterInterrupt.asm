#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

.const RasterInterruptLine = 102
.const RasterInterruptLineEnd = 140

BasicUpstart2(main)

main:
    sei

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #RasterInterruptLine                    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register

    lda #<interruptHandlerStart                 // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandlerStart                 // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda VIC.INTERRUPT_ENABLE                    // load current value of VIC interrupt control register
    ora #VIC.ENABLE_RASTER_INTERRUPT_MASK       // set bit 0 - enable raster line interrupt
    sta VIC.INTERRUPT_ENABLE                    // store back to enable raster interrupt

    cli                                         // allow interrupts to happen again
                                                // return back to caller

waitForever:
    jmp waitForever

interruptHandlerStart:
    // indicate start of outer irq with white
    lda #WHITE
    sta VIC.BORDER_COLOR                       
    sta VIC.SCREEN_COLOR

    // setup next irq to fire a couple of rasters later
    lda #<interruptHandlerNestedStart          
    sta Internals.InterruptHandlerPointerRamLo 
    lda #>interruptHandlerNestedStart          
    sta Internals.InterruptHandlerPointerRamHi 
    clc
    lda VIC.CURRENT_RASTERLINE_REG
    adc #7
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

    // important to ack raster before using cli
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_EVENT                     // store to this register acks irq associated with bis
    
    // this allows the remaining code to be interrupted again
    cli

    // continue with code that may run longer
waitForEndRasterLine:
    lda VIC.CURRENT_RASTERLINE_REG              // load current line
    cmp #RasterInterruptLineEnd                 // is already end raster line?
    bne waitForEndRasterLine                    // nope. high bit not checked, end raster < 256 
    lda #0
    sta VIC.SCREEN_COLOR
    sta VIC.BORDER_COLOR                        // set border back to light blue
    ReturnFromInterrupt()                       // leave interrupt handler

interruptHandlerNestedStart: {
    lda #RED
    sta VIC.BORDER_COLOR 
    sta VIC.SCREEN_COLOR 

    // set the outer irq handler back
    lda #<interruptHandlerStart                 // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandlerStart                 // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi
    lda #RasterInterruptLine                    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

    lda #BLUE
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR 

    // ack raster irq
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_EVENT     

    // end interrupt
    ReturnFromInterrupt()
}
    