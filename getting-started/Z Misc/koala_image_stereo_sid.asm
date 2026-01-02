#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/cia2_constants.inc"

BasicUpstart2(main)
.var music = LoadSid("Bohemian_Rhapsody.sid")

//#define SHOW_TIMING
#define ENABLE_MUSIC

* = $0900 "Code"
main:
    // --- setup music -------------------------
#if ENABLE_MUSIC
    lax #0
    tay
    lda #music.startSong - 1
    jsr music.init
#endif

    // --- setup graphics ----------------------
    jsr setupKoalaColors
    jsr setupGraphics

lp:  // --- main loop ---------------------------    
#if ENABLE_MUSIC
    BusyWaitForNewScreen()
#if SHOW_TIMING
    inc $d020
#endif
    jsr music.play
#if SHOW_TIMING
    dec $d020
#endif

!:  lda $d012
    cmp #$80
    bne !-

#if SHOW_TIMING
    inc $d020
#endif
    jsr music.play
#if SHOW_TIMING
    dec $d020
#endif

!:  lda $d012
    cmp #$f0
    bne !-

#if SHOW_TIMING
    inc $d020
#endif
    jsr music.play
#if SHOW_TIMING
    dec $d020
#endif

#endif
    jmp lp

setupGraphics:
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)    

    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    and #VIC.SELECT_BITMAP_CLEAR_MASK
    ora #VIC.SELECT_SCREENBUFFER_AT_1000_MASK
    ora #VIC.SELECT_BITMAP_AT_2000_MASK
    sta VIC.GRAPHICS_POINTER

    ldx #BLACK
    stx VIC.BORDER_COLOR
    stx VIC.SCREEN_COLOR

    lda #%00111011      
    sta $d011           
    lda #%00011000      
    sta $d016           
                                 
    rts

setupKoalaColors:
    ldx #0
!:
    lda koala_colors + $000,x
    sta $d800 + $000,x
    lda koala_colors + $100,x
    sta $d800 + $100,x
    lda koala_colors + $200,x
    sta $d800 + $200,x
    lda koala_colors+$02e8,x
    sta $d800 + $2e8,x
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


* = $5000 "pic_screen"
    .import binary "Bohemian_better.kla", 8000 + 2, 1000

* = $9000 "koala colors for colorram" // temporary area
koala_colors:
    .import binary "Bohemian_better.kla", 9000 + 2, 1000    
* = $6000 "bitmap"
    .import binary "Bohemian_better.kla", 2, 8000