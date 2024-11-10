    // ./exomizer sfx basic ~/Commodore64/sources/commodore64-private/bin/we_come_in_petscii.prg 
    // -o ~/Commodore64/sources/commodore64-private/bin/we_come_in_petscii.prg 
    // -s "jsr highest_addr_out" 
    // -X 'inc $dbe4' 
    // -f 'ldx #$6 lda #$20 lp: sta $07e1,x dex bpl lp'

    // -s: add text to screen before decrunching
    // -X: flash dot on screen in slow decrunch progress
    // -f: remove text after decrunching

    * = $0801
    .import binary "../../bin/we_come_in_petscii_main.prg", 2

    // this will be called from exomizer basic startup with a sys, see -s argument
    // basically print some text with defined colors at bottom right of screen
    ldx #6
maketext:
    lda decrunchText,x
    sta $0400 + 25 * 40 - (decrunchTextEnd-decrunchText),x
    lda #$0f
    sta $d800 + 25 * 40 - (decrunchTextEnd-decrunchText),x
    dex
    bpl maketext

    rts

decrunchText:
    .text "fck.nzs"
decrunchTextEnd: