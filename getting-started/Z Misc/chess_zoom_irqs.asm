#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/BezierEasings.asm"
#import "../../includes/irq_helpers.asm"

#define TIMING

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

    .label StartUpdateCharsetIrqRasterLine = 30
    .label StartZoomerIrqRasterLine = 49 - 1

    .label Charset1Address = $3000
    .label Charset2Address = $3800
    .label ScratchBufferAddress = $2d00
    .label Screen = $0400
    .label SineValuesAddress = $2e00
}

main:
    sei                                         // no other irqs during set

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

    ldx #0
    lda SineValues,x
    sta irqStartUpdateCharset.currentWidth
    stx irqStartUpdateCharset.currentWidth+1
    jsr irqStartUpdateCharset.updateCharsets
    jsr irqStartCloneCharset.cloneCharsetBytes

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

    lda #Configuration.StartUpdateCharsetIrqRasterLine
    sta VIC.CURRENT_RASTERLINE_REG              
    lda #<irqStartUpdateCharset
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqStartUpdateCharset
    sta Internals.InterruptHandlerPointerRomHi
    
    txs                                         // get stack pointer from first irq back

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti


.align $100
irqZoomerStart: {
    SaveIrqRegistersZPWithTimer(Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
    
    // waste one rasterline
    .fill 10, NOP

    ldy $d012                   // 4:  6
    dey                         // 2:  8
    dey                         // 2: 10
    tya                         // 2: 12
    ldx sineIndex: #0           // 2:  2
    adc SineValues,x            // 4: 16
    bcs doneWithScreen          // 2: 18
    tax                         // 2: 20
    and #%00000111              // 2: 22
    cmp #3                      // 2: 24
    bne !+                      // 2: 26
    dex                         // 2: 28
    inc isbadline               // 4: 32
    jmp !++                     // 3: 35
!:
    txa                         // 1+2: 29
    sta $d012
    nop                         // 2: 31
    nop                         // 2: 33 
    nop                         // 2: 35
!:  bit $01                     // 3: 38

    lda isbadline: #0
    beq !+
    // waste
    bit $01
    bit $01
    .fill 7, NOP
    
!:    
    lda d018Value: #0   // @$38/56
    sta $d018           // @58
                        // 62    
#if TIMING
    lda $d020
    pha
    lda #RED
    sta $d020//inc $d020
#endif

    lda $d011
    bmi doneWithScreen

    lda $d018
    eor #((Configuration.Charset1Address & $3800)/$800*2)^((Configuration.Charset2Address&$3800)/$800*2)
    sta d018Value

    lda #0
    sta isbadline
   
    jmp endInterrupt

doneWithScreen:

    inc sineIndex
    ldx sineIndex
    lda SineValues,x
    sta irqStartUpdateCharset.currentWidth
    lda #0
    sta irqStartUpdateCharset.currentWidth+1

    irq_set(irqStartCloneCharset, $105)
    
    lda #(Configuration.Screen & $3c00)/$400*$10 + (Configuration.Charset1Address & $3800)/$800*2
    sta irqZoomerStart.d018Value
    jmp endInterrupt

nextCharline:
    sta $d012
endInterrupt:
    lsr VIC.INTERRUPT_EVENT                     

#if TIMING
    pla
    sta $d020
#endif

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}


.align $100
irqStartUpdateCharset: {
    irq_save()

#if TIMING
    lda $d020
    pha

    lda #YELLOW
    sta $d020
#endif

    lsr $d019

    lda #Configuration.StartZoomerIrqRasterLine        
    sta VIC.CURRENT_RASTERLINE_REG              
    lda #<irqZoomerStart
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqZoomerStart
    sta Internals.InterruptHandlerPointerRomHi

    // allow other raster irqs to interrupt this one
    cli

    jsr updateCharsets

endInterrupt:
#if TIMING
    pla
    sta $d020
#endif
    @irq_endRaster()

updateCharsets: 

    // temp for debugging, remove later
    //lda #12
    //sta currentWidth
    //lda #0
    //sta currentWidth+1

    // reset charset pointer for both normal and inverted charset
    lda #<TempCharset1
    sta Charset1AdressLo1
    sta Charset1AdressLo2
    lda #<TempCharset2
    sta Charset2AdressLo1
    sta Charset2AdressLo2
    lda #>TempCharset1
    sta Charset1AdressHi1
    sta Charset1AdressHi2
    lda #>TempCharset2
    sta Charset2AdressHi1
    sta Charset2AdressHi2

    // may change with x,y offset
    lda #0
    sta color

    // initialize remainging counters
    
    //lda #$10
    //sta currentWidth

    ldy #0
    sty remainingPixels
pixelLoop:
    sec
    lda currentWidth
    sbc remainingPixels
    sta remainingWidth
    lda currentWidth+1
    sbc #0
    sta remainingWidth+1

    // get the remaining pixels after drawing full characters
    lda remainingWidth
    bne !+
!:
    and #%00000111
    sta remainingPixels

    // divide 16 bit number / 8 to get the number of full characters to draw
    lsr remainingWidth+1 // max is 320, so only 1 bit in hi byte, so we can just shift it out
    ror remainingWidth      // possibly take the hi bytes bit
    lsr remainingWidth      // from here it's just shift right
    lsr remainingWidth      // one more for div by 8

    lda remainingWidth
    beq drawRemainingPixels

!:
    tax                     // number of full chars to draw
moreRemainingPixelsLeft:
    lda color
store8PxInCharset:
.label Charset1AdressLo1 = * + 1
.label Charset1AdressHi1 = * + 2
    sta $dead,y 
    eor #$ff
.label Charset2AdressLo1 = * + 1
.label Charset2AdressHi1 = * + 2
    sta $dead,y
    iny
    cpy #40
    beq doneUpdating
    dex
    bne moreRemainingPixelsLeft 
    jmp drawRemainingPixels

drawRemainingPixels:
    ldx remainingPixels: #0
    beq noRemainingPixels
    lda patterns,x
    ldx color
    bne storeRemainingPxInCharset
    eor #$ff
storeRemainingPxInCharset:
.label Charset1AdressLo2 = * + 1
.label Charset1AdressHi2 = * + 2
    sta $dead,y 
    eor #$ff
.label Charset2AdressLo2 = * + 1
.label Charset2AdressHi2 = * + 2
    sta $dead,y 

    iny
    cpy #40
    beq doneUpdating

    sec
    lda #8
    sbc remainingPixels
    sta remainingPixels

noRemainingPixels:
    lda color
    eor #$ff
    sta color
 
    jmp pixelLoop

doneUpdating:
    //lda #BLACK
    //sta $d020
    rts

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

totalRemainingPixels:
    .byte 0, 0
currentWidth:
    .byte 0, 0
remainingWidth:
    .byte 0,0
color: 
    .byte 0
}

.align $100
irqStartCloneCharset: {
    irq_save()

#if TIMING
    lda $d020
    pha 

    lda #GREEN
    sta $d020
#endif
    jsr cloneCharsetBytes
    
endInterrupt:
#if TIMING
    pla
    sta $d020
#endif

    irq_set(irqStartUpdateCharset, Configuration.StartUpdateCharsetIrqRasterLine)
    
    @irq_endRaster()

cloneCharsetBytes: {

    ldx #(20)*8
    ldy #20-1
!:
    lda TempCharset1,y
    sta Configuration.Charset1Address - 8 + 0,x
    sta Configuration.Charset1Address - 8 + 1,x
    sta Configuration.Charset1Address - 8 + 2,x
    sta Configuration.Charset1Address - 8 + 3,x
    sta Configuration.Charset1Address - 8 + 4,x
    sta Configuration.Charset1Address - 8 + 5,x
    sta Configuration.Charset1Address - 8 + 6,x
    sta Configuration.Charset1Address - 8 + 7,x

    lda TempCharset1+20,y
    sta Configuration.Charset1Address - 8 + 20*8 + 0,x
    sta Configuration.Charset1Address - 8 + 20*8 + 1,x
    sta Configuration.Charset1Address - 8 + 20*8 + 2,x
    sta Configuration.Charset1Address - 8 + 20*8 + 3,x
    sta Configuration.Charset1Address - 8 + 20*8 + 4,x
    sta Configuration.Charset1Address - 8 + 20*8 + 5,x
    sta Configuration.Charset1Address - 8 + 20*8 + 6,x
    sta Configuration.Charset1Address - 8 + 20*8 + 7,x

    lda TempCharset2,y
    sta Configuration.Charset2Address - 8 + 0,x
    sta Configuration.Charset2Address - 8 + 1,x
    sta Configuration.Charset2Address - 8 + 2,x
    sta Configuration.Charset2Address - 8 + 3,x
    sta Configuration.Charset2Address - 8 + 4,x
    sta Configuration.Charset2Address - 8 + 5,x
    sta Configuration.Charset2Address - 8 + 6,x
    sta Configuration.Charset2Address - 8 + 7,x    

    lda TempCharset2+20,y
    dey
    sta Configuration.Charset2Address - 8 + 20*8 + 0,x
    sta Configuration.Charset2Address - 8 + 20*8 + 1,x
    sta Configuration.Charset2Address - 8 + 20*8 + 2,x
    sta Configuration.Charset2Address - 8 + 20*8 + 3,x
    sta Configuration.Charset2Address - 8 + 20*8 + 4,x
    sta Configuration.Charset2Address - 8 + 20*8 + 5,x
    sta Configuration.Charset2Address - 8 + 20*8 + 6,x
    sta Configuration.Charset2Address - 8 + 20*8 + 7,x    

    txa
    sec
    sbc #8
    tax
    bne !-

    rts
}

}

.macro SaveIrqRegistersZPWithTimer (AccuZpLocation, XRegZpLocation, YRegZpLocation) {
    sta AccuZpLocation        // 2: 9 + jitter
    lda $dc04                 // 4: 15
    stx XRegZpLocation        // 2: 17
    sty YRegZpLocation        // 2: 19

    and #%00001111            // 2: 21 mask timer value
    sta delay                 // 4: 25
    lda #12                   // 2: 27
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
    lda     #$a9        
    lda     #$a9        
    lda     #$a9       
    lda     $eaa5
    // stable at cycle 53 on the same raster line
}

.macro irq_set(label, rasterline) {
    lda $d011
    .if (rasterline > 255) {
        ora #%10000000
    } else {
        and #%01111111
    }
    sta $d011
    
    lda rasterLine: #<rasterline
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
    .fill $100, 6 + sin(toRadians((i / $100) * 180)) * (180 - 6)

* = Configuration.ScratchBufferAddress  "SCRATCH" virtual
TempCharset1:
    .fill 40, 0
TempCharset2:
    .fill 40, 0

* = Configuration.Charset1Address  "Charset 1" virtual
    .fill 256*8, 0

* = Configuration.Charset2Address "Charset 2" virtual
    .fill 256*8, 0

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