#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/cia2_constants.inc"

BasicUpstart2(main)
.var music = LoadSid("Bohemian_Rhapsody.sid")

* = $0900 "Code"
main:
    // --- setup music -------------------------
    lax #0
    tay
    lda #music.startSong - 1
    //jsr music.init

    // --- setup graphics ----------------------
    //jsr clearScreen1
    //jsr clearScreen2    
    jsr setupGraphics
    jsr setupKoalaColors
    //jsr setupBackgroundColors

!:  // --- main loop ---------------------------
    //jsr music.play
    jmp !-

setupGraphics:
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK2_MASK)    

    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    and #VIC.SELECT_BITMAP_CLEAR_MASK
    ldx #BLACK
    stx VIC.BORDER_COLOR
    ora #VIC.SELECT_SCREENBUFFER_AT_0000_MASK
    ora #VIC.SELECT_BITMAP_AT_2000_MASK
    sta VIC.GRAPHICS_POINTER

    lda VIC.SCREEN_CONTROL_REG
    ora #VIC.ENABLE_BITMAP_MODE_MASK
    sta VIC.SCREEN_CONTROL_REG
 
    lda VIC.CONTR_REG
    ora #VIC.ENABLE_40_COLUMNS_MASK
    sta VIC.CONTR_REG

    lda VIC.CONTR_REG                           
    ora #VIC.ENABLE_MULTICOLOR_MASK
    and #%11111000                              
    sta VIC.CONTR_REG    
    rts

setupKoalaColors:
    ldx #$00
!:
    lda koala_colors + $000,x
    sta $d800 + $000,x
    lda koala_colors + $100,x
    sta $d800 + $100,x
    lda koala_colors + $200,x
    sta $d800 + $200,x
    lda koala_colors + $300,x
    sta $d800 + $300,x
    dex
    bne !-

    rts



* = music.location "Music"
.fill music.size, music.getData(i)

// Print the music info while assembling
.print ""
.print "SID Data"
.print "--------"
.print "location=$"+toHexString(music.location)
.print "init=$"+toHexString(music.init)
.print "play=$"+toHexString(music.play)
.print "songs="+music.songs
.print "startSong="+music.startSong
.print "size=$"+toHexString(music.size)
.print "name="+music.name
.print "author="+music.author
.print "copyright="+music.copyright

.print ""
.print "Additional tech data"
.print "--------------------"
.print "header="+music.header
.print "header version="+music.version
.print "flags="+toBinaryString(music.flags)
.print "speed="+toBinaryString(music.speed)
.print "startpage="+music.startpage
.print "pagelength="+music.pagelength


* = $8000 "pic_screen"
    .import binary "Bohemian_better.kla", $1F40 + 2, 1000

koala_colors:
* = $5000 "koala colors for colorram" // temporary area
    .import binary "Bohemian_better.kla", $2328 + 2, 1000

* = $a000 "bitmap"
    .import binary "Bohemian_better.kla", 2, $1f3f