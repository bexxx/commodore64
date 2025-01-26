#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/common.inc"

#define TheWholeShebang

.namespace Configuration {
    .label Irq1AccuZpLocation = $2
    .label Irq1XRegZpLocation = $3
    .label Irq1YRegZpLocation = $4

    .label ScrollSpeed = 2
    .label RasterInterruptLine = ($33 + 23*8 - 4)
    .label ScreenBufferAddress = $6400
    .label TextBufferOffset = (ScreenBufferAddress + 23*40)

    .label ScrollerCodeAddress = $3000
}

#if TheWholeShebang // not part of the El Hefe version, standalone for debugging
    BasicUpstart2(main)
#endif 

* = Configuration.ScrollerCodeAddress "Startup"
    jmp init                                    // expose a jsr target to init this part
    jmp interruptHandler                        // expose a jsr target to get called in raster irq
    jmp fadeout                                 // expose a jsr target for basic fader

#if TheWholeShebang
main:
    jsr fadeout
    jsr init
    lda #WHITE
    sta $d020
    sta $d021

    sei
    lda #$35
    sta $01

    lda #<interruptHandler                      
    sta $fffe
    lda #>interruptHandler
    sta $ffff

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    lda #Configuration.RasterInterruptLine
    sta $d012              
    
    lda $d011                                   // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta $d011                                   // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt   

    cli                                         // allow interrupts to happen again

waitForever:                                          // remove line before and uncomment to not go back to basic
    jmp waitForever

#endif 

fadeout: {
    BusyWaitForNewScreen()

    // crappy fade out, not raster synched. yeah I know I should do better ...
    lda VIC.BORDER_COLOR
    and #$f
    tax
    lda fadeouttable,x
    sta VIC.BORDER_COLOR

    lda VIC.SCREEN_COLOR
    and #$f
    tax
    lda fadeouttable,x
    sta VIC.SCREEN_COLOR

    ldx #0
 !:  
    lda $d800,x
    and #$f
    tay
    lda fadeouttable,y
    sta $d800,x

    lda $d900,x
    and #$f
    tay
    lda fadeouttable,y
    sta $d900,x

    lda $da00,x
    and #$f
    tay
    lda fadeouttable,y
    sta $da00,x

    lda $db00,x
    and #$f
    tay
    lda fadeouttable,y
    sta $db00,x
    dex
    bne !-
    
    dec frameCounter
.label frameCounter = *+1
    lda #$f
    bne fadeout

    // now that colors are all black, clear screen
    lda #$20
    ldx #0
!:  sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    dex
    bne !-

fadein: {
    BusyWaitForNewScreen()

    // crappy fade out, not raster synched. yeah I know I should do better ...
    lda VIC.BORDER_COLOR
    and #$f
    tax
    lda fadeintable,x
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR
    
    dec frameCounter
    lda frameCounter: #$f
    bne fadein
}
    rts
}

fadeouttable:
    .byte BLACK, LIGHT_GREEN, DARK_GREY, GREEN, RED, LIGHT_RED, BROWN, LIGHT_GREY, PURPLE, BLACK, GREY, BLUE, LIGHT_BLUE, YELLOW, ORANGE, CYAN

fadeintable:
    .byte BLUE, WHITE, DARK_GREY, ORANGE, ORANGE, LIGHT_GREEN, BROWN, WHITE, LIGHT_BLUE, RED, YELLOW, PURPLE, LIGHT_GREY, CYAN, LIGHT_BLUE, BLUE

init:
    lda #$1
    sta currentCharacterSlice

    lda #$7
    sta currentXScrollOffset

    lda #<scrollText
    sta scrollTextLo
    lda #>scrollText
    sta scrollTextHi

    ldx #0
    lda #$20
!:  sta Configuration.ScreenBufferAddress + $0000,x
    sta Configuration.ScreenBufferAddress + $0100,x
    sta Configuration.ScreenBufferAddress + $0200,x
    sta Configuration.ScreenBufferAddress + $0300,x
    dex
    bne !-

    ldx #2*40
    lda #BLACK
!:  sta $d800 + 23*40,x
    dex
    bpl !-

    lda #WHITE
    sta $d800 + 23*40 + 0
    sta $d800 + 24*40 + 0
    sta $d800 + 23*40 + 38
    sta $d800 + 24*40 + 38

    lda #YELLOW
    sta $d800 + 23*40 + 1
    sta $d800 + 24*40 + 1 
    sta $d800 + 23*40 + 37
    sta $d800 + 24*40 + 37
    
    lda #LIGHT_RED
    sta $d800 + 23*40 + 2
    sta $d800 + 24*40 + 2
    sta $d800 + 23*40 + 36
    sta $d800 + 24*40 + 36
    
    lda #ORANGE
    sta $d800 + 23*40 + 3
    sta $d800 + 24*40 + 3
    sta $d800 + 23*40 + 35
    sta $d800 + 24*40 + 35

    lda #BROWN
    sta $d800 + 23*40 + 4
    sta $d800 + 24*40 + 4
    sta $d800 + 23*40 + 34
    sta $d800 + 24*40 + 34

    lda #BROWN
    sta $d800 + 23*40 + 5
    sta $d800 + 24*40 + 5
    sta $d800 + 23*40 + 33
    sta $d800 + 24*40 + 33

    rts

.align $100                                     // align on the start of a new page
.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem
                                                // helpful to check whether it all fits into the same page
interruptHandler:
#if TheWholeShebang
    sta Configuration.Irq1AccuZpLocation
    stx Configuration.Irq1XRegZpLocation
    sty Configuration.Irq1YRegZpLocation
    lda #%00011011
    sta $d011
#endif 
    
    lda $d016                           
    and #%11100000                              
    ora currentXScrollOffset                       
    sta $d016   

#if TheWholeShebang    
    lda $d018
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora #VIC.SELECT_CHARSET_AT_2800_MASK
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    ora #VIC.SELECT_SCREENBUFFER_AT_2400_MASK
    sta $d018                       

    lda $dd00 
    and #~%11
    ora #%00000010
    sta $dd00
#endif

    lda $d016                                   // already calculate the 0 xscroll value for the next
    and #11111000
                                                // character line after the scrolling line
    ora #00000011

waitToCharacterLineEnd:
    ldx $d012                                   // wait until we hit the last raster line of the scroller
    cpx #251              
    bne waitToCharacterLineEnd

scrollForward:                                  // not that we are passed the scrolled line with the raster
    lda currentXScrollOffset                    // we determine the next xscroll value and move the characters
    sec                                         // of the line if needed.
    sbc #Configuration.ScrollSpeed
    and #%00000111
    sta currentXScrollOffset
    bcc scrollOneSliceLeft
    jmp exit

scrollOneSliceLeft:    
    ldx #0                                      // move all characters one position to the left
!:                                              // loop forward to not overwrite character before
    lda Configuration.TextBufferOffset +  1,x   // reading
    sta Configuration.TextBufferOffset +  0,x
    lda Configuration.TextBufferOffset + 41,x                    
    sta Configuration.TextBufferOffset + 40,x
    inx
    cpx #39
    bne !-

checkForNewCharacter:
    lda currentCharacterSlice
    bne readNextScrollTextCharacter
    lda currentRightmostCharacter
    clc
    adc #$40
    dec currentCharacterSlice
    jmp insertCharacterForward

readNextScrollTextCharacter:
.label scrollTextLo = *+1                   
.label scrollTextHi = *+2
    lda scrollText                              // we need to modify either this lda target by code 
    bne moveScrollPointerForward                // or use indirect addressing to have a scroll text
                                                // longer than 255 characters (limit of x/y indexing) 
    lda #<scrollText                            // reset to start when we observe 0 byte (end marker)
    sta scrollTextLo
    lda #>scrollText
    sta scrollTextHi 
    jmp readNextScrollTextCharacter

insertCharacterForward:
    dec currentCharacterSlice
    jmp printCharacterSlice

moveScrollPointerForward:    
    ldx #0

checkForCloseBracket:
    cmp #' '                                    // do not use 2 char width for some characters
    beq reduceGap
    jmp !+

reduceGap:
    inx
!:
    stx currentCharacterSlice

    sta currentRightmostCharacter
    inc scrollTextLo                            // insert new character on the right
    bne printCharacterSlice                     // and update scroll text pointer
    inc scrollTextHi

printCharacterSlice:
    sta Configuration.TextBufferOffset + 39     // after moving the line to the left,
    ora #$80
    sta Configuration.TextBufferOffset + 39 + 40    // after moving the line to the left,
    
exit:

#if TheWholeShebang
    lsr $d019
    ldy Configuration.Irq1YRegZpLocation
    ldx Configuration.Irq1XRegZpLocation
    lda Configuration.Irq1AccuZpLocation
    rti
#else 
    // when part of El Hefe, this just gets called with jsr
    rts
#endif 

currentXScrollOffset:
    .byte $07
currentRightmostCharacter:
    .byte $00
currentCharacterSlice:
    .byte $01

.segment Default "scrolltext" 
scrollText:
.text "            "

.text "le jefe, the hefe - we wish our beloved manager would be here with us in frankfurt tonight "
.text "for this very important meeting. but alas, nature said otherwise. so humble ldx#40 sends greetings to the " 
.text "man, hoping he gets well in time for the next big thing... so without further ado i pass the keyboard on to:"

.text "         bexxx at the jever bottle (wtf?): another item of my bucket list checked off:"
.text " coding parts of a party scroller intro and carefully selecting some opcodes."
.text " el jefe, hope you get better soon to catch up on the missed beers at bcc#19!"
.text " fok julle naaiers and fok afd/bsw/ptn/nzs/trmp, bexxx bottle drop (sorry ldx#40)..."

.text "         ldhicksi really should go to bed, but he tries his best and hawks out some very personal shout outs to... : "
.text "nerdisten - goerp - steel - 4gente - rebel1 - tom3000 - monte carlos - keen vox - and so many others i forgot about."

.text "         dyme is on the floor greeting el jever with a healthy burp and is sorry for everyone that is still reading this."
.text "   go get a hobby!   code a demo or something!"

.text "         bexxx sends out his greets to digger, fieser wolf, proton, hermit, jack asser, wvl, hcl,"
.text " bitbreaker and trident who helped me to improve coding recently and folks at forum64.de"
.text " and nerdroom who helped me to learn repairing c64s! much appreciated!"

.text "         code by dyme and bexxx, graphics by ldx#40 and groepaz, music by gerard hulting, carefully selected inspirations by dall-e"

.text "         for your convenience: soon we will loop the scroller. each time you pass this position please remember to have"
.text " a drink on our very one and only el jefe!                        "

.byte $00 

#if TheWholeShebang
    .align $6800
    .segment Default "charset"
    .import binary "dead2x2.prg", 2
#endif

