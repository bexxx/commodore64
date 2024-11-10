.filenamespace Fader

#import "configuration.asm"

* = Configuration.FaderInterruptAddress
.segment Default "Fader"

irqFader: {
    sta Configuration.Irq1AccuZpLocation        // save register values
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation

    lsr $d019                                   // ack raster interrupt

borderFading:                                   // fade down border to black
    lda doBorderFading: #1                      // flag to see if the current part should be executed or not
    beq screenBlanking                          // if disabled, go to the next part
    jsr borderFadeOneFrame                      // do updates for one frame
    jmp exitIrq                                 // done with this frame, exit raster irq

screenBlanking:                                 // black out the screen in blocks
    lda doScreenBlanking: #1
    beq waitForMusicToStart
    jsr blankScreenOneFrame
    jmp exitIrq

waitForMusicToStart:                            // delay the music on black screen a bit to increase drama
    lda doWaitForMusicToStart: #1
    beq petsciiFading
    jsr waitForMusikToStartOneFrame
    jmp exitIrq

petsciiFading:                                  // fade in the petscii logo with different column offsets
    lda doPetsciiFading: #1
    beq blinkBlinkText
    jsr fadeInPetsciiLogoOneFrame
    jmp exitIrq

blinkBlinkText:                                 // make the text in the logo blink
    lda doBlinkBlink: #1
    beq petsciiBlanking
    jsr blinkOneFrame
    jmp exitIrq

petsciiBlanking:                                // fase colors of logo out in blocks
    lda doPetsciiBlanking: #1
    beq setupNextPhase
    jsr blankPetsciiOneFrame
    jmp exitIrq

setupNextPhase:                                 // setup irq and stuff for the next phase
    lda doWait: #1
    dec waitIterations
    lda waitIterations: #30
    bne exitIrq
    lda #0
    sta doWait

#if Integrated                                  // when integrated, call LDX petscii animation
    lda #Configuration.RasterLinePetsciiIrq
    sta $d012
    lda #<Configuration.PetsciiScrollerAnimationCodeAddress
    sta $fffe
    lda #>Configuration.PetsciiScrollerAnimationCodeAddress
    sta $ffff
#else                                           // when not integrated just do top scroller irq
    lda #Configuration.RasterLineScrollerTopIrq
    sta $d012
    lda #<irq0
    sta $fffe
    lda #>irq0
    sta $ffff
#endif

    // petscii anomation needs ZP pointer setup
    jsr Configuration.PetsciiAnimationSetupAddress

    // clear top screen with spaces
    lda #$20
    ldx #0
!:
    sta Configuration.ScreenRamStartAddress + $0000,x
    sta Configuration.ScreenRamStartAddress + $0100,x
    dex
    bne !-

    // clear top colors with black
    lda #$0
    ldx #0
!:
    sta $d800,x
    sta $d900,x
    dex
    bne !-

exitIrq:
    lda musicEnabled: #0                        // in later phases of the fader, music needs to be called
    beq !+
#if EnableMusic

#if Timing
    inc $d020
#endif

    jsr music.play

#if Timing
    dec $d020
#endif

#endif
!:
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation

    rti
}

borderFadeOneFrame: {
    dec borderFaderDelayFrames
    lda borderFaderDelayFrames: #1
    bmi doneWithDelay
    rts

doneWithDelay:
    lda #1
    sta borderFaderDelayFrames
    lda $d020
    and #%00001111
    tax
    beq noMoreBorderFading
    lda fadeoutColors,x
    sta $d020
    rts

noMoreBorderFading:
    dec Fader.irqFader.doBorderFading           // stop doing the border fader
    lda #Configuration.RasterLineBlackOutIrq    // from now on execute code at bottom to not interfer with raster beam
    sta $d012
    rts
}

blankPetsciiOneFrame: {
    dec petsciiBlankingDelayFrames
    lda petsciiBlankingDelayFrames: #75         // initially wait longer then with next frames
    bmi doneWithDelay
    rts

doneWithDelay:
    lda #0
    sta petsciiBlankingDelayFrames              // when fading out the color of the same block, do this each frame

    // read colors of 5 rows and exchange with the fadeout color
    ldy #5 * 40
fadeoutLoop:
    lda (Configuration.ColorPointer2ZP),y
    and #$f                                     // color ram has upper nibble ramdomly set
    tax
    lda fadeoutColors,x
    sta (Configuration.ColorPointer2ZP),y
    dey
    bne fadeoutLoop

    // we need max 16 iterations to fade to black, so the same color ram range needs to be processed 16 times
    // before fading out the next color block
    dec petsciiBlankingBlockIterations
    lda petsciiBlankingBlockIterations: #16
    beq doneWithPetsciiBlankingBlock
    rts

doneWithPetsciiBlankingBlock:
    // now we need to point the ZP pointer to the next block (current pointer + 5 * 40)
    clc
    lda Configuration.ColorPointer2ZP
    adc #5 * 40
    sta Configuration.ColorPointer2ZP

    lda Configuration.ColorPointer2HiZP
    adc #0
    sta Configuration.ColorPointer2HiZP

    lda #16
    sta petsciiBlankingBlockIterations          // restore counter for processing the same block
    sta petsciiBlankingDelayFrames              // before fading out the next block, wait a bit

    dec petsciiBlankingIterations               // counter for the blocks
    lda petsciiBlankingIterations: #5
    beq doneWithPetsciiBlanking
    rts

doneWithPetsciiBlanking:
    dec Fader.irqFader.doPetsciiBlanking                       // disable this part from the main fader irq
    rts
}

waitForMusikToStartOneFrame: {
    dec waitForMusikToStartDelayFrames
    lda waitForMusikToStartDelayFrames: #50
    bmi doneWithDelay
    rts

doneWithDelay:
    dec Fader.irqFader.doWaitForMusicToStart                   // no more waiting
    inc Fader.irqFader.musicEnabled                            // turn it to 11!
    lda #$a8
    sta $d012
    rts
}

blankScreenOneFrame: {
    dec screenBlankingDelayFrames
    lda screenBlankingDelayFrames: #20
    bmi doneWithDelay
    rts

doneWithDelay:
    lda #20
    sta screenBlankingDelayFrames

    ldy #200
    lda #BLACK
colorRamLoop:
    sta (Configuration.ColorPointerZP),y
    dey
    bne colorRamLoop

    ldy #200
    lda #$a0                                    // inverse space, filled block
screenRamLoop:
    sta (Configuration.ScreenPointerZP),y
    dey
    bne screenRamLoop

    // update ZP pointer for next block of 5 rows (+ (5 * 40))
    clc
    lda Configuration.ScreenPointerZP
    adc #5 * 40
    sta Configuration.ScreenPointerZP
    sta Configuration.ColorPointerZP

    lda #0
    bcc skipCarry
    lda #1

skipCarry:
    sta fixup

    lda Configuration.ScreenPointerHiZP
    adc #0
    sta Configuration.ScreenPointerHiZP

    lda Configuration.ColorPointerHiZP
    adc fixup: #0                               // carry was consumed in previous adc, so we need adc 0 or adc 1 if there was a carry before
    sta Configuration.ColorPointerHiZP

    dec screenBlankingIterations
    lda screenBlankingIterations: #5
    beq doneWithScreenBlanking
    rts

doneWithScreenBlanking:
    dec Fader.irqFader.doScreenBlanking
    lda #BLACK
    sta $d021
    rts
}

blinkOneFrame: {
    dec blinkBlinkDelayFrames
    lda blinkBlinkDelayFrames: #2
    bmi doneWithDelay
    rts

doneWithDelay:
    lda #2
    sta blinkBlinkDelayFrames

    ldx #Configuration.BlinkTextLength  - 1
textColorLoop:
    lda highlightsLine1End - Configuration.BlinkTextLength,x    // load color of highlight
    bne !isNotTransparent+                      // if it is black take the original color (black is the transparent color)
    lda petsciiLogoColors + 20 * 40 + 14,x      // address is position of petscii logo colors
!isNotTransparent:
    sta $d800 + 20 * 40 + 14,x

    lda highlightsLine2End - Configuration.BlinkTextLength,x
    bne !isNotTransparent+
    lda petsciiLogoColors + 21 * 40 + 14,x
!isNotTransparent:
    sta $d800 + 21 * 40 + 14,x
    dex
    bpl textColorLoop

    ldx #(highlightsLine1End - highlightsLine1 - 2) // move colors to the right in the highlights
moveHighlightsLoop:
    lda highlightsLine1 + 0,x
    sta highlightsLine1 + 1,x
    lda highlightsLine2 + 0,x
    sta highlightsLine2 + 1,x
    dex
    bpl moveHighlightsLoop

    // insert black on the left side
    lda #BLACK
    sta highlightsLine1
    sta highlightsLine2

    dec blinkBlinkIterations
    lda blinkBlinkIterations: #(highlightsLine1End - highlightsLine1 + 1)
    beq doneWithBlinkBlink
    rts

doneWithBlinkBlink:
    dec Fader.irqFader.doBlinkBlink
    rts
}

fadeInPetsciiLogoOneFrame: {
    dec petsciiFaderDelayFrames
    lda petsciiFaderDelayFrames: #127           // initially wait a bit longer, not more than 127 to avoid being negative
    bmi doneWithDelay
    rts

doneWithDelay:
    lda #3
    sta petsciiFaderDelayFrames

#if TIMING
    inc $d020
#endif

    ldx #39
drawColumns:
    inc columnIndexes,x
    lda columnIndexes,x                         // indexes are initialized with $ff or less
    bpl isVisible                               // 0+ is visible
    jmp continueWithNextColumn                  // otherwise skip this column for this iteration

isVisible:
    bne notFirstRow                             // row 0 means just the cursor

    lda #1                                      // first row means just show cursor, not yet the petscii above
    sta doCursor
    lda #0
    sta doLogo
    jmp determineTargetAddresses

notFirstRow:
    cmp #25                                     // should we stop showing the cursor?
    beq !+                                      // yeah, just not show the cursor, still do petscii for one iteration
    bcs continueWithNextColumnJump              // 26 or more means just continue with the next column
    ldy #1
    jmp !++
continueWithNextColumnJump:
    jmp continueWithNextColumn

!:  ldy #0
!:
    sty doCursor
    lda #1
    sta doLogo

determineSourceAddresses:
    lda sourceLogoOffsetsLo,x                   // load current source address lo
    sta sourceLogoAddressLo                     // store in code
    sta sourceColorAddressLo                    // same lo address in color ram
    clc
    adc #40                                     // calc next lo address for next iteration
    sta sourceLogoOffsetsLo,x                   // save in buffer

    lda #0                                      // adjust hi address in case of page crossing,
    bcc !+                                      // add carry to both source addresses
    lda #1
!:
    sta fixupSourceColorAddress
    lda sourceLogoOffsetsHi,x
    sta sourceLogoAddressHi
    adc #0
    sta sourceLogoOffsetsHi,x

    lda sourceColorOffsetHi,x
    sta sourceColorAddressHi
    adc fixupSourceColorAddress: #0
    sta sourceColorOffsetHi,x

determineTargetAddresses:
    lda targetLogoOffsetsLo,x                   // initially one row below screen ram, but first iteration skips drawing logo line
    sta targetLogoAddressLo                     // store target lo bytes of address (same for logo and color)
    sta targetColorAddressLo
    clc
    adc #40
    sta targetLogoOffsetsLo,x                   // calc next lo address
    sta targetCursorAddressLo                   // next iteration logo lo address is current cursor low address of cursor
    sta targetCursorColorAddressLo              // and cursor color

    lda #0
    bcc !+
    lda #1
!:
    sta fixupTargetColorAddress
    lda targetLogoOffsetsHi,x                   // fetch current iteration target hi address
    sta targetLogoAddressHi                     // store into code
    adc #0                                      // if we crossed page in determining next iteration's lo address, consider this here
    sta targetLogoOffsetsHi,x                   // store for next iteration
    sta targetCursorAddressHi                   // next iterations logo hi address is this iterations cursor hi address

    lda targetLogoColorOffsetsHi,x              // fetch current logo color hi address
    sta targetColorAddressHi                    // store into code
    adc fixupTargetColorAddress: #0             // if we crossed page in determining next iteration's lo address, consider this here
    sta targetLogoColorOffsetsHi,x              // store for next iteration
    sta targetCursorColorAddressHi              // next iterations logo color hi address is this iterations cursor color hi address

drawLogoChar:
    lda doLogo: #0
    beq drawCursor

.label sourceLogoAddressLo = * + 1
.label sourceLogoAddressHi = * + 2
    lda $dead
.label targetLogoAddressLo = * + 1
.label targetLogoAddressHi = * + 2
    sta $beef

.label sourceColorAddressLo = * + 1
.label sourceColorAddressHi = * + 2
    lda $dead
.label targetColorAddressLo = * + 1
.label targetColorAddressHi = * + 2
    sta $beef

drawCursor:
    lda doCursor: #0
    beq continueWithNextColumn
    lda currentCursorCharacter: #119                                    // thin top line character
.label targetCursorAddressLo = * + 1
.label targetCursorAddressHi = * + 2
    sta $beef
    lda #WHITE
.label targetCursorColorAddressLo = * + 1
.label targetCursorColorAddressHi = * + 2
    sta $dead

continueWithNextColumn:
    dex
    bmi !+
    jmp drawColumns

!:
#if TIMING
    dec $d020
#endif

    dec iterationCounter
    lda iterationCounter: #40
    bpl notDoneWithFader

    dec Fader.irqFader.doPetsciiFading

notDoneWithFader:
    lda currentRasterIrqLine: #$38
    cmp #$f8
    beq !+
    clc
    adc #8
    sta currentRasterIrqLine
    sta $d012
!:
    rts
}

    // replacement color to fade to black
fadeoutColors:
    .byte BLACK, LIGHT_GREEN, DARK_GREY, GREEN, RED, LIGHT_RED, BROWN, LIGHT_GREY, PURPLE, BLACK, GREY, BLUE, LIGHT_BLUE, YELLOW, ORANGE, CYAN

columnIndexes:
    .byte $f5, $f5, $f5, $f6, $f6, $f7, $f7, $f8, $f8, $f9
    .byte $f9, $fa, $fa, $fb, $fb, $fc, $fc, $fd, $fd, $fe
    .byte $fe, $fd, $fd, $fc, $fc, $fb, $fb, $fa, $fa, $f9
    .byte $f9, $f8, $f8, $f7, $f7, $f6, $f6, $f5, $f5, $f5

.var blinkReflex = List()
.eval blinkReflex.add(LIGHT_GREY, WHITE, YELLOW, WHITE, LIGHT_GREY) // colors that form the blink highlight on the texyt
.var blinkReflexLine1 = List()
.eval blinkReflexLine1.add(BLACK)                                   // line 1 trails colors by one, add padding color to front
.eval blinkReflexLine1.addAll(blinkReflex)
.var blinkReflexLine2 = List()
.eval blinkReflexLine2.addAll(blinkReflex)
.eval blinkReflexLine2.add(BLACK)                                   // add padding color to back to make them the same length

highlightsLine1:
    .fill blinkReflexLine1.size(), blinkReflexLine1.get(i)          // working buffer for high light colors
    .fill Configuration.BlinkTextLength, BLACK
highlightsLine1End:

highlightsLine2:
    .fill blinkReflexLine2.size(), blinkReflexLine2.get(i)
    .fill Configuration.BlinkTextLength, BLACK
highlightsLine2End:

sourceLogoOffsetsLo:                                                // current lo addresses of the logo screen source for each column
    .fill 40, <(Configuration.SourceLogoAddress + i)
sourceLogoOffsetsHi:                                                // current hi addresses of the logo screen source for each column
    .fill 40, >(Configuration.SourceLogoAddress + i)
sourceColorOffsetHi:                                                // current hi addresses of the logo color source for each column (share lo)
    .fill 40, >(Configuration.SourceLogoColorAddress + i)
targetLogoOffsetsLo:                                                // current lo addresses of the logo screen target for each column
    .fill 40, <(Configuration.ScreenRamStartAddress + i - 40)
targetLogoOffsetsHi:                                                // current hi addresses of the logo screen target for each column
    .fill 40, >(Configuration.ScreenRamStartAddress + i - 40)
targetLogoColorOffsetsHi:                                           // current hi addresses of the logo color target for each column (share lo)
    .fill 40, >($d800 + i - 40)

* = Configuration.SourceLogoAddress
.segment Default "Petscii Logo Fader Screen"
fadeoutScreen:
	.byte	$20, $20, $20, $20, $20, $20, $20, $55, $49, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $55, $49, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $4a, $72, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $72, $4b, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $d5, $c3, $c3, $c9, $d5, $c3, $c9, $d5, $c3, $c9, $c2, $d5, $c3, $d5, $c3, $c3, $d5, $c3, $c9, $d5, $c3, $c9, $5d, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $c2, $a0, $a0, $c2, $c2, $a0, $c2, $c2, $a0, $a0, $c2, $c2, $a0, $c2, $a0, $a0, $c2, $a0, $dd, $c2, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $ca, $c0, $c9, $c2, $eb, $c3, $f3, $c2, $a0, $a0, $eb, $f1, $c9, $eb, $c3, $c3, $eb, $f2, $cb, $ca, $c3, $c9, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $c2, $c2, $c2, $a0, $c2, $c2, $a0, $a0, $c2, $a0, $c2, $c2, $a0, $a0, $c2, $c2, $a0, $a0, $a0, $c2, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $5d, $ca, $c3, $cb, $ca, $c3, $c3, $cb, $ca, $c3, $c3, $cb, $a0, $ca, $f1, $c3, $c3, $cb, $ca, $c3, $c3, $c3, $cb, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $6b, $43, $40, $40, $40, $40, $40, $40, $40, $40, $40, $72, $72, $40, $40, $40, $40, $40, $40, $40, $40, $40, $43, $73, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $42, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $42, $20, $6c, $79, $6f, $20, $20, $6f, $79, $7b, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $42, $20, $f9, $ef, $c4, $c3, $c3, $c4, $ef, $e2, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $42, $20, $20, $20, $20, $19, $77, $20, $20, $20, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $5d, $42, $20, $20, $20, $20, $5d, $20, $20, $20, $20, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $6b, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $42, $43, $43, $43, $43, $43, $43, $43, $43, $43, $43, $73, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $6b, $a0, $a0, $a0, $73, $20, $20, $20, $42, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $42, $ae, $a0, $a0, $6b, $49, $20, $20, $42, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $42, $a0, $a0, $ae, $42, $5d, $20, $20, $42, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $42, $a0, $ae, $a0, $6b, $4b, $20, $20, $42, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $20, $4a, $43, $43, $43, $4b, $20, $20, $20, $42, $5d, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $6b, $43, $43, $43, $43, $43, $43, $40, $40, $40, $40, $71, $71, $40, $40, $40, $40, $40, $40, $40, $40, $43, $43, $73, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $a0, $20, $a0, $a0, $e7, $20, $20, $09, $0e, $20, $04, $15, $02, $09, $0f, $20, $20, $e5, $a0, $a0, $20, $a0, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $42, $20, $a0, $20, $a0, $e7, $10, $12, $0f, $20, $03, $05, $12, $16, $09, $13, $09, $01, $e5, $a0, $20, $a0, $20, $42, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $4a, $43, $43, $43, $43, $43, $43, $40, $49, $49, $55, $72, $72, $49, $55, $55, $40, $40, $40, $40, $40, $43, $43, $4b, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $4a, $4b, $4a, $4b, $4a, $4b, $4a, $4b, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20
	.byte	$20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20, $20

* = Configuration.SourceLogoColorAddress
.segment Default "Petscii Logo Fader Colors"
petsciiLogoColors:
	.byte	$08, $0b, $0e, $0e, $0e, $0e, $0e, $01, $0c, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0c, $01, $0e, $01, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $01, $0f, $0f, $0f, $0f, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $01, $01, $01, $01, $01, $0e, $01, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $01, $0f, $0f, $0c, $0f, $0c, $0c, $0c, $0c, $0f, $0c, $0f, $0f, $01, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $01, $0f, $01, $0f, $0f, $0c, $0f, $0c, $0c, $0f, $0c, $0f, $0f, $01, $0f, $01, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $01, $0f, $01, $0c, $0f, $0c, $0f, $0f, $0c, $0f, $0c, $01, $0f, $01, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $01, $0f, $01, $0f, $0f, $0c, $0f, $0c, $0c, $0f, $0c, $0f, $0f, $01, $0f, $01, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $01, $0f, $0f, $0c, $0f, $0c, $0c, $0c, $0c, $0f, $0c, $0f, $0f, $01, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $0f, $0f, $0f, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $07, $01, $07, $0f, $07, $0f, $07, $0c, $07, $0c, $0c, $0e, $0e, $02, $02, $02, $02, $02, $02, $0e, $0e, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $07, $01, $07, $0f, $07, $0f, $07, $0c, $07, $0c, $0c, $0c, $09, $0a, $0a, $08, $0e, $0e, $09, $09, $09, $0c, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $07, $01, $07, $0f, $07, $0f, $07, $0c, $07, $0c, $0c, $0e, $0a, $08, $08, $08, $08, $09, $09, $0b, $0c, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $07, $01, $07, $0f, $07, $0f, $07, $0c, $07, $0c, $0c, $0c, $0e, $0e, $0e, $02, $0c, $08, $0e, $02, $0e, $0c, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $07, $01, $07, $0f, $07, $0f, $07, $0c, $07, $0c, $0c, $0e, $0e, $02, $02, $0c, $02, $02, $02, $01, $0c, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $0f, $0f, $0f, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $0e, $0e, $01, $0f, $0f, $0f, $0f, $0e, $0e, $0e, $0c, $0c, $0c, $04, $0c, $04, $0f, $04, $0f, $04, $01, $04, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0c
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $0e, $0c, $01, $07, $07, $07, $0f, $0f, $0c, $0e, $0c, $0c, $04, $0c, $04, $0c, $04, $0f, $04, $01, $04, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $0e, $0e, $01, $07, $07, $07, $0f, $0f, $0c, $0e, $0c, $0c, $0c, $04, $0c, $04, $0f, $04, $0f, $04, $01, $04, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $0e, $0e, $01, $07, $07, $07, $0f, $0f, $0e, $0e, $0c, $0c, $04, $0c, $04, $0c, $04, $0f, $04, $01, $04, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $0e, $09, $01, $0c, $0c, $0c, $0f, $09, $09, $0c, $0c, $0c, $0c, $04, $0c, $04, $0f, $04, $0f, $04, $01, $04, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $0f, $0f, $0f, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $00, $01, $0f, $01, $0e, $0e, $0c, $0c, $0e, $0c, $0c, $0c, $0c, $0c, $0e, $0f, $01, $0f, $01, $00, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $00, $01, $00, $01, $0f, $0f, $0f, $0c, $0e, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $01, $00, $01, $00, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $01, $01, $01, $01, $0f, $0f, $0f, $0f, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0f, $0f, $0f, $0f, $01, $01, $01, $01, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0c, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e
	.byte	$0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0b, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e, $0e