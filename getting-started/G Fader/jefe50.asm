.filenamespace Fader

#import "../../../commodore64/includes/irq_helpers.asm"
#import "../../../commodore64/includes/BezierEasings.asm"
#import "../../../commodore64/includes/common_gfx_functions.asm"

.namespace Configuration {
   .label FaderInterruptAddress = $1000
   .label FaderInterruptRasterLine = $50
   .label Irq1AccuZpLocation = $f0
   .label Irq1XRegZpLocation = $f1
   .label Irq1YRegZpLocation = $f2
   .label flipBoardDelay = 12
   .label cursorBlinkDelay = 12
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
    
    lsr $d019                                   // ack raster interrupt

    jsr busyWaitForNewScreen

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

    jsr faderSequence

doneWithInterrupt:
    lsr $d019                                   // ack raster interrupt

    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

faderSequence: {
    jmp pt: resetPhase

resetPhase:
    lda $d016
    and #%11110111
    sta $d016
    
    delay(pt, 60)
    
startScreenPhase:
       lda $d016
    ora #%00001000
    sta $d016

    jsr clearScreen
    jsr showBootScreen

    continue_with(pt, blinkOnStartScreen)
    
blinkOnStartScreen:
    jsr cursorBlinking
    parallel_delay(pt, 14 * Configuration.cursorBlinkDelay)    

    jsr flipBoardOneFrame.init
    continue_with(pt, flipboardPhase)
    
flipboardPhase:
    jsr cursorBlinking
    jsr flipBoardOneFrame

    rts    

fallingCursorPhase:
    jsr cursorBlinking
    delay(pt, 5)
    
    ldx #$20
.label currentCursorAddress1Lo = * + 1
.label currentCursorAddress1Hi = * + 2
    lda $0400 + 6*40
.label currentCursorAddress2Lo = * + 1
.label currentCursorAddress2Hi = * + 2
    stx $0400 + 6*40
.label nextCursorAddress1Lo = * + 1
.label nextCursorAddress1Hi = * + 2
    sta $0400 + 7*40

    lda nextCursorAddress1Hi
    sta currentCursorAddress1Hi
    sta currentCursorAddress2Hi
    lda nextCursorAddress1Lo
    sta currentCursorAddress1Lo
    sta currentCursorAddress2Lo
    clc
    adc #40
    sta nextCursorAddress1Lo
    bcc !+
    inc nextCursorAddress1Hi
!:
    lda cursorLine
    inc cursorLine
    cmp #25
    bne !+

.var colorsScroller = List().add($0f,$0c,$0b,$00,$0b,$0c)
.var colorsScroller_length = colorsScroller.size()
ldx #colorsScroller_length

    continue_with(pt, !+)

!:

    jmp !-

    rts



cursorLine:
    .byte 6

cursorBlinking: {
    jmp pt: !+

!:
    delay_repeatable(pt, Configuration.cursorBlinkDelay)
    lda $0400 + 6*40
    eor #%10000000
    sta $0400 + 6*40

    rts
}

clearScreen:
    ldx #$0
    lda #' '
!:  sta $0400,x
    sta $0410,x
    sta $0420,x
    sta $0430,x
    inx
    bne !-

    ldx #$0
    lda #LIGHT_BLUE
!:  sta $d800,x
    inx
    bne !-

    rts

startText1:
    .var bootScreenText1 = "**** commodore 64 basic v2 ****"
    .text bootScreenText1
startText2:
    .var bootScreenText2 = "64k ram system  38911 basic bytes free"
    .text bootScreenText2
startText3:
    .var bootScreenText3 = "ready."
    .text bootScreenText3

showBootScreen:
    ldx #bootScreenText1.size() - 1
!:
    lda startText1,x
    sta $0400 + 40 + 4,x
    dex
    bpl !-

    ldx #bootScreenText2.size() - 1
!:
    lda startText2,x
    sta $0400 + 3 * 40 + 1,x
    dex
    bpl !-

    ldx #bootScreenText3.size() - 1
!:
    lda startText3,x
    sta $0400 + 5 * 40,x
    dex
    bpl !-
    rts
}



flipBoardOneFrame: {
    lda frameCounter: #Configuration.flipBoardDelay
    beq doneFlippingOneCharacter
    ldx startIndex: #0
    clc
!:  
.label textStartAddress1Lo = * + 1
    lda $0400,x
    adc #1 
    and #%00111111
.label textStartAddress2Lo = * + 1
    sta $0400,x

    inx
    cpx textLength: #3
    bne !-

    dec frameCounter
    jmp doneWithFrame

doneFlippingOneCharacter:
    ldx textIndex: #0
.label textSourceAddressLo = * + 1
.label textSourceAddressHi = * + 2
    lda $dead,x
.label textStartAddress3Lo = * + 1
    sta $0400,x
    inc textIndex

    lda startIndex
    clc
    adc #1
    sta startIndex
    cmp textLength
    beq doneWithWord
    jmp resetFrameCounter

doneWithWord:
    ldx currentWord
    lda textLengths,x
    clc
    adc textSourceAddressLo
    sta textSourceAddressLo
    inx
    stx currentWord
    lda textLengths,x
    beq allDone
    sta textLength
    lda targetOffsets,x
    sta textStartAddress1Lo
    sta textStartAddress2Lo
    sta textStartAddress3Lo
    lda #0
    sta startIndex
    sta textIndex

resetFrameCounter:
    lda #Configuration.flipBoardDelay
    sta frameCounter
    rts

doneWithFrame:
    rts

allDone:
    jmp allDone
    lda #<faderSequence.fallingCursorPhase
    sta faderSequence.pt
    lda #>faderSequence.fallingCursorPhase
    sta faderSequence.pt + 1
    rts

init:
    lda #<targetStrings
    sta textSourceAddressLo
    lda #>targetStrings
    sta textSourceAddressHi
    lda targetOffsets
    sta textStartAddress1Lo
    sta textStartAddress2Lo
    sta textStartAddress3Lo
    lda textLengths
    sta textLength
    rts
.align $100

targetStrings:
    .var word1 = " 50"
    .var word2 = "yrs"
    .var word3 = "eljefe"
    .var word4 = "happy"
    .var word5 = "b-day"
    .var word6 = "dude!"
    .var word7 = " ]s["
    
    .text word1
    .text word2
    .text word3
    .text word4
    .text word5
    .text word6
    .text word7

targetOffsets:
    .var xOffsets = List()
    .eval xOffsets.add(1, 5, 9, 17, 23, 29, 35)
    .fill xOffsets.size(), xOffsets.get(i) + 3 * 40

textLengths:
    .byte word1.size(), word2.size(), word3.size(), word4.size(), word5.size(), word6.size(), word7.size()
    .byte 0 // end marker

currentWord:
    .byte 0
}