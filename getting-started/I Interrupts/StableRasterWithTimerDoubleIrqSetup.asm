#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"

.filenamespace StableRasterWithTimer

.namespace Configuration {
    .label RasterLineIrqSetup = $20             // start line for raster interrupt
    .label RasterLineIrqDemo = $28
    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04       
}

BasicUpstart2(main)

main:
    sei                                         // no other irqs during set

    lda #$35                                    // disable kernel
    sta Zeropage.PORT_REG
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs
    lsr CIA1.INTERRUPT_CONTROL_REG              // ack timer
    lsr CIA2.INTERRUPT_CONTROL_REG              // ack timer
    
    lda #$81
    sta $d01a                                   // enable raster irq

    lda #<irq0                                  // setup irq handler
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irq0
    sta Internals.InterruptHandlerPointerRomHi

    lda #$1b
    sta VIC.SCREEN_CONTROL_REG                  // set MSB of raster line, it's bit 7
    lda #Configuration.RasterLineIrqSetup       // select raster line for irq
    sta VIC.CURRENT_RASTERLINE_REG
    lsr VIC.INTERRUPT_EVENT                     // ack any pending irq

    lda #0                                      // no hi byte for cia timer
    sta $dc05                                   
    ldy #62                                     // let it count down from 62 like 62, ..., 2, 1, 62, 62, 61
    sty $dc04                                   // so it's always counting 63 cycles

    cli         

    ldx #0                                    // do some variance in jitter, code from csdb
waitForever:
    inc $0400,x
    bpl waitForever
    bit $3
    bmi waitForever
    nop
    jmp waitForever

.align $100                                     // align on the start of a new page
.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem
                                                // helpful to check whether it all fits into the same page
irq0:                                           // classic double irq stabilization first
    sta Configuration.Irq1AccuZpLocation        // save register values
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    inc VIC.CURRENT_RASTERLINE_REG              // set irq for next line
    lsr VIC.INTERRUPT_EVENT                     // ack current irq

    cli                                         // we allow irqs again during this one
    
    lda #<irq1
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irq1
    sta Internals.InterruptHandlerPointerRomHi

    tsx                                         // save stack pointer in x register
    .fill 14, NOP                               // more NOPs to fill more than rest of this raster line

// gets called with after 7 cycles of irq setup (push status and PC to stack & jmp to this code) 
irq1: 
    // and additional jitter of 2 or 3 (we know it was a NOP before)
    lsr VIC.INTERRUPT_EVENT                     // 6: 15
    .fill 20, NOP                               // 40: 55, yeah, a loop has less bytes 
    lda $d012                                   // 4: 59
    cmp $d012                                   // 4: 63 or 64 (1 on new raster lines)
    beq fixcycle                                // 2 or 3, depending on 1 cycle jitter

fixcycle: 
    // now stable on cycle 3 of raster line 

    // we now want some delay to have the CIA timer to show 8 on the minimal passed cycles (7+2=9)
    // this will give us the values 8-1 on the CIA for common jitters (0-7)
    .fill 7, NOP 
    ldy #$11                                    // configure CIA to continuous restart timer counter
    sty $dc0e  

    lda #Configuration.RasterLineIrqDemo        
    sta VIC.CURRENT_RASTERLINE_REG              
    lda #<irqStableDemo
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqStableDemo
    sta Internals.InterruptHandlerPointerRomHi
    
    txs                                         // get stack pointer from first irq back

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti

    // must be non bad line, too many cycles used 
irqStableDemo:
    sta Configuration.Irq1AccuZpLocation        // 2: 9 + jitter
    lda $dc04                                   // 4: 15
    stx Configuration.Irq1XRegZpLocation        // 2: 17
    sty Configuration.Irq1YRegZpLocation        // 2: 19

    lsr VIC.INTERRUPT_EVENT                     // 6: 25 ack raster irq
    and #%00001111                              // 2: 27 mask timer value
    sta delay                                   // 4: 31
    lda #9                                      // 2: 33
    sec                                         // 2: 35
    sbc delay: #1                               // 2: 37
    
    // LFT's cycle slide, see codebase64
    sta     jmpTarget                           // (A in range 0..10)
    bpl     jmpTarget: !+
!:
    lda     #$a9        
    lda     #$a9        
    lda     #$a9        
    lda     #$a9       
    lda     $eaa5
    // stable at cycle 59 on the same raster line

    // just changing border color to see the stable change on the beginning of next raster line
    stx VIC.BORDER_COLOR 
    .fill 5, NOP
    ldx #VIC.lblue
    stx VIC.BORDER_COLOR
    
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
