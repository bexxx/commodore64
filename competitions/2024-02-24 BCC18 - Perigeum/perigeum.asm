#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/cia2_constants.inc"

.namespace BitmapConfiguration {
    .label RasterInterruptLine  = 48
    .label VICBankNumber        = 2                             
    .label VICScreenOffset      = $0000
    .label VICScreenOffsetMask  = VIC.SELECT_CHARSET_AT_0000_MASK
    .label VICBitmapOffsetMask  = VIC.SELECT_BITMAP_AT_2000_MASK
    .label VICBitmapOffset      = $2000
    .label VICBaseAddress       = VICBankNumber * $4000
    .label VICScreenBuffer      = VICBaseAddress + VICScreenOffset
    .label VICBitmapAddress     = VICBaseAddress + VICBitmapOffset   
}

.namespace ScrollerConfiguration {
    .label RasterInterruptLine          = 146                        // raster line to start with dycp irq    
    .label VICBankNumber                = 1
    .label ScrollerWidth                = 40                         // how wide is the scroller (in characters)
    .label ScreenMemoryOffset1          = $0000
    .label ScreenMemoryOffset2          = $0400
    .label ScreenMemoryBase1            = VICBankNumber * $4000 + ScreenMemoryOffset1   // base address of screen ram, buffer 1
    .label ScreenMemoryBase2            = VICBankNumber * $4000 + ScreenMemoryOffset2   // base address of screen ram, buffer 2
    .label CharsetBase1                 = $5000                      // base address of charset, buffer 1
    .label CharsetBase2                 = $5800                      // base address of charset, buffer 1
    .label SelectScreenbuffer1Mask      = VIC.SELECT_SCREENBUFFER_AT_0000_MASK
    .label SelectScreenbuffer2Mask      = VIC.SELECT_SCREENBUFFER_AT_0400_MASK
    .label SelectCharsetBuffer1Mask     = VIC.SELECT_CHARSET_AT_1000_MASK
    .label SelectCharsetBuffer2Mask     = VIC.SELECT_CHARSET_AT_1800_MASK
    .label ScreenBufferPointer          = Zeropage.Unused_FB        // ZP pointer, used write to screen ram
    .label SourceCharsetPointer         = Zeropage.Unused_FD        // ZP pointer, used to read from charset data
    .label TargetCharsetPointer         = Zeropage.Unused_FB        // ZP pointer, used to write to charset data
    .label CurrentChar                  = Zeropage.Unused_02        // current char from scroll text
}

.namespace WidescreenConfiguration {
    .label RasterInterruptLine = 250
}

.namespace StarfieldConfiguration {
    .label RasterInterruptLine = 250
}

.var music = LoadSid("perigeum.sid")

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

BasicUpstart2(main)

* = $1C00 "Code"
main:
    sei

    BusyWaitForNewScreen()

    // crappy fade out, not raster synched. yeah I know I should do better ...
    lda VIC.BORDER_COLOR
    and #$f
    tay
    lda fadeouttable,x
    sta VIC.BORDER_COLOR

    lda VIC.SCREEN_COLOR
    and #$f
    tay
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
    bne main

    jsr disableDisplay

    // make run from start nearly the same each time.
    BusyWaitForNewScreen()

    // --- setup music -------------------------
    lax #0
    tay
    lda #music.startSong - 1
    jsr music.init

    // --- setup graphics ----------------------
    jsr clearScreen1
    jsr clearScreen2
    jsr setupKoalaColors
    jsr setupBackgroundColors

    lda #VIC.black
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    // clear the @ character which is used around the 2 dycp characters to clear the screen
    lda #$0
    ldx #7
!:
    sta ScrollerConfiguration.CharsetBase1,x
    sta ScrollerConfiguration.CharsetBase2,x
    dex
    bpl !-

    // --- setup scroll text -------------------
    ldx #ScrollerConfiguration.ScrollerWidth - 1
    lda #' '
!:  sta scrollTextBuffer,x
    dex
    bpl !-

    // --- setup sprites -----------------------
    lda #VIC.SPRITE_ALL_ENABLE_MASK
    sta VIC.SPRITE_ENABLE
    
    lda #$00  
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y
    sta VIC.SPRITE_BG_PRIORITY

    ldx #$00
generateSpriteData:    
    lda #$00
    sta $6000,x
    inx
    bne generateSpriteData
    lda #$01                                    // create a dot for the sprite starfield
    sta $6000

    ldx #$00
setsprs:
    lda #$80                                    // Sprite object data from
    sta ScrollerConfiguration.ScreenMemoryBase1 + VIC.SPRITE_POINTER_0_OFFSET,x
    sta ScrollerConfiguration.ScreenMemoryBase2 + VIC.SPRITE_POINTER_0_OFFSET,x
    lda #$01                                    // All sprites are white
    sta VIC.SPRITE_MULTICOLOR_3_0,x
    inx
    cpx #$08                                    // Do the sprite creation 8 times
    bne setsprs
			
    ldx #$f
positions:	
    lda postable,x                              // Read position table
    sta starpos,x                               // create data memory for current sprite position
    dex
    bpl positions

    // write y pos once
    ldx #$f
!:
    lda starpos,x                               // Read star position buffer (odd number values)
    sta VIC.SPRITE_0_X,x                        // Write memory to the actual sprite y position
    dex
    dex
    bpl !-

    lda #<irqBitmap                             // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>irqBitmap                             // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #BitmapConfiguration.RasterInterruptLine// load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    // GO!
    jsr enableDisplay

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    cli

waitForever:
    jmp waitForever

fadeouttable:
    .byte VIC.black, VIC.lgreen, VIC.dgrey, VIC.green, VIC.red, VIC.lred, VIC.brown, VIC.lgrey, VIC.purple, VIC.black, VIC.grey, VIC.blue, VIC.lblue, VIC.yellow, VIC.orange, VIC.cyan

irqWidescreenBar:
    lda #<irqBitmap                             // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>irqBitmap                             // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #BitmapConfiguration.RasterInterruptLine// load desired raster line
    nop
    ldx #VIC.dgrey
    stx VIC.BORDER_COLOR
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // ack interrupt to enable next one       
    sta VIC.INTERRUPT_EVENT    

    ReturnFromInterrupt()

irqBitmap:
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK2_MASK)    

    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    and #VIC.SELECT_BITMAP_CLEAR_MASK
    ldx #VIC.black
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

    lda #<irqDycp                                   // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo      // store to RAM interrupt handler
    lda #>irqDycp                                   // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi      // store to RAM interrupt handler

    lda #ScrollerConfiguration.RasterInterruptLine  // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG                  // low byte of raster line
    
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK           // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                         // store back to enable raster interrupt

    ReturnFromInterrupt()

irqDycp:
    // fix crap between logo and scroller
    nop
    nop
    nop

    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)    

    lda VIC.SCREEN_CONTROL_REG
    and #VIC.ENABLE_BITMAP_MODE_CLEAR_MASK
    sta VIC.SCREEN_CONTROL_REG

    // set 38 column mode to hide partial chars at the sides
    lda VIC.CONTR_REG
    and #VIC.ENABLE_40_COLUMNS_CLEAR_MASK
    sta VIC.CONTR_REG

    // configure VIC to use new charset and screen location
    // (use the buffers that were written before)
    ldy currentTargetBuffer
    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora charsetPointerMasks,y
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    ora screenramPointerMasks,y
    sta VIC.GRAPHICS_POINTER

    // set x scroll to current value
    lda VIC.CONTR_REG         
    and #%11111000                              
    and #VIC.ENABLE_MULTICOLOR_CLEAR_MASK                      
    ora currentXScrollOffset                       
    sta VIC.CONTR_REG      
    
    lda #<irqWidescreenBar                              // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo          // store to RAM interrupt handler
    lda #>irqWidescreenBar                              // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi          // store to RAM interrupt handler

    lda #WidescreenConfiguration.RasterInterruptLine    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG                      // low byte of raster line

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK               // ack interrupt to enable next one       
    sta VIC.INTERRUPT_EVENT    
    cli
    
    dec currentXScrollOffset                            // determine next x scroll offset
    bpl !+                                              // if less then 0, we need to reset to 7
    lda #$7
    sta currentXScrollOffset   
    jsr scrollOneCharacter

!:
    // create two buffers with the positional data.
    // yposOffsetWithinChar will contain all offsets 0-7 within the first of the two chars per column
    // yposOffsetInFullChars will contain the offset in char rows for the first of two characters per column
    ldx #ScrollerConfiguration.ScrollerWidth - 1
    ldy currentSineIndex1
createYPositionData:
    lda sinetable,y
    and #%0000111
    sta yposOffsetWithinChar,x                  // lower 3 bits as offset into the character data
    lda sinetable,y
    lsr
    lsr
    lsr
    sta yposOffsetInFullChars,x                 // y offset in full character counts (divided by 8)
    iny                                         // advance sine index
    dex
    bpl createYPositionData

    // fix up code to write to current screen ram buffer
    ldy currentTargetBuffer
    lda screenRowOffsetsTableLo,y
    sta screenPointerLo
    lda screenRowOffsetsTableHi,y
    sta screenPointerHi

    // draw the two characters in a column based on the offset in rows (yposOffsetInFullChars)
    lda #(ScrollerConfiguration.ScrollerWidth * 2) | $80    // we use 2 characters per column, starting at 1 AND the upper 128 chars of the charset
    sta ScrollerConfiguration.CurrentChar
    ldx #ScrollerConfiguration.ScrollerWidth - 1            // iterate through all columns (x coords)
drawCharacters:
    ldy yposOffsetInFullChars,x                 // get row offset for current column
    txa                                         // store current column in accu
    clc                     
    adc screenRowOffsetsLo,y                    // add x (in rows) to y offset
    sta ScrollerConfiguration.ScreenBufferPointer
.label screenPointerLo = *+1
.label screenPointerHi = *+2
    lda $dead,y
    sta ScrollerConfiguration.ScreenBufferPointer+1
    bcc !+
    inc ScrollerConfiguration.ScreenBufferPointer+1
!:
    lda #'@'                                    // write @ as clearning character above and below two characters of this column
    ldy #(0 * 40)                               // above column
    sta (ScrollerConfiguration.ScreenBufferPointer),y
    ldy #(3 * 40)                               // below column
    sta (ScrollerConfiguration.ScreenBufferPointer),y
    lda ScrollerConfiguration.CurrentChar
    ldy #(2 * 40)                               // second row of column
    sta (ScrollerConfiguration.ScreenBufferPointer),y
    dec ScrollerConfiguration.CurrentChar
    lda ScrollerConfiguration.CurrentChar
    ldy #(1 * 40)                               // first row of column
    sta (ScrollerConfiguration.ScreenBufferPointer),y
    dec ScrollerConfiguration.CurrentChar
    dex
    bpl drawCharacters

    // clear charset data for the characters used in the columns
    ldy currentTargetBuffer
    lda clearCharsetLo,y
    sta clearCharsetPointerLo
    lda clearCharsetHi,y
    sta clearCharsetPointerHi
.label clearCharsetPointerLo = *+1
.label clearCharsetPointerHi = *+2
    jsr $dead

    ldy currentTargetBuffer
    lda charsetOffsetRowsTableLo,y
    sta TargetCharsetAddressLo
    lda charsetOffsetRowsTableHi,y
    sta TargetCharsetAddressHi

    // now copy the character data into the charset based on the offset within the first of the 
    // two characters used in the column
    ldx #ScrollerConfiguration.ScrollerWidth - 1
copyScrollCharacterDataIntoColumnCharacters:
    lda scrollTextBuffer,x                      // load scroll text character for this x position
    asl                                         // multiply with 8 to get source offset
    asl                                         // if we only use 32 characters max in scroll text
    asl
    sta ScrollerConfiguration.SourceCharsetPointer      // store into ZP pointer
    lda #>ScrollerConfiguration.CharsetBase1                           
    sta ScrollerConfiguration.SourceCharsetPointer + 1                
    bcc !+
    inc ScrollerConfiguration.SourceCharsetPointer + 1  // fix hi address for chars > 32
    clc
!:
    lda yposOffsetWithinChar,x                          // get y offset within character
    adc charsetOffsetRowsLo,x                           // add to the offset of the character
    sta ScrollerConfiguration.TargetCharsetPointer      // store in ZP pointer (lo)

.label TargetCharsetAddressLo = *+1
.label TargetCharsetAddressHi = *+2
    lda $dead,x                                         // here we need to set hi part of address as well
    sta ScrollerConfiguration.TargetCharsetPointer + 1  // store in ZP pointer (hi)

    ldy #7          
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey            
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y
    dey
    lda (ScrollerConfiguration.SourceCharsetPointer),y
    sta (ScrollerConfiguration.TargetCharsetPointer),y

    dex
    bpl copyScrollCharacterDataIntoColumnCharacters

setupNextIterationValues:
    inc currentSineIndex1                       // determine next sine value index

    lda currentTargetBuffer
    eor #$1  // 00 -> 01, 01 -> 00
    sta currentTargetBuffer

exitDycp:  
    // do everything that needs to happen once per frame here

    // play sic
    jsr music.play

    // update sprite pointers, they get corrupted by dycp ...
    lda #$80
    ldx #8
!:	sta ScrollerConfiguration.ScreenMemoryBase1 + VIC.SPRITE_POINTER_0_OFFSET,x
    sta ScrollerConfiguration.ScreenMemoryBase2 + VIC.SPRITE_POINTER_0_OFFSET,x
    dex
    bpl !-

    // update sprite positions
    ldx #$e
xpdloop:
    lda starpos+0,x //Read virtual memory from starpos (odd number values)
    asl
    rol $d010 //increase the screen limit for sprite x position
    sta $d000,x //Write memory to the actual sprite x position
    dex
    dex
    bpl xpdloop
			
    ldx #$e
moveloop:
    lda starpos+0,x //Read from data table (starpos)
    clc
    adc starspeed+0,x
    sta starpos+0,x
    dex // Add 2 to each value of the loop
    dex //
    bpl moveloop

    jmp $ea31

scrollOneCharacter:
    ldx #0
!:
    lda scrollTextBuffer+1,x
    sta scrollTextBuffer+0,x
    inx
    cpx #ScrollerConfiguration.ScrollerWidth - 1 
    bne !-
    
.label scrollTextPointerLo = *+1
.label scrollTextPointerHi = *+2
!:  lda scrollText
    bne !+
    lda #<scrollText
    sta scrollTextPointerLo
    lda #>scrollText
    sta scrollTextPointerHi
    jmp !-
!:  sta scrollTextBuffer,x
    inc scrollTextPointerLo
    bne !+
    inc scrollTextPointerHi

!:  rts

clearScreen1:
MakeClearScreenFunction(ScrollerConfiguration.VICBankNumber, ScrollerConfiguration.ScreenMemoryOffset1)

clearScreen2:
MakeClearScreenFunction(ScrollerConfiguration.VICBankNumber, ScrollerConfiguration.ScreenMemoryOffset2)

clearCharset1:
    lda #$0
    ldx #(ScrollerConfiguration.ScrollerWidth * 2) - 1
!:
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 0 * 80),x    
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 1 * 80),x    // + 0-8 to unroll this loop and overwrite all 8 bytes of a character
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 2 * 80),x    // + $0400 to target upper 128 characters of charset (| $80)
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 3 * 80),x
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 4 * 80),x
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 5 * 80),x
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 6 * 80),x
    sta (ScrollerConfiguration.CharsetBase1 + $0400  + 7 * 80),x
    dex
    bpl !-
    rts

clearCharset2:
    lda #$0
    ldx #(ScrollerConfiguration.ScrollerWidth * 2) - 1
!:
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 0 * 80),x    
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 1 * 80),x    // + 0-8 to unroll this loop and overwrite all 8 bytes of a character
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 2 * 80),x    // + $0400 to target upper 128 characters of charset (| $80)
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 3 * 80),x
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 4 * 80),x
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 5 * 80),x
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 6 * 80),x
    sta (ScrollerConfiguration.CharsetBase2 + $0400 + 7 * 80),x
    dex
    bpl !-
    rts

setupBackgroundColors:
    lda #VIC.white
    ldx #$0
!:  sta $da00,x
    sta $db00,x
    dex
    bne !-

    .for (var i=14;i<25;i++) {
        lda #VIC.dgrey
        sta $d800+0+i*40
        lda #VIC.grey
        sta $d800+1+i*40
        lda #VIC.lgrey
        sta $d800+2+i*40
    }

    .for (var i=14;i<25;i++) {
        lda #VIC.lgrey
        sta $d800+36+i*40
        lda #VIC.grey
        sta $d800+37+i*40
        lda #VIC.dgrey
        sta $d800+38+i*40
    }
    rts

#import "../../../commodore64/includes/common_gfx_functions.asm"

currentXScrollOffset:
    .byte $07
currentSineIndex1:
    .byte $00
currentSineIndex2:
    .byte $04
scrollTextBuffer:
    .fill ScrollerConfiguration.ScrollerWidth, $0
scrollText:
    .text "              hello beautiful people at bcc#18! we hope all is well with you all. "
    .text "moonshine's 2 year anniversary is soon to come. we had a music collection planned but "
    .text "sadly only like 1 tune and the intro tune you are hearing right now was made, so we scrapped it.      "
    .text "demosic on the keys. huh, 2 years, it's been a little while eh? i still remember back when me and some "
    .text "others first started this group back in early 2022, and sooner or later, it turned into what it is now thanks "
    .text " to everyone's talent and motivation, it's been a fun ride these past 2 years. i'm genuinely proud of everyone "
    .text "in the group. i hope someday we can make some cool demos together! "
    .text "     hepterida on the keys. moonshine is still home of real borning stars as an open platform for those whose "
    .text "desire to learn or apply the knowledge tuning it into the fun. fun for everyone. "
    .text "     bexxx here: moonshine embraced me when i barely was able to code a scroller and supported me with everything "
    .text "i tried out. hepterida even taught me petscii as a gateway drug to graphics! without all of your support i would not write these lines here. "
    .text "    this catchy sid tune was composed by demosic, the wonderful graphic was contributed by hepterida and the code was wrangled by bexxx. "

    .text "    moonshine's greetings fly out to: seffren, abyss-connection, onslaught, frequency (frq)"

    .text "    demosic sends greetings to: sidwave, jammer, shine, seffren, dr.j, mythus, nomistake, thunder.bird, moroz1999, n1k-o, pator and the whole moonshine crew for being so talented! "
    .text "    personal greetings of bexxx: fieser wolf, mr. curly, ldx#40, higgie, el jefe, copass, logan, mcm, dandee, dyme, proton/fig, sonic, shine, deekay, kb, "
    .text "seffren, milinator, logiker, ccd, crucial, panito, fraegle, greenfrog and everybody at moonshine!"
    .text "    hepterida sends greetings to: bexxx, ulrick, demosic, seffren, shine, strangerhmd, tygrys, pator, "
    .text " lamer pinky, omega, busy, aki and all those kind people behind parties for different platforms. (speccy forever!)"

    .text "    mic drop."

    .byte $00 

screenramPointerMasks:
    .byte ScrollerConfiguration.SelectScreenbuffer2Mask
    .byte ScrollerConfiguration.SelectScreenbuffer1Mask
charsetPointerMasks:
    .byte ScrollerConfiguration.SelectCharsetBuffer2Mask
    .byte ScrollerConfiguration.SelectCharsetBuffer1Mask
currentTargetBuffer:
    .byte $00

.align $100
sinetable:
    .import binary "scroller_wave.bin"

.align $100
screenRowOffsetsLo:
    .fill 25, <(ScrollerConfiguration.ScreenMemoryBase1 + i * 40)
screenRowOffsets1Hi:
    .fill 25, >(ScrollerConfiguration.ScreenMemoryBase1 + i * 40)
screenRowOffsets2Hi:
    .fill 25, >(ScrollerConfiguration.ScreenMemoryBase2 + i * 40)

screenRowOffsetsTableLo:
    .byte <screenRowOffsets1Hi, <screenRowOffsets2Hi
screenRowOffsetsTableHi:
    .byte >screenRowOffsets1Hi, >screenRowOffsets2Hi

clearCharsetLo:
    .byte <clearCharset1, <clearCharset2
clearCharsetHi:
    .byte >clearCharset1, >clearCharset2

yposOffsetWithinChar:
    .fill ScrollerConfiguration.ScrollerWidth, $0
yposOffsetInFullChars:
    .fill ScrollerConfiguration.ScrollerWidth, $0
charsetOffsetRowsLo:
    .fill ScrollerConfiguration.ScrollerWidth, i * 16 + 8

charsetOffsetRowsTableLo:
    .byte <charsetOffsetRows1Hi, <charsetOffsetRows2Hi
charsetOffsetRowsTableHi:
    .byte >charsetOffsetRows1Hi, >charsetOffsetRows2Hi

.align $100
charsetOffsetRows1Hi:
    .fill ScrollerConfiguration.ScrollerWidth, >(ScrollerConfiguration.CharsetBase1 + $0400 + i * 16 + 8)
charsetOffsetRows2Hi:
    .fill ScrollerConfiguration.ScrollerWidth, >(ScrollerConfiguration.CharsetBase2 + $0400 + i * 16 + 8)

postable:	
    .byte $13,163 
    .byte $01,171
    .byte $26,179
    .byte $17,185
    .byte $09,198
    .byte $04,203
    .byte $26,210
    .byte $05,$f6
			
starspeed:
    .byte $05,$00 // Important. Remember that Y should always be zero. X is changable for
    .byte $03,$00 // varied speeds of the moving stars. :)
    .byte $01,$00
    .byte $04,$00
    .byte $03,$00
    .byte $01,$00
    .byte $07,$00
    .byte $02,$00

starpos:
    .fill $10, $0

setupKoalaColors:
    ldx #$00
!:
    lda $3000 + $000,x
    sta $d800 + $000,x
    lda $3000 + $100,x
    sta $d800 + $100,x
    dex
    bne !-

    rts

    // load font to the lower half of the charset
* = ScrollerConfiguration.CharsetBase1 "Charset"
    .import c64 "cuddly.64c", 0, 128 * 8

* = $8000 "pic_screen"
    .import binary "moonshine_intro_final.kla", $1F40 + 2, 1000

* = $3000 "koala colors for colorram" // temporary area
    .import binary "moonshine_intro_final.kla", $2328 + 2, 1000

* = $a000 "bitmap"
    .import binary "moonshine_intro_final.kla", 2, $1f3f

