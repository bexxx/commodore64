#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"

.filenamespace SimpleD011Stretcher

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

    jsr fillScreen

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

irqStretcherStart: {
irqStableDemo:
row: 
    .for (var i=0; i<25; i++) {
        SaveIrqRegistersZPWithTimer(Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
        nop             // 2: 57

 badline:  
        ldx stretch: #1 // 2: 59
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
.break
        lda $d012
        cmp #250
        bpl !+ 
        jmp endFrame
!:
        .fill 10, NOP
        lda $d012
        adc #6
        sta irqwait.irqset.rasterLine
        irqwait: irq_wait($ff, Configuration.IrqStretchAccuZpLocation, Configuration.IrqStretchXRegZpLocation, Configuration.IrqStretchYRegZpLocation)
    }

    .fill 50, NOP

endFrame:

    ldx irqStretcherStart.row[0].stretch
    cpx 200
    bne !+
    ldx #0
!:
    inx
    stx irqStretcherStart.row[0].stretch
    stx irqStretcherStart.row[1].stretch
    stx irqStretcherStart.row[2].stretch
    stx irqStretcherStart.row[3].stretch
    stx irqStretcherStart.row[4].stretch
    stx irqStretcherStart.row[5].stretch
    stx irqStretcherStart.row[6].stretch
    stx irqStretcherStart.row[7].stretch

    lda #%00011011
    sta $d011


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

//		ldx #7		;2		
//		beq +		;4
//		lda $D011	;8
//-		bit $ea			;03
//		clc				;05
//		adc #$01		;07
//		and #$07		;09
//		ora #$38		;11
//;		lda #$01		;11
//		sta $D011		;15
//		dex				;17
//		bne -			;20	



//!:

//    lda $d012       // 4: 19
//    cmp #$fe
//    bne !+
//    jmp done

//.break
    // fix $d011 after visible screen for next frame
//!:
//    lda $d012
//    cmp #252
//    bne !-
//    lda #%00011011
//    sta $d011
//
//
//    // check whether done
//    // else repeat
//
//done:    
//   inc stretch
//    lda stretch
//    cmp 200
//    bne !+
//    lda #1
//    sta stretch
//!:
//    jmp newFrame   




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

stabilize:
    lda $d011
    bpl stabilize
stabilize2:
    lda $d011
    bmi stabilize2

    ldx #47
!:  
    cpx $d012           // 4: 4
    bne !-              // 2/3: 7

    // execution timing by opcode: 
    // https://codebase64.c64.org/doku.php?id=base:6510_instruction_timing&s[]=opcode
    // the earliest time when the cpx has read the row number in the last of the 4 cycles.
    // to compare the current raster line with the desired one the row number must be read in the last cycle of the cpx
    // this means the shortest execution  looks like 
    // last read cycles of cpx (1) + bne (no jump==2) = 3 cycles
    // longest execution is when line changed after cpx:
    // bne (3) + cpx (4) + bne (2) = 9
    // this means the jitter is between 3 and 9
    // the main idea of the following code is to use the knowledge of the current jitter and
    // divide it by half with each further line

    // so here we want now to add 63 - (9 - 3 + 1) / 2 cycles and check again then we would know
    // we had 3-5 or 6-9 jitter
    jsr cycles_43       // 6 + 43:  [52-58]
    bit $ea             // 3:       [55-61]
    nop                 // 2:       [57-63]
    cpx $d012           // 4:       [61-67] 64,65,66,67=4cycles, when its not equal
    beq skip1           // 2,3:  x=next line           61,62,63 when it's equal
    // too early        // 2:       [63-69]             we could be in 63-65 now, jitter 1-3 cycles
    nop                 // 2:       [ 2- 5]
    nop                 // 2:       [ 4- 7]

skip1:    
    jsr cycles_43       // 49:      [53-56]
    bit $ea             //  3:      [56-59]
    nop                 //  2:      [58-61]
    cpx $d012           //  4:      [62-65]
    beq skip2           // 2,3
    // too early        //  2:      [ 1- 2]
    bit $ea             //  3:      [ 4- 5]


skip2:    
    jsr cycles_43       // 49:      [53-55]
    nop                 //  2:      [55-57]
    nop                 //  2:      [59-61]
    nop                 //  2:      [61-63]
    cpx $d012           //  4:      []
    bne onecycle
onecycle: 

rts

cycles_43:
    ldy #$06            // 2:            2
lp2:
    dey                 // 2:6*2=12     14
    bne lp2             // 3:5*3=15     29
                        // 2:           31   
    inx                 // 2:           33
    nop                 // 2:           35
    nop                 // 2:           37
    rts                 // 6:           43



//
//
//    // we multiplay this code 25 times, but we might be done earlier and need to
//    // skip some of these fragments
//
//    ldy $d012           // n-1
//    iny                 // n                 
//    iny                 // n + 1
//
//    ldx #repetition
//!:
//    tya
//    and #%11111000
//    lda $d011
//    lda #00             // 2: 02
//    sta $d011           // 4: 06
//    lda #00             // 2: 08
//    dex                 // 2: 10
//    bpl !-              // 2,3
//    bne !+              // 3: 11
//    cpy #$fa            // 2: 13
//    bmi                 //
//    jmp ende
//!:  
//
//
//
//    ldx #repetition
//
//ende:

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

.macro irq_wait(rasterLine, AccuZpLocation, XRegZpLocation, YRegZpLocation) {
    .errorif rasterLine > 255, "raster line number > 255, implement a irq_wait_ex instead"
    
    irqset: irq_set(next, rasterLine)

    irq_endRaster(AccuZpLocation, XRegZpLocation, YRegZpLocation)                             // restore reg values and return from irq

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