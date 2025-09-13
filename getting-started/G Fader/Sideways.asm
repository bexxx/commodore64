.filenamespace Fader

#import "../../../commodore64/includes/irq_helpers.asm"
#import "../../../commodore64/includes/BezierEasings.asm"

.namespace Configuration {
   .label FaderInterruptAddress = $1000
   .label FaderInterruptRasterLine = $fe
   .label ScreenTargetAddress = $0400
   .label Irq1AccuZpLocation = $f0
   .label Irq1XRegZpLocation = $f1
   .label Irq1YRegZpLocation = $f2
   .label MainBackgroundColor = BLUE
}

BasicUpstart2(main)

main:
    sei                                         // don't allow other irqs to happen during setup
    lda #<NmiHandler                            // change nmi vector to unacknowledge "routine"
    sta $0318
    lda #>NmiHandler
    sta $0319
    lda #$00
    sta $dd0e                                   // stop timer a
    sta $dd04                                   // set timer a to 0, after starting nmi will occur immediately
    sta $dd05
    lda #$81
    sta $dd0d                                   // set timer a as source for nmi
    lda #$01
    sta $dd0e                                   // start timer a and trigger nmi

    lda #%01111111                              // disable timer on CIAs mask
    sta $dc0d                                   // disable all CIA1 irqs
    sta $dd0d                                   // disable all CIA2 irqs

    lda #$35
    sta $1                                      // disable ROM

    irq_set(Fader.irqFader, Configuration.FaderInterruptRasterLine)
    lda $d011
    and #$7f                                 
    sta $d011                                   

    lda #%00000001
    sta $d01a                                   // enable raster irq
    
    lda $d021
    sta irqFader.fadeColorToBlue.initialScreenColor
    lda $d020
    sta irqFader.fadeColorToBlue.initialBorderColor

    lsr $d019                                   // ack raster interrupt

    BusyWaitForNewScreen()

    cli

!:  jmp !-

NmiHandler:
    rti                                         // just rti, no ack


* = Configuration.FaderInterruptAddress
.align $100
.segment Default "Fader"
irqFader: {
    sta Configuration.Irq1AccuZpLocation        // save register values
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    jmp pt_main_irq: phase_fadeToRight

phase_fadeToRight:
    jsr fadeToRight
    jmp doneWithInterrupt

phase_fadeToBlue:
    jsr fadeColorToBlue
    dec counter
    bne doneWithInterrupt
    // LDX#40: done with fader, add your setup code here.
    // don't forget to ack raster irq
    .break
    jmp doneWithInterrupt

counter:
    .byte 128
doneWithInterrupt:
    lsr $d019                                   // ack raster interrupt

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti

fadeToRight: {
    jmp pt_fader: !+
!:
    delay_autorepeat(pt_fader, 2)
    ldx column: #0
    lda #$e0

    .for (var i = 0; i < 25; i++) {
        sta Configuration.ScreenTargetAddress + i * 40,x
    }

    lda $d020
    .for (var i = 0; i < 25; i++) {
        sta $d800 + i * 40,x
    }

    inc column
    lda column
    cmp #40
    beq done

    rts

done:
    lda #<phase_fadeToBlue
    sta pt_main_irq
    lda #>phase_fadeToBlue
    sta pt_main_irq + 1

    lda #1
    sta $d012

    lda #%00000000
    sta $d011
    rts
}

fadeColorToBlue: {

slideDownScreenColor:
    ldy #Configuration.MainBackgroundColor
    sty $d020
    sty $d021

    ldx slideDownScreenColorIndex: #0
    lda slideDownYOffsetsLo,x        // load lo byte of y value
    sta rasterLine                   // store in code
    lda slideDownYOffsetsHi,x        // load the opcode used in code for the y value
    sta checkRasterMsbBranchOpcode   // store in code

    ldy initialScreenColor: #LIGHT_BLUE
    ldx initialBorderColor: #LIGHT_BLUE

checkRasterMsb:
    lda $d011                                   // check MSB of raster line
checkRasterMsbBranchOpcode:
    bpl checkRasterMsb                          // using either bmi or bpl from table below

checkRasterLine:  
    lda $d012                                   // load current raster line
    cmp rasterLine: #$ff                        // compare with current y value (previously written)
    bne checkRasterLine

    inc slideDownScreenColorIndex
    lda slideDownScreenColorIndex
    bmi endOfSlideDown

    .fill 21, NOP                               // add some delay to push flickering to non visible part of screen

    stx $d020
    sty $d021
    jmp done

endOfSlideDown:
    lda #BLUE
    sta $d021
    sta $d020

done:
    rts
}

.align $100 
.segment Default "Fader data"//* = $bf00 "Color slide down offsets"
slideDownYOffsets:
    .var bgYOffsets = List()
    .for (var i=0; i < 128 ; i++) {
        // https://cubic-bezier.com/#.16,1.48,.68,-0.04
        .var value = floor(cubicBezierEasing(i, 2, 315, 128, 0.16,1.48,0.68,-0.04))
        .eval bgYOffsets.add((value & 3) == 3 ? value - 1 : value)
    }

    .align $80
slideDownYOffsetsLo:
    .fill bgYOffsets.size(), <(bgYOffsets.get(i))
slideDownYOffsetsHi:
    .fill bgYOffsets.size(), (bgYOffsets.get(i)) < 255 ? BMI_REL : BPL_REL
}

.macro BusyWaitForNewScreen() {
waitForNewFrame:
    lda $d011
    bpl waitForNewFrame                         // 7th bit is MSB of rasterline, wait for the next frame
!:  lda $d011
    bmi !-                                      // wait until the 7th bit is clear (=> line 0 of raster)
}