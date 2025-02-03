#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"

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

    irq_set(irqHandler)

    lda CIA1.INTERRUPT_CONTROL_REG              // ack CIA 1 interrupts in case there are pending ones
    lda CIA2.INTERRUPT_CONTROL_REG              // ack CIA 2 interrupts in case there are pending ones
    lsr $d019                                   // ack raster irq in case of pending ones

    cli

waitForever: 
    jmp waitForever

.align $100
irqHandler:
    irq_save()

irqHandlerNoSave:
    irq_wait(70)
    inc $d020

    irq_wait(100)
    inc $d020

    irq_wait(120)
    dec $d020

    irq_wait(140)
    dec $d020

    irq_wait(180)
    ldx #0
    inc $0400,x

    irq_wait(1)
    jmp irqHandlerNoSave    


.macro irq_set(label) {
    lda #<label
    sta $fffe
    lda #>label
    sta $ffff
}

// start a new raster irq out of another irq (see irq_restore doing an rti)   
.macro irq_wait_ex(rasterLine, currentScreenConfig) {
    .if (rasterLine > 255) {
        lda #(currentScreenConfig | %10000000)
    }
    else {
        lda #(currentScreenConfig & %01111111)
    }
    sta $d011
    
    lda #<rasterLine
    sta $d012                                   // set next raster irq line
    
    irq_set(next)

    irq_restore()                               // restore reg values and return from irq

next:
    irq_save()                                  // stash reg values away

    lsr $d019                                   // ack raster irq
}

.macro irq_wait(rasterLine) {
    .errorif rasterLine > 255, "raster line number > 255, use irq_wait_ex instead"
    
    lda #<rasterLine
    sta $d012                                   // set next raster irq line
    
    irq_set(next)

    lsr $d019                                   // ack raster irq
    irq_restore()                               // restore reg values and return from irq

next:
    irq_save()                                  // stash reg values away
}

.macro irq_save() {
    pha
    txa
    pha
    tya
    pha
}

.macro irq_restore() {
    pla
    tay
    pla
    tax
    pla

    rti
}