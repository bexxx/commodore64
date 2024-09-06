#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/internals.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"

// uncomment to compile it as part of the whole demo
// comment in to use it standalone
//#define integrated

#if !integrated
    BasicUpstart2(main)
#endif

*= $c000 "Code"
main:
    sei

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    sta CIA2.INTERRUPT_CONTROL_REG              

    lda #$35                                    // disable ROM
    sta Zeropage.PORT_REG
    
    lda VIC.BORDER_COLOR                        // figure out actual background color
    sta borderColor                             // use this in border fade down in case system has non default colors

    lda #<interruptBackgroundColor
    sta Internals.InterruptHandlerPointerRomLo
    lda #>interruptBackgroundColor
    sta Internals.InterruptHandlerPointerRomHi

    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure    
    lda CIA2.INTERRUPT_CONTROL_REG 
    lsr VIC.INTERRUPT_EVENT
    
    BusyWaitForNewScreen()                      // we start with a white screen on top
    ldx #VIC.white
    stx VIC.BORDER_COLOR

    cli

    jmp afterWait                               // jump to directly setting raster irq to slowly fade down border and not flicker on first iteration

blindsLoop:
    ldx rasterLineIndex                         // the raster line index was already incremented before, so we temporarily need to fix this up 
    dex                                         // for the 2 raster line increments during the wait frames
    lda rasterIrqLines,x
    tay                                         // save away to have it handy between wait frames

    ldx #VIC.white
    BusyWaitForNewScreen()
    stx VIC.BORDER_COLOR
    iny
    iny
    sty VIC.CURRENT_RASTERLINE_REG              // 2 raster line increments per wait frame
    
    BusyWaitForNewScreen()
    stx VIC.BORDER_COLOR
    iny
    iny
    sty VIC.CURRENT_RASTERLINE_REG

    lda firstLine                               // while waiting we can do the logo fading on top of screen
    cmp #24                                     // start when bottom blinds hit last char row. Blinds are 9 chars in height, so fading stops before blinds are gone.
    bcc blindsNotAtBottom
    jsr fadeOutLogo

blindsNotAtBottom:
    BusyWaitForNewScreen()
    stx VIC.BORDER_COLOR
    iny
    iny
    sty VIC.CURRENT_RASTERLINE_REG

afterWait:
    ldx rasterLineIndex
    cpx #(rasterIrqLinesEnd - rasterIrqLines + 1)
    beq skipRasterIrqSetup

    lda rasterIrqLines,x                        // at this moment, the index is correct, just use it
    sta VIC.CURRENT_RASTERLINE_REG
    lda rasterIrqLinesMsb,x
    sta VIC.SCREEN_CONTROL_REG
    inc rasterLineIndex

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits
    jmp waitForRasterChange

skipRasterIrqSetup:
    lda #0
    sta VIC.INTERRUPT_ENABLE                    // disable raster irqs

waitForRasterChange:
    lda VIC.CURRENT_RASTERLINE_REG              // in a frame we wait to a specific beam position to not modify screen ram where beam is drawing
    cmp rasterLineDrawing: #180                 // because the blinds move through the whole screen we change this raster line for the second half
    bne waitForRasterChange                     // to the upper screen part

    lda numberOfStepsBefore: #6                 // fade down the border for 6 steps before starting to draw blinds
    beq doBlinds

skipBlinds:
    dec numberOfStepsBefore
    jmp blindsLoop

doBlinds:
    lda linesToDraw                             // how many lines to draw for the blinds? in the beginning and end it's not the full height
    bne continueDrawing
    jmp exit

continueDrawing:
    sta currentLinesToDraw                      // store temp counter
    lda firstLine                               // where to start
    sta currentLine                             // store temp row
    lda firstCharacterIndex                     // what char to start with
    sta currentCharacterIndex                   // store temp char index

drawOneBlindsRowOnScreen:
    lda currentLinesToDraw: #$ff
    beq doneWithFrame

    ldy currentLine: #$ff                       // determine target address for current line in screen ram
    lda lineStartAddressesLo,y
    sta screenLineLo
    lda lineStartAddressesHi,y
    sta screenLineHi

    lda colorDefinitionAddressesLo,y            // determine source address for current line in logo colors
    sta colorSourceLo
    lda colorDefinitionAddressesHi,y
    sta colorSourceHi

    lda colorRamAddressesLo,y                   // determine target address for current line in color ram
    sta colorRamLo
    lda colorRamAddressesHi,y
    sta colorRamHi

    ldx currentCharacterIndex: #$ff             // load current char of the blind and draw it
    lda charTableBlindsStart,x
    jsr drawOneLine

    lda isNewLine                               // if this is a new line, we need to also update color ram
    beq isNoNewLine
    jsr colorOneLine
    dec isNewLine

isNoNewLine:
    dec currentLine                             // update indexes for the next blinds row
    dec currentCharacterIndex
    dec currentLinesToDraw
    bne drawOneBlindsRowOnScreen                // loop until all lines are drawn

doneWithFrame:
    lda hitEndOfScreen: #$0                     // check if we are in the bottom, where only border gets faded down
    bne blindsNotGrowing
    lda linesToDraw                             // determine whether we are in the top part where the number of lines increases
    cmp #(charTableBlindsEnd-charTableBlindsStart+1)
    beq blindsNotGrowing                        // stop increasing when we hit full blind height
    inc linesToDraw

blindsNotGrowing:
    lda firstLine
    cmp #(24)
    bne blindsDidNotHitBottom
    dec linesToDraw
    dec firstCharacterIndex
    inc hitEndOfScreen
    jmp noBlindDrawingJustBorder

blindsDidNotHitBottom:
    lda firstLine
    cmp #16                                     // in the beginning, drawing was at bottom part of screen, when blinds move down
    bne noRasterLineUpdate
    lda #30                                     // change to top of screen to not update the part while the beam is drawing it
    sta rasterLineDrawing                       // poor man's approach to double buffer and nice irq routines
noRasterLineUpdate:
    inc isNewLine
    inc firstLine   
noBlindDrawingJustBorder:
    jmp blindsLoop

exit:                                           // transition to end or next part
    BusyWaitForNewScreen()
    lda #VIC.white
    sta VIC.SCREEN_COLOR                        // also set screen color to white
    sta borderColor                             // in case the raster irq still gets executed, let it set border to white again
    lda #$13                                           
    sta VIC.SCREEN_CONTROL_REG                  // disable screen to avoid flickering in transition
    BusyWaitForNewScreen()                      // wait for new frame to be sure disabling screen worked

#if integrated
    jmp $0900                                   // jump to next demo part
#else 
!:  jmp !-                                      // Stay a while, stay forever.
#endif 

drawOneLine:
    ldx #39
.label screenLineLo = * + 1
.label screenLineHi = * + 2
!:
    sta $0400,x                                 // dump character in accu 40 times into screen ram
    dex
    bpl !-
    rts

colorOneLine:
    ldx #39
.label colorSourceLo = * + 1
.label colorSourceHi = * + 2
!:    
    lda $dead,x                                 // copy 40 colors from logo into screen ram
.label colorRamLo = * + 1
.label colorRamHi = * + 2
    sta $dead,x
    dex
    bpl !-
    rts

fadeOutLogo:
    ldy #15                                     // logo is 16 chars wide
!: 
    .for (var i = 0; i<16; i++) {               // do some fricking speed code to not flicker. I hate color ram. srsly
        lda $d800 + 5*40 + i*40 + 12,y          // load current color
        and #%00001111                          // only take color part
        tax
        lda fadeColors,x                        // get replacement/next fade color
        sta $d800 + 5*40 + i*40 + 12,y          // store back
    }
    dey
    bmi !+
    jmp !-
!:
    rts

interruptBackgroundColor:
    sei

    pha
    txa
    pha
    tya
    pha

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    lda borderColor: #VIC.lblue                 // the border color that was set before demo started
    sta VIC.BORDER_COLOR                        // set previous border color for border fade down
    lsr VIC.INTERRUPT_EVENT                     // ack raster irq

noRasterInterrupt:
    pla
    tay        
    pla
    tax        
    pla        
    cli

    rti

linesToDraw:
    .byte 1                                     // start with one line
isNewLine:
    .byte 1                                     // first line is a new line, trigger coloring
firstLine:
    .byte 0                                     // start top ofd screen, 1st char row
firstCharacterIndex:
    .byte charTableBlindsEnd-charTableBlindsStart       // start with the last char of the blinds (thinnest line)

charTableBlindsStart:
    .byte $a0, $e3, $f7, $f8, $62, $79, $6f, $64, $64   // blinds definition, last char is the one at the bottom
.label charTableBlindsEnd = *-1

lineStartAddressesLo:                           // precalculated addresses
    .fill 25, <($0400 + (i * 40))
lineStartAddressesHi:
    .fill 25, >($0400 + (i * 40))
colorRamAddressesLo:
    .fill 25, <($d800 + (i * 40))
colorRamAddressesHi:
    .fill 25, >($d800 + (i * 40))
colorDefinitionAddressesLo:
    .fill 25, <(logoColors + (i * 40))
colorDefinitionAddressesHi:
    .fill 25, >(logoColors + (i * 40))

rasterLineIndex:                                // where to change the border color from white to original one for fading down
    .byte 0
rasterIrqLines:
    .fill 38, <($1) + i * 8
.label rasterIrqLinesEnd = *-1
rasterIrqLinesMsb:
    .fill 38, (($1) + i * 8) > 255 ? $1b | %10000000 : $1b  // do steps of 8 raster lines and avoid bad lines

fadeColors:                                     // red grey tones only, mgmt wants special color scheme
    .byte 9, $1, $b, $1, $1, $1, $1, $1, $1, $2, $f, $c, $a, $1, $1, $1

logoColors:                                     // dumped from https://petscii.krissz.hu/ petscii assembler source export
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $01, $00, $00, $01, $01, $01, $00, $00, $00, $01, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $01, $00, $00, $01, $01, $01, $00, $00, $00, $01, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $00, $00, $00, $00, $00, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $00, $00, $01, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $01, $00, $00, $00, $01, $01, $01, $00, $00, $01, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $01, $00, $00, $00, $01, $01, $01, $00, $00, $01, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00, $00, $00, $00, $00, $00, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01
	.byte	$01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01