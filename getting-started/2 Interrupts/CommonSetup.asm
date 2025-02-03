#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/vic_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

BasicUpstart2(main)

.namespace Configuration {
    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04
}

main:
    sei                                         // don't allow other irqs to happen during setup

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs

    lda #$10                                    
    sta VIC.CURRENT_RASTERLINE_REG              // select a raster line for raster interrupt
    lda #$1b
    sta VIC.SCREEN_CONTROL_REG                  // set MSB of raster line, it's bit 7
    
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       
    sta VIC.INTERRUPT_ENABLE                    // enable raster irq

    lda #$35    
    sta Zeropage.PORT_REG                       // disable ROM

    lda #<irqHandler                            // setup custom irq handler address
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqHandler
    sta Internals.InterruptHandlerPointerRomHi

    lda CIA1.INTERRUPT_CONTROL_REG              // ACK CIA 1 interrupts in case there are pending ones
    lda CIA2.INTERRUPT_CONTROL_REG              // ACK CIA 2 interrupts in case there are pending ones
    lsr VIC.INTERRUPT_EVENT                     // ACK VIC interrupt in case there is a pending one

    cli                                         // now we are done and can enable interrupts again

waitForever: jmp waitForever
    // add code of main loop here


.align $100                                     // align to $100 to avoid page crossing and branches (costs 1 extra cycle)
irqHandler: {
    sta Configuration.Irq1AccuZpLocation
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    lsr VIC.INTERRUPT_EVENT

    // check whether carry is set to see if it's really coming from a raster

    // add raster code here

exitInterrupt:
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}
