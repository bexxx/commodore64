#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/BezierEasings.asm"

.filenamespace ChessZoomerIrqs

BasicUpstart2(main)

.namespace Configuration {
    .label RasterLineIrqSetup = $20             // start line for raster interrupt

    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04       

    .label IrqStretchAccuZpLocation = $02
    .label IrqStretchXRegZpLocation = $03
    .label IrqStretchYRegZpLocation = $04       

    .label StartStretchIrqRasterLine = 49

    .label Charset1Address = $3000
    .label Charset2Address = $3800
    .label Screen = $0400
    .label SineValuesAddress = $2e00
}

main:
    sei                                         // no other irqs during set

    lda #0
    //lda #%01011010
    sta $3fff

    lda #$35                                    // disable kernel
    sta $01

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs
    lsr CIA1.INTERRUPT_CONTROL_REG              // ack timer
    lsr CIA2.INTERRUPT_CONTROL_REG              // ack timer
    
init:
    lda #$81
    sta $d01a                                   // enable raster irq

    lda #<irq0                                  // setup irq handler
    sta $fffe
    lda #>irq0
    sta $ffff

    lda #$1b
    sta VIC.SCREEN_CONTROL_REG                  // set MSB of raster line, it's bit 7
    lda #Configuration.RasterLineIrqSetup       // select raster line for irq
    sta VIC.CURRENT_RASTERLINE_REG
    lsr VIC.INTERRUPT_EVENT                     // ack any pending irq

    lda #0                                      // no hi byte for cia timer
    sta $dc05                                   
    ldy #62                                     // let it count down from 62 like 62, ..., 2, 1, 62, 62, 61
    sty $dc04                                   // so it's always counting 63 cycles


    // generate charsets
    ldx #39
    lda #$0
!:  sta Configuration.Charset1Address,x
    dex
    bpl !-

    ldx #39
    lda #$ff
!:  sta Configuration.Charset2Address,x
    dex
    bpl !-

    clc
    ldx #0
!:  
    txa
    .for (var row=0; row < 25; row++) {
        sta $0400 + row*40,x
    }
    inx
    cpx #40
    bne !-

    lda #(Configuration.Screen & $3c00)/$400*$10 + (Configuration.Charset1Address & $3800)/$800*2
    sta irqZoomerStart.d018Value

    cli

!:  jmp !-

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
    lda #<irqZoomerStart
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqZoomerStart
    sta Internals.InterruptHandlerPointerRomHi
    
    txs                                         // get stack pointer from first irq back

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti


.align $100
irqZoomerStart: {
    SaveIrqRegistersZPWithTimer(Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
    nop             // 2: 57
    nop
beforeBadline:  
    lda d018Value: #0
    sta $d018

    //inc $d020

    lda $d011
    bmi doneWithScreen

    lda $d018
    eor #((Configuration.Charset1Address & $3800)/$800*2)^((Configuration.Charset2Address&$3800)/$800*2)
    sta d018Value

    ldx sineIndex: #0
    lda $d012
    clc
    adc SineValues,x
    bcs doneWithScreen


    jmp nextCharline

doneWithScreen:
    lda #BLACK
    sta $d020

    inc sineIndex
    ldx sineIndex
    lda SineValues,x
    sta updateCharsets.currentWidth
    lda #0
    sta updateCharsets.currentWidth+1

    irq_wait($ff, Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation, 0)
.break
    jsr updateCharsets
.break
    jsr cloneCharsetBytes
.break
    lda #(Configuration.Screen & $3c00)/$400*$10 + (Configuration.Charset1Address & $3800)/$800*2
    sta irqZoomerStart.d018Value

    lda #<irqZoomerStart
    sta $fffe
    lda #>irqZoomerStart
    sta $ffff

    lda #Configuration.StartStretchIrqRasterLine
nextCharline:
    sta $d012
endInterrupt:
    lsr VIC.INTERRUPT_EVENT                     // 6: 25 ack raster irq


    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

updateCharsets: {
    lda #YELLOW
    sta $d020

    // temp for debugging, remove later
    lda #12
    sta currentWidth
    lda #0
    sta currentWidth+1

    // reset charset pointer for both normal and inverted charset
    lda #<Configuration.Charset1Address
    sta char1TargetLo
    sta char2TargetLo
    lda #>Configuration.Charset1Address
    sta char1TargetHi
    lda #>Configuration.Charset2Address
    sta char2TargetHi

    // initialize remainging counters
    lda currentWidth
    sta remainingWidth
    lda currentWidth+1
    sta remainingWidth+1
    
    ldy #40-1                 // 40 characters per line
pixelLoop:
    
    // decrement remaining with by 8 (8 pixels per character)
.break
    sec
    lda remainingWidth
    sbc #8
    sta remainingWidth
    lda remainingWidth+1
    sbc #0
    sta remainingWidth+1
    bpl moreRemainingPixelsLeft     // more pixels in the same color

    // remaining width is a negative number. but it must be -1 to -7, because we subtracted 8
    // so clear bit 7 to make this a number 1 - 7 to use it as an index into the patterns array
    lda remainingWidth
    and #%00000111
    tax         

    // remaining width was negative, so we are adding the current width number
    // to get the remaining with after drawing the partial pixels in the current character
    // carry is clear because we are negative.
    
    lda currentWidth
    adc remainingWidth
    sta remainingWidth
    lda currentWidth+1
    adc remainingWidth+1
    sta remainingWidth+1

    inc updateColor

    // depending on the current color, we either store the pattern or the inverted
    // pattern into the charset    
    lda patterns,x
    ldx color
    bne !+       // inverted condition, we inverted color before
    eor #$ff
!:
    
    jmp store8PxInCharset

moreRemainingPixelsLeft:
    lda color
store8PxInCharset:
.label char1TargetLo = * + 1
.label char1TargetHi = * + 2
    sta $dead 
    eor #$ff
.label char2TargetLo = * + 1
.label char2TargetHi = * + 2
    sta $dead 

    clc
    lda char1TargetLo
    adc #8
    sta char1TargetLo
    sta char2TargetLo
    bcc !+
    inc char1TargetHi
    inc char2TargetHi
!:
    lda updateColor: #0
    bne doUpdateColor   
    lda remainingWidth+1
    bne !+
    lda remainingWidth 
    bne !+

    lda currentWidth
    sta remainingWidth
    lda currentWidth+1
    sta remainingWidth+1

doUpdateColor:
    lda color
    eor #$ff
    sta color
    lda #0
    sta updateColor 

!:
    dey
    bmi doneUpdating
    jmp pixelLoop

doneUpdating:
    lda #BLACK
    sta $d020
    rts
totalRemainingPixels:
    .byte 0, 0
currentWidth:
    .byte 0, 0
remainingWidth:
    .byte 0,0
color: 
    .byte 0
}

cloneCharsetBytes: {
    lda #GREEN
    sta $d020
    ldx #$0
!:
    lda Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    sta Configuration.Charset1Address,x
    inx
    bne !-

    ldx #$0
!:
    lda Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    sta Configuration.Charset1Address + 32 * 8,x
    inx
    cpx #8*8
    bne !-

    ldx #$0
!:
    lda Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    sta Configuration.Charset2Address,x
    inx
    bne !-

    ldx #$0
!:
    lda Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    sta Configuration.Charset2Address + 32 * 8,x
    inx
    cpx #8*8
    bne !-

    lda #BLACK
    sta $d020
    rts
}

patterns:
    .byte %00000000   // 0
    .byte %10000000   // 1
    .byte %11000000   // 2
    .byte %11100000   // 3
    .byte %11110000   // 4   
    .byte %11111000   // 5
    .byte %11111100   // 6
    .byte %11111110   // 7
    .byte %11111111   // 8

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

* = Configuration.SineValuesAddress "Sine values"
SineValues:
    .fill $100, 4 + sin(toRadians((i / $100) * 180)) * (180 - 4)

* = Configuration.Charset1Address  "Charset 1" virtual
    .fill 40*8, 0

* = Configuration.Charset2Address "Charset 2" virtual
    .fill 40*8, 0




//  01010101                    40x
//  00110011                    40x
//  00011100 01110001 11000111  34x
//  00001111                    40x


//  
//  >= 4px means only one change per character
//  00000111 11000001 11110000 01111100 00011111
//  00000011 11110000 00111111
//  00000001 11111100 00000111 11110000 00011111 11000000 01111111
//  00000000 11111111
//  00000000 01111111 11000000 00011111 1111
//  ...


//color == 00 or ff
//remainingWidth = width
//targetIndex=0
//char = 0
//
//while remainingWidth > 8 {
//    lda patterns[8-1]
//    eor color
//    sta charsetHi: charset + targetIndex
//    targetIndex += 8
//    bcc !+
//    inc charsetHi
//!:
//    remainingWidth -= 8
//    char++
//    if char > 39
//        jmp end
//}
//    color = color eor $ff
//
//    if remainingWidth > 0 {
//        lda pattern[remainingWidth]
//        sta charset + targetIndex
//    }
//
//    targetIndex += 8
//
//    remainingWidth = width - remainingWidth
//
//end:
//
//
//
//
//patterns = [
//    .byte %00000000
//    .byte %10000000
//    .byte %11000000
//    .byte %11100000
//    .byte %11110000
//    .byte %11111000
//    .byte %11111100
//    .byte %11111110
//    .byte %11111111]