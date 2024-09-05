#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"

.filenamespace StableRasterWithTimer

.namespace Configuration {
    .label RasterLineIrq = $30+2*8 // start line for raster interrupt
    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04       
    .label FldLines = 4 
}

BasicUpstart2(main)

main:
    lda #$17                                        // lowercase to see effect on "y" bottom line being duplicated
    sta $d018

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
    lda #Configuration.RasterLineIrq           // select raster line for irq
    sta VIC.CURRENT_RASTERLINE_REG
    lsr VIC.INTERRUPT_EVENT                     // ack any pending irq
                                               // set when re-newing continuous mode, it's not visible until then
    cli         

 ldx #$00
drawCharacters:
.label character = *+1
    lda #'y'-1                                    // draw alphabet on column 0 to fill screen
.label screenTargetLo = *+1
.label screenTargetHi = *+2
    sta $0400
    inx
    cpx #$19                                    // draw on all 25 columns (notice missing lines on bottom)
    beq waitForever

    inc character                               // next character
    lda screenTargetLo
    clc
    adc #$28                    
    sta screenTargetLo
    bcc drawCharacters
    inc screenTargetHi
    jmp drawCharacters

    lda #%10010101
    sta $3fff
waitForever:
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
    lda VIC.CURRENT_RASTERLINE_REG              // 4: 59
    cmp VIC.CURRENT_RASTERLINE_REG              // 4: 63 or 64 (1 on new raster lines)
    beq fixcycle                                // 2 or 3, depending on 1 cycle jitter

fixcycle: 
    // now stable on cycle 3 of raster line 
    txs                                         // 2: 5 get stack pointer from first irq back
fldLoop:
    ldx fldCounter: #Configuration.FldLines     // 2: 7
    beq doneFld                                 // 2: 9
    lda $d011                                   // 4: 13
    clc                                         // 2: 15
    adc #1                                      // 2: 17
    and #$7                                     // 2: 19
    eor #%00011000                               // 2: 21
    .fill 16, NOP                               // 32: 53
    dec fldCounter                              // 6: 59
    //nop                                         // 2: 61
    sta $d011                                   // 4: 65/2
    jmp fldLoop                                // 3 as before

doneFld:
    lda $d012
    clc
    adc #1
    and #$7                                 // 2: 17
    lda #%00011011                               // 2: 19
    sta $d011  
    
    lda #Configuration.FldLines
    sta fldCounter

    lda #Configuration.RasterLineIrq
    sta $d012
    lda #<irq0
    sta $fffe
    lda #>irq0
    sta $ffff

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti