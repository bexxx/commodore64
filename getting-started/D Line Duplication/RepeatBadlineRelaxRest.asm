#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"

.filenamespace SimpleD011Stretcher

// based on Trident's / FailightTV video "$D011 Mayhem". This is the cheap stretcher.
// YT: https://www.youtube.com/watch?v=0KhH4YrUsXo

// uncomment to fill screen with std font characters instead of logo
//#define USE_ROM_FONT

// uncomment to show border indicator for stretch value compute time indicator
//#define SHOW_TIMING

.namespace Configuration {
    .label RasterLineIrqSetup = $20             // start line for raster interrupt
    .label RasterLineIrqDemo = $28
    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04       

    .label IrqStretchAccuZpLocation = $02
    .label IrqStretchXRegZpLocation = $03
    .label IrqStretchYRegZpLocation = $04       

    .label StartStretchIrqRasterLine = 50
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

#if USE_ROM_FONT
    jsr fillScreen
#else
    jsr copyLogo
#endif 

!:    jmp !-

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

.align $100                                     // align on the start of a new page
.segment Default "stretcher code"               // shows the bytes for this code, when using -showmem

.align $80
irqStretcherStart: {
row: 
    .for (var i=0; i<25; i++) {     // generate this codeblock 25 times for each char row. Instead of codegen, this block can be reused, when updating the stretch value at the end of each row.
        SaveIrqRegistersZPWithTimer(Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
        nop             // 2: 57

 badline:  
        ldx stretch: #0 // 2: 59
        beq !++         // 2: 61 / 3: 62
        lda $d011       // 4: 63
!:
        bit $1          // 3: 3     wasting 3 spare cycles
        clc             // 2: 5
        adc #1          // 2: 7     make next line a badline
        and #%00000111  // 2: 9     fix possible yscroll overflow
        ora #%00010000  // 2: 11    fix other $d011 bits
        sta $d011       // 4: 15    
        dex             // 2: 17    keep badlines until stretch for this char line is done
        bne !-          // 2/3: 20, just 2 or 3 R cycles, can be interrupted any cycle, so we have 20 cycles only for this badline

!:
        lda $d011
        bmi quit
        lda $d012
        cmp #247
        bcc !+ 
        jmp endFrame
!:
        .fill 10, NOP   // still within the badline, make sure, we are on the next raster line when loading current line
        lda $d012       // calculate line for next raster irq
        adc #6
        bcc !+
        jmp endFrame
!:      cmp #247
        bcc !+
quit:   jmp endFrame
!:
        sta irqwait.irqset.rasterLine
        irqwait: irq_wait(
            $ff, 
            Configuration.IrqStretchAccuZpLocation, 
            Configuration.IrqStretchXRegZpLocation, 
            Configuration.IrqStretchYRegZpLocation,
            $80)
    }

endFrame:

#if SHOW_TIMING
    inc $d020
#endif 

    lda #0
    sta $20
    clc
    ldx sine1Index: #(SineTable120End - SineTable120 - 1)
    ldy sind2Index: #(SineTable95End - SineTable95 - 1)
    .for (var i=0; i<25; i++) {
        sta irqStretcherStart.row[i].stretch
    }
    .for (var i=0; i<25; i++) {
        lda SineTable120,x
        clc
        adc SineTable95,y
        sta irqStretcherStart.row[i].stretch
        adc $20
        bcc !+
        jmp endStretchUpdate
   !:     
        adc #7
        sta $20
        cmp #200
        bcc !+
        jmp endStretchUpdate
    !:
        dex
        bne !+
        ldx #(SineTable120End - SineTable120 - 1)
    !:
        dey
        bne !+
        ldy #(SineTable95End - SineTable95 - 1)
    !:
    }
endStretchUpdate:

       dec sine1Index
        bne !+
        ldx #(SineTable120End - SineTable120 - 1)
        stx sine1Index
    !:
        dec sind2Index
        bne !+
        ldy #(SineTable95End - SineTable95 - 1)
        sty sind2Index
!:
    lda #%00011011
    sta $d011

#if SHOW_TIMING
    dec $d020
#endif 

    lda #<irqStretcherStart
    sta Internals.InterruptHandlerPointerRomLo
    lda #>irqStretcherStart
    sta Internals.InterruptHandlerPointerRomHi
    lda #Configuration.StartStretchIrqRasterLine
    sta $d012

    lsr VIC.INTERRUPT_EVENT                     // 6: 25 ack raster irq
    
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

.align $100
.segment Default "sine table source"
SineTable120:
    .const sine1_length = 60
    .fill sine1_length, 5 + (5 * sin(toRadians((i*360)/(sine1_length)))) 
SineTable120End:

SineTable95:
    .const sine2_length = 75
    .fill sine2_length, 5 + (5 * sin(toRadians((i*360)/(sine2_length)))) 
SineTable95End:

#if !USE_ROM_FONT
copyLogo:
    ldx #0
!:  lda screen + $000,x
    sta $0400,x
    lda screen + $100,x
    sta $0500,x
    lda screen + $200,x
    sta $0600,x
    lda screen + $300,x
    sta $0700,x

    lda colors + $000,x
    sta $d800,x
    lda colors + $100,x
    sta $d900,x 
    lda colors + $200,x
    sta $da00,x
    lda colors + $300,x
    sta $db00,x

    lda screen_001
    sta $d020
    lda screen_001 + 1
    sta $d021

    dex
    bne !-
    rts

#else

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
#endif 

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

#if !USE_ROM_FONT
screen_001:
.byte 0,0

*=$3000
screen:
	.byte	$A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $6F, $6F, $6F, $02, $5F, $A0, $A0, $20, $6F, $6F, $6F, $05, $E2, $20, $6F, $6F, $6F, $6F, $6F, $6F, $6F, $33, $E1, $A0, $A0, $A0, $69, $20, $6F, $6F, $18, $E1, $61, $20, $6F, $6F, $6F, $20, $E1
	.byte	$61, $F4, $F0, $A0, $CD, $20, $5F, $A0, $75, $F4, $F0, $EA, $CD, $20, $5F, $A0, $A0, $A0, $A0, $A0, $A0, $EE, $A0, $E1, $A0, $A0, $69, $E9, $A0, $A0, $EE, $A0, $E1, $61, $A0, $A0, $A0, $EE, $A0, $E1
	.byte	$61, $F4, $C2, $A0, $A0, $CD, $20, $5F, $75, $F4, $C2, $EA, $A0, $CD, $20, $5F, $A0, $A0, $A0, $A0, $A0, $C2, $A0, $E1, $A0, $69, $20, $A0, $A0, $A0, $C2, $A0, $E1, $7E, $E9, $A0, $A0, $C2, $A0, $E1
	.byte	$61, $F4, $A1, $A0, $A0, $A0, $CD, $20, $7E, $F4, $A1, $EA, $A0, $A0, $CD, $20, $6C, $F8, $F8, $20, $A0, $A1, $A0, $E1, $69, $20, $A0, $A0, $69, $F4, $A1, $A0, $7C, $E9, $A0, $A0, $A0, $A1, $A0, $E1
	.byte	$61, $F4, $AE, $EA, $5F, $A0, $A0, $CD, $20, $F4, $AE, $EA, $5F, $A0, $A0, $CD, $7C, $A0, $69, $E9, $A0, $AE, $A0, $7C, $20, $A0, $A0, $69, $2F, $F4, $AE, $A0, $E9, $A0, $A0, $CE, $69, $AE, $A0, $E1
	.byte	$61, $F4, $A0, $EA, $DF, $5F, $A0, $A0, $DF, $F4, $A0, $E7, $DF, $5F, $A0, $A0, $DF, $7C, $E9, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A0, $69, $F4, $A0, $AF, $A0, $A0, $CE, $69, $20, $A0, $FD, $E1
	.byte	$61, $F4, $A0, $EA, $E2, $E9, $A0, $CE, $69, $F4, $A0, $E7, $E2, $E9, $A0, $CE, $69, $E9, $A0, $A0, $CE, $69, $79, $79, $79, $79, $79, $79, $7B, $F4, $AF, $A0, $A0, $CE, $69, $E9, $62, $62, $68, $FF
	.byte	$61, $F4, $A0, $EA, $A0, $A0, $A0, $69, $E9, $F4, $A0, $A0, $A0, $A0, $CE, $69, $E9, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $20, $AF, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A1, $FE
	.byte	$61, $F4, $A0, $E7, $A0, $A0, $DF, $E1, $A0, $F4, $A0, $A0, $A0, $CE, $69, $E9, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $69, $E9, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $EA, $A0, $A0, $A0, $DF, $5F, $F4, $A0, $A0, $CE, $69, $E9, $A0, $A0, $CE, $69, $E1, $A0, $A0, $A0, $A0, $A0, $A0, $69, $E9, $A0, $A0, $CE, $AF, $67, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $EA, $5F, $A0, $A0, $A0, $DF, $F4, $A0, $A0, $69, $F8, $5F, $A0, $A0, $A0, $CD, $7C, $FB, $A0, $A0, $A0, $A0, $69, $E9, $A0, $A0, $CE, $AF, $E7, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $EA, $DF, $5F, $A0, $A0, $AE, $E5, $A0, $EA, $4E, $E2, $7E, $5F, $EF, $A0, $A0, $CD, $7C, $FB, $A0, $A0, $69, $E9, $A0, $A0, $CE, $AF, $A0, $EA, $69, $78, $78, $78, $78, $78, $AE, $A0
	.byte	$61, $F4, $A0, $EA, $69, $E9, $A0, $CE, $69, $F4, $A0, $EA, $E9, $A0, $A0, $AE, $CE, $A0, $A0, $A0, $CD, $7C, $A0, $69, $E9, $A0, $A0, $CE, $69, $F4, $A0, $EA, $E9, $A0, $A0, $AE, $69, $E9, $FB, $A0
	.byte	$61, $F4, $A0, $EA, $E9, $A0, $CE, $69, $7B, $F4, $A0, $EA, $E9, $A0, $CE, $69, $79, $5F, $A0, $A0, $A0, $DF, $7E, $E9, $A0, $A0, $CE, $69, $7B, $F4, $A0, $EA, $E9, $A0, $CE, $69, $E9, $FC, $AE, $A0
	.byte	$61, $F4, $A0, $A0, $A0, $CE, $69, $E9, $61, $F4, $A0, $A0, $A0, $CE, $69, $E9, $69, $E9, $A0, $A0, $AE, $69, $E9, $A0, $A0, $CE, $69, $E9, $61, $F4, $A0, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $A0, $A0, $69, $E9, $A0, $61, $F4, $A0, $A0, $A0, $69, $E9, $69, $E9, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $69, $E9, $A0, $61, $F4, $A0, $A0, $A0, $69, $E9, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $A0, $20, $E9, $A0, $A0, $61, $F4, $A0, $A0, $20, $E9, $69, $20, $A0, $A0, $CE, $69, $7B, $F4, $A0, $A0, $34, $E9, $A0, $A0, $61, $F4, $A0, $A0, $20, $E9, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $A0, $20, $E9, $A0, $A0, $A0, $61, $F4, $A0, $20, $E9, $69, $20, $A0, $A0, $CE, $69, $E9, $61, $F4, $A0, $32, $E9, $A0, $A0, $A0, $61, $F4, $A0, $20, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $F4, $20, $E9, $A0, $A0, $A0, $A0, $61, $F4, $20, $E9, $69, $20, $A0, $A0, $CE, $69, $E9, $A0, $61, $F4, $30, $E9, $A0, $A0, $A0, $A0, $61, $F4, $20, $E9, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $69, $E9, $A0, $A0, $A0, $A0, $A0, $20, $69, $E9, $69, $20, $A0, $A0, $CE, $69, $E9, $A0, $A0, $32, $69, $E9, $A0, $A0, $A0, $A0, $AC, $20, $69, $E9, $AE, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$61, $E9, $AE, $A0, $A0, $A0, $A0, $A0, $7B, $E9, $69, $20, $A0, $A0, $CE, $69, $E9, $A0, $A0, $BA, $7B, $E9, $AE, $A0, $A0, $A0, $A0, $EC, $7B, $E9, $AC, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$7F, $EC, $A0, $A0, $A0, $A0, $A0, $A0, $A1, $69, $20, $A0, $A0, $CE, $69, $E9, $A0, $A0, $A0, $AE, $DA, $7F, $A0, $A0, $A0, $A0, $A0, $AE, $C8, $DA, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$DA, $A0, $A0, $A0, $A0, $A0, $A0, $AE, $69, $E9, $EF, $EF, $EF, $69, $E9, $A0, $A0, $A0, $A0, $A0, $AE, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A1, $FB, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0
	.byte	$AE, $A0, $A0, $A0, $A0, $A0, $A0, $EC, $62, $62, $62, $62, $62, $62, $FB, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $AE, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0, $A0

*=$4000
colors:
	.byte	$05, $05, $05, $05, $05, $05, $03, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $03, $0E, $03, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05, $05
	.byte	$05, $01, $01, $01, $0B, $05, $05, $05, $0E, $01, $01, $01, $0B, $05, $01, $01, $01, $01, $01, $01, $01, $01, $0B, $05, $03, $03, $05, $05, $0B, $01, $01, $0B, $05, $05, $0B, $01, $01, $01, $0B, $05
	.byte	$05, $01, $01, $01, $0F, $01, $05, $05, $05, $01, $01, $01, $0F, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $05, $03, $05, $05, $01, $01, $01, $01, $01, $05, $05, $01, $01, $01, $07, $07, $05
	.byte	$05, $01, $01, $01, $01, $0F, $05, $05, $05, $01, $01, $01, $01, $0F, $01, $01, $01, $01, $01, $01, $01, $01, $01, $05, $05, $05, $01, $01, $01, $01, $01, $01, $05, $05, $01, $01, $07, $07, $07, $05
	.byte	$05, $01, $01, $01, $01, $01, $0F, $01, $05, $01, $01, $01, $01, $01, $0F, $01, $05, $05, $05, $01, $01, $01, $07, $05, $05, $01, $01, $01, $01, $01, $01, $01, $05, $01, $01, $07, $07, $07, $07, $05
	.byte	$05, $01, $01, $01, $01, $01, $01, $0F, $01, $01, $01, $01, $01, $01, $01, $0F, $05, $05, $05, $01, $01, $07, $07, $05, $01, $01, $01, $01, $05, $01, $01, $01, $01, $01, $07, $07, $07, $07, $07, $05
	.byte	$05, $01, $01, $01, $05, $01, $01, $01, $01, $01, $01, $01, $05, $01, $01, $01, $01, $05, $01, $01, $07, $07, $07, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $07, $07, $07, $01, $07, $07, $05
	.byte	$05, $01, $01, $01, $05, $01, $01, $01, $01, $01, $01, $01, $05, $01, $01, $01, $01, $01, $01, $07, $07, $07, $05, $05, $05, $05, $05, $05, $05, $01, $01, $01, $07, $07, $07, $05, $05, $05, $05, $05
	.byte	$05, $01, $01, $01, $01, $01, $01, $01, $05, $01, $01, $01, $01, $01, $01, $01, $01, $01, $07, $07, $07, $05, $05, $03, $03, $03, $03, $05, $01, $01, $01, $07, $07, $07, $05, $05, $03, $03, $03, $03
	.byte	$05, $01, $01, $01, $01, $01, $01, $05, $05, $01, $01, $01, $01, $01, $01, $01, $01, $07, $07, $07, $05, $03, $03, $0E, $0E, $03, $05, $05, $01, $01, $07, $07, $07, $05, $05, $03, $0E, $0E, $0E, $0E
	.byte	$05, $01, $01, $01, $01, $01, $01, $01, $05, $01, $01, $01, $01, $01, $01, $01, $07, $07, $07, $05, $03, $03, $0E, $0E, $03, $05, $05, $01, $01, $07, $07, $07, $05, $05, $03, $0E, $0E, $0E, $0E, $0E
	.byte	$05, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $05, $01, $07, $07, $07, $0F, $05, $05, $03, $03, $03, $05, $05, $01, $01, $07, $07, $07, $01, $05, $05, $03, $03, $03, $03, $03, $0E
	.byte	$05, $01, $01, $01, $05, $01, $01, $07, $07, $01, $01, $01, $05, $05, $05, $07, $07, $07, $01, $0F, $05, $05, $03, $05, $05, $01, $01, $07, $07, $07, $01, $01, $05, $05, $05, $05, $05, $05, $05, $03
	.byte	$05, $01, $01, $01, $05, $01, $07, $07, $07, $01, $01, $01, $01, $01, $07, $07, $07, $01, $01, $01, $0F, $05, $05, $05, $01, $01, $07, $07, $07, $01, $01, $01, $01, $01, $07, $07, $07, $05, $05, $03
	.byte	$05, $01, $01, $01, $01, $07, $07, $07, $05, $01, $01, $01, $01, $07, $07, $07, $05, $01, $01, $01, $07, $07, $05, $01, $01, $07, $07, $07, $05, $01, $01, $01, $01, $07, $07, $07, $05, $05, $03, $03
	.byte	$05, $01, $01, $01, $07, $07, $07, $05, $05, $01, $01, $01, $07, $07, $07, $05, $05, $01, $01, $07, $07, $07, $01, $01, $07, $07, $07, $05, $05, $01, $01, $01, $07, $07, $07, $05, $05, $03, $03, $0E
	.byte	$05, $01, $01, $07, $07, $07, $05, $05, $05, $01, $01, $07, $07, $07, $05, $05, $01, $01, $07, $07, $07, $01, $01, $07, $07, $07, $05, $05, $05, $01, $01, $07, $07, $07, $05, $05, $03, $03, $0E, $0E
	.byte	$05, $01, $07, $07, $01, $05, $05, $03, $05, $01, $07, $07, $01, $05, $05, $01, $01, $07, $07, $07, $05, $01, $07, $07, $0B, $05, $05, $03, $05, $01, $07, $07, $01, $05, $05, $03, $03, $0E, $0E, $0E
	.byte	$05, $07, $07, $01, $05, $05, $03, $03, $05, $07, $07, $01, $05, $05, $0E, $01, $07, $07, $07, $05, $05, $07, $07, $0B, $05, $03, $03, $03, $05, $07, $07, $01, $05, $05, $03, $03, $0E, $0E, $0E, $0E
	.byte	$05, $07, $01, $05, $05, $03, $03, $05, $05, $07, $01, $05, $05, $0E, $01, $07, $07, $07, $05, $05, $05, $07, $0B, $05, $05, $03, $03, $05, $05, $07, $01, $05, $05, $03, $03, $0E, $0E, $0E, $0E, $0E
	.byte	$05, $07, $05, $05, $03, $03, $03, $05, $05, $07, $05, $05, $0E, $01, $07, $07, $07, $05, $05, $05, $0B, $07, $05, $05, $03, $03, $03, $05, $0E, $07, $05, $05, $03, $03, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$05, $05, $05, $03, $03, $0E, $03, $05, $05, $05, $05, $0E, $01, $07, $07, $07, $05, $05, $03, $05, $05, $05, $05, $03, $03, $0E, $03, $05, $05, $05, $05, $03, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$05, $05, $03, $03, $0E, $0E, $03, $03, $05, $05, $0E, $01, $07, $07, $07, $05, $05, $03, $03, $05, $05, $05, $03, $03, $0E, $0E, $03, $03, $05, $05, $03, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$03, $03, $03, $0E, $0E, $0E, $03, $05, $05, $01, $01, $07, $07, $07, $05, $05, $03, $03, $0E, $03, $05, $03, $03, $0E, $0E, $0E, $0E, $03, $03, $03, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
	.byte	$0E, $0E, $0E, $0E, $0E, $0E, $03, $05, $05, $05, $05, $05, $05, $05, $05, $03, $03, $0E, $0E, $03, $03, $03, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E, $0E
#endif 
