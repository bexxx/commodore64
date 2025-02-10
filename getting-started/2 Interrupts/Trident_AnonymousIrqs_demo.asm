#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"

#import "Trident_Magic_Tricks.asm"

BasicUpstart2(main)

main:
    sei
    lda #1                                      // start at top of screen
    sta $d012
    sta $d01a                                   // enable raster irq
    
    lda $d011
    and #%01111111                              // set MSB of raster line to 0
    sta $d011

    lda #$35                                    // enable hiram config
    sta $1

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs

    irq_set(irqHandler, 1)

    lda CIA1.INTERRUPT_CONTROL_REG              // ack CIA 1 interrupts in case there are pending ones
    lda CIA2.INTERRUPT_CONTROL_REG              // ack CIA 2 interrupts in case there are pending ones
    lsr $d019                                   // ack raster irq in case of pending ones

    cli

waitForever: 
    jmp waitForever

.align $100
irqHandler:
    irq_save()

    irq_wait(70)
    inc $d020

    irq_wait(100)
    inc $d020

    irq_wait(120)
    dec $d020

    irq_wait(140)
    dec $d020

    irq_wait(160)
    lda $d020
    sta previousD020
    jsr sequence
    lda currentColor: #currentColor
    sta $d020

    irq_wait(180)
    lda previousD020: #1
    sta $d020 

    ldx #0
    inc $0400,x

    irq_set(irqHandler, 1)
    irq_endRaster()

sequence: {
    jmp pt: *+3

    lda #WHITE
    sta currentColor
    delay_repeatable(pt, 50)

    inc currentColor
    delay_repeatable(pt, 50)

    inc currentColor
    delay_repeatable(pt, 50)

    inc currentColor
    delay_repeatable(pt, 50)

    inc currentColor
    delay_repeatable(pt, 50)

    lda #<(pt+2)
    sta pt
    lda #>(pt+2)
    sta pt+1

    rts
}