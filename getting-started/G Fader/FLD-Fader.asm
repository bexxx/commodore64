#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/BezierEasings.asm"


.filenamespace FLDFader

.namespace Configuration {
    .label RasterLineIrqSetup = $20             // start line for raster interrupt

    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04       

    .label IrqStretchAccuZpLocation = $02
    .label IrqStretchXRegZpLocation = $03
    .label IrqStretchYRegZpLocation = $04       

    .label StartStretchIrqRasterLine = 49
}

//#define STANDALONE

#if STANDALONE
    BasicUpstart2(main)
#endif 

* = $2000
 main:
    sei                                         // no other irqs during set

    lda #0
    //lda #%01011010
    sta $3fff

    lda #$35                                    // disable kernel
    sta Zeropage.PORT_REG

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs
    lsr CIA1.INTERRUPT_CONTROL_REG              // ack timer
    lsr CIA2.INTERRUPT_CONTROL_REG              // ack timer
    
typeLftLoader:
    dec delay
    ldx delay: #4
    bpl wait
    lda #4
    sta delay
    ldx charIndex: #0
    lda loaderCredits,x
    beq init
    sta $0400 + 24*40,x
    inc charIndex
wait:
    jsr busyWaitForNewScreen
    jmp typeLftLoader

init:
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

loaderCall:
#if STANDALONE
    //jsr fillScreen
    //lsr VIC.INTERRUPT_EVENT                     // ack any pending irq
#endif 
    cli

#if STANDALONE
#else
    jsr $0200 // spindle load next part on main
#endif 

mainLoop:  
    ldx doneWithFader: #0
    beq mainLoop

#if STANDALONE
!:  jmp !-
#else
    jmp $8800
#endif 

loaderCredits:
    .text "loader by lft.   "
    .byte 0

busyWaitForNewScreen: {
    lda $d011
    bpl busyWaitForNewScreen        // 7th bit is MSB of rasterline, wait for the next frame
!:  lda $d011
    bmi !-                          // wait until the 7th bit is clear (=> line 0 of raster)

    rts
}

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

    // we now want some delay to have the CIA timer to show 8 on the minimal passed cycles (7+2=9)
    // this will give us the values 8-1 on the CIA for common jitters (0-7)
    .fill 7, NOP 
    ldy #$11                                    // configure CIA to continuous restart timer counter
    sty $dc0e  

    lda #Configuration.StartStretchIrqRasterLine        
    sta VIC.CURRENT_RASTERLINE_REG              
    lda #<irqStretcherStart
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqStretcherStart
    sta Internals.InterruptHandlerPointerRomHi
    
    txs                                         // get stack pointer from first irq back

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti

.align $100
irqStretcherStart: {
    SaveIrqRegistersZPWithTimer(Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
    nop             // 2: 57
    nop
beforeBadline:  
    ldx stretch: #0 // 2: 59
    beq doneWithFLD         // 2: 61 / 3: 62
    nop             // 2: 63

doFLD: 
    lda $d011       // 4: 4
    bmi resetD011AndNextFrame   
    clc             // 2: 6
    adc #1          // 2: 8     make next line a badline
    and #%00000111  // 2: 10    fix possible yscroll overflow
    ora #%00011000  // 2: 12    fix other $d011 bits
    sta $d011       // 4: 17
    dex             // 2: 19    keep badlines until stretch for this char line is done
    beq doneWithFLD // 2: 21
    bit $01
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    adc $1000,x     // 5
    //nop
    bit $01
    jmp doFLD       //  4: 63

doneWithFLD:
    lda $d011
    bmi resetD011AndNextFrame
    lda $d012
    clc
    adc #8
    bcs nextFrame
    cmp #251
    bcs nextFrame

    tay
    inc perRowSineIndex
    ldx perRowSineIndex: #0
    lda sineValues,x
    sta irqStretcherStart.stretch
    tya

    jmp nextCharline

nextFrame:
    lda $d011
    bpl nextFrame
resetD011AndNextFrame:
    lda #%00011011
    sta $d011

    inc sineFrameIndex
    ldx sineFrameIndex: #0
    beq doneWithFLDFading
    stx perRowSineIndex
    lda sineValues,x
    sta irqStretcherStart.stretch

    lda #Configuration.StartStretchIrqRasterLine
nextCharline:
    sta $d012
endInterrupt:
    lsr VIC.INTERRUPT_EVENT                     // 6: 25 ack raster irq
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti

doneWithFLDFading:
    lda #' '
    ldx #0
!:
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    dex
    bne !-

    inc doneWithFader

    jmp endInterrupt
}

.align $100
.segment Default "sine table source"
.function curve(x) {
    //.return floor(cubicBezierEasing(x, 0, 40, Configuration.FppLines, 0.68, 0.09, 0.37, 0.37))
    // https://cubic-bezier.com/#1,.02,.27,.42
    //cubic-bezier(.53,.04,.49,.95)
    //cubic-bezier(.9,0,.84,.74)
    //.return floor(cubicBezierEasing(x, 0, 200, 256-25, 0.82,0.18,0.65,0.44))
    .return floor(cubicBezierEasing(x, 0, 200, 256-25, 0.59,0.0,0.71,1.0))
}

sineValues:
    .fill 25, 0
    .fill 256-25, curve(i)// + (10 + 10 * sin(toRadians(i*360/50)))

fillScreen:
    ldy #25
!:
    lda char: #'a'
    ldx #39
!:
    sta screenaddress: $0400,x
    dex
    bpl !-

    clc
    lda screenaddress
    adc #40
    sta screenaddress
    bcc !+
    inc screenaddress+1
!:
    inc char
    dey
    bne !---
    rts

.macro SaveIrqRegistersZPWithTimer (AccuZpLocation, XRegZpLocation, YRegZpLocation) {
    sta AccuZpLocation        // 2: 9 + jitter
    lda $dc04                 // 4: 15
    stx XRegZpLocation        // 2: 17
    sty YRegZpLocation        // 2: 19

    and #%00001111            // 2: 21 mask timer value
    sta delay                 // 4: 25
    lda #9                    // 2: 27
    sec                       // 2: 29
    sbc delay: #1             // 2: 33
    
    // LFT's cycle slide, see codebase64
    sta     jmpTarget                           // (A in range 0..10)
    bpl     jmpTarget: !+
!:
    lda     #$a9        
    lda     #$a9        
    lda     #$a9        
    lda     #$a9       
    lda     $eaa5
    // stable at cycle 53 on the same raster line
}

.macro irq_set(label, rasterline) {
    lda rasterLine: #rasterline
    sta $d012
    irq_set_no_line(label)
}

.macro irq_set_no_line(label) {
    lda #<label
    sta $fffe
    lda #>label
    sta $ffff
}

.macro irq_wait(rasterLine, AccuZpLocation, XRegZpLocation, YRegZpLocation, alignment) {
    .errorif rasterLine > 255, "raster line number > 255, implement a irq_wait_ex instead"
    
    irqset: irq_set(next, rasterLine)

    irq_endRaster(AccuZpLocation, XRegZpLocation, YRegZpLocation)                             // restore reg values and return from irq

    .if (alignment > 0) {
        .align alignment
    }
next:
}

.macro irq_endRaster(AccuZpLocation, XRegZpLocation, YRegZpLocation) {
    lsr $d019                                   // ack raster irq
    irq_restore(AccuZpLocation, XRegZpLocation, YRegZpLocation)                               // restore reg values and return from irq

    rti
}

.macro irq_restore(AccuZpLocation, XRegZpLocation, YRegZpLocation) {
    ldy YRegZpLocation
    ldx XRegZpLocation
    lda AccuZpLocation
}

//#import "slackers.asm"
