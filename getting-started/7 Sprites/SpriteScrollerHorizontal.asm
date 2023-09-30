#import "../../includes/vic_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/cia2_constants.inc"

.namespace Consts {
    .label RasterLineStart = $fb
    .label ScreenBase = $0000
    .label VicBankBase = $4000   
}

.var music = LoadSid("../E Custom Charset/retrospectful.sid")

* = music.location "Music" 
.fill music.size, music.getData(i)

BasicUpstart2(start)

*= $2000 "Code"

start:
    jsr setup

mainLoop:
    BusyWaitForNewScreen()
    jsr music.play

    //inc $d020                                   // uncomment to see duration of code

    // decrement all x coords from all 8 sprites by 1
    ldx #<VIC.SPRITE_7_X                        // last x coord, $d00e
!:  dec VIC.SPRITE_0_X,x
    dex                                         // decrement twice to go over y coord
    dex
    bpl !-

    // did first sprite just move out of screen?
    lda Data.spriteOrder                        // number of left most sprite
    asl                                         
    tax    
    lda VIC.SPRITE_0_X,x                        // n-th x coordinate
    cmp #$ff                                    // has it overflown?
    bne checkForXMsbUpdate                      // nope, just move on
    jsr moveLeftSpriteToRight

checkForXMsbUpdate:
    lda Data.spriteOrder + 5                    // only the 5th sprite from left has values +- 255 and switches MSB
    jsr updateSpriteXCoordMsbAfterDecrement

ycoords:
    jsr updateYCoords
    //dec $d020                                 // uncomment to see code timing
    
    jmp mainLoop                                // end of code, jump back to wait for new frame

clearScreen:
    MakeClearScreenFunction(Consts.VicBankBase, Consts.ScreenBase)

    // the leftmost sprite disappears in the left border and need to be moved to the
    // right part (also into the border). Additionally, we copy the char bitmap to the
    // sprite pointer address.
moveLeftSpriteToRight:
    // rotate the sprite order bytes
    ldx #0
    ldy Data.spriteOrder                        // read number of leftmost sprite
!:  lda Data.spriteOrder+1,x                    // move sprites one to the left
    sta Data.spriteOrder+0,x
    inx
    cpx #7
    bne !-
    sty Data.spriteOrder+7                      // put the sprite to the end
    tya
    asl
    tax                                         // calculate ycoord register for sprite
    lda #<(31 + 7 * 45 + 13)                    // + 13 to set distance to previous sprite 
    sta VIC.SPRITE_0_X,x

    lda #$0
    sec                                         // we know the rightmost sprite has x coord > 255
!:  rol                                         // so we need to rotate 1 into the correct bit position
    dey                                         // y register still has rightmost sprite number
    bpl !-

    ora VIC.SPRITE_MSB_X                        // set this byte
    sta VIC.SPRITE_MSB_X
    jsr copyChardataToSprite                    // sprite is not visible, copy new char data into it's data
    rts

copyChardataToSprite:

    ///
    /// Calculate sprite data target addresses
    ///

    lda #$0                                     // initialize with sprite data hi base address with to rol in carry
    sta spritePointer0Hi
    
    // sprites are aligned on 64 bytes, find the start address based on sprite number
    lda Data.spriteOrder+7                      // load number of last/rightmost sprite
    beq noShiftingRequired
    asl                                         // multiply with 64
    asl
    asl
    asl
    asl
    asl                                         // only last one can have carry set, max sprite number is 7
    rol spritePointer0Hi    

noShiftingRequired:
    sta spritePointer0Lo                        // start address for top left character target
    tax
    inx
    stx spritePointer1Lo                        // start address for top right character target
    clc
    adc #24                                     // 3x8 bytes from top left start
    sta spritePointer2Lo                        // start address for bottom left character target
    tax
    inx
    stx spritePointer3Lo                        // start address for bottom right character target

    lda #>spriteDataStart                       // need to merge bit with hi address of sprite segment
    ora spritePointer0Hi
    sta spritePointer0Hi                        // all addresses of single sprite are in the same page
    sta spritePointer1Hi                        // and will share the same hi address
    sta spritePointer2Hi
    sta spritePointer3Hi    

    ///
    /// Scroll text handing
    ///

.label scrollTextPointerLo = *+1
.label scrollTextPointerHi = *+2
loadNextScrollTextCharacter:
    lda scrollText
    bne incrementScrollPosition                 // end of scroll text?
    lda #<scrollText                            // yeah, so reset address
    sta scrollTextPointerLo
    lda #>scrollText
    sta scrollTextPointerHi
    jmp loadNextScrollTextCharacter             // try again. and yes, empty scroll text suck big time

incrementScrollPosition:
    inc scrollTextPointerLo                     // set scroll text position for next iteration.
    bne !+                                      // not using x indexing to allow scroll texts longer than 255 bytes.
    inc scrollTextPointerHi
!:

    ///
    /// Calculate charset data source addresses
    ///

    // We need to multiply character with 8 to get the offset to the
    // charset start. This gives us the first 8 bytes of the sprite.
    // accumulator holds current scrolltext character
    ldx #$0
    stx charsetPointer0Hi                       // clear hi address
    asl                                         // cannot have carry flag
    asl                                         // cannot have carry flag
    asl                                         // possibly have carry
    rol charsetPointer0Hi                       // set 1 on lo address overflow
    sta charsetPointer0Lo                       // all 4 characters will start on same lo address (64*8=512=$200)
    sta charsetPointer1Lo
    sta charsetPointer2Lo
    sta charsetPointer3Lo

    lda charsetPointer0Hi                       // we know the high address of the start, so we can generate the 
    ora #((>charset) | %0000)                   // four source addresses with or
    sta charsetPointer0Hi
    ora #((>charset) | %0010)
    sta charsetPointer1Hi
    and #%00000001                              // we are just using or, because we switch bits, the previous one needs to be erased.
    ora #((>charset) | %0100)                   // being smarter and using eor could combine and and or here. but hey, it's just cycles.
    sta charsetPointer2Hi
    ora #((>charset) | %0110)
    sta charsetPointer3Hi

    // A sprite has 3*21 bytes. The charset bytes need to be written every 3rd byte.
    // using y to index, it will not overflow with iny and not cross pages (although 
    // this would not matter too much here)

    // sprite memory layout:
    // 00=char1byte0, 01=char2byte0, 02=emtpy
    // 03=char1byte1, 04=char2byte1, 05=empty
    // ..
    // 45=char3byte7, 46=char4byte7, 47=empty
    // empty,      empty,   empty
    // empty,      empty,   empty  
    // empty,      empty,   empty            
    // empty,      empty,   empty      
    // empty,      empty,   empty      

    ldx #$7                                     // x index is used to read from charset, decreased by one each iteration
    ldy #$15                                    // y index is used to write to sprite where it has to be decreased by three each iteration
!:
.label charsetPointer0Lo = *+1
.label charsetPointer0Hi = *+2
    lda $dead,x
.label spritePointer0Lo = *+1
.label spritePointer0Hi = *+2
    sta $beef,y
.label charsetPointer1Lo = *+1
.label charsetPointer1Hi = *+2
    lda $dead,x
.label spritePointer1Lo = *+1
.label spritePointer1Hi = *+2
    sta $beef,y
.label charsetPointer2Lo = *+1
.label charsetPointer2Hi = *+2
    lda $dead,x
.label spritePointer2Lo = *+1
.label spritePointer2Hi = *+2
    sta $beef,y
.label charsetPointer3Lo = *+1
.label charsetPointer3Hi = *+2
    lda $dead,x
.label spritePointer3Lo = *+1
.label spritePointer3Hi = *+2
    sta $beef,y

    dey
    dey
    dey 

    dex
    bpl !-

    rts

setup:
    BusyWaitForNewScreen()
    jsr disableDisplay
    SetFullRamWithIoConfig()
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)    
    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_0000_MASK, VIC.SELECT_CHARSET_AT_1000_MASK)

    lda #0
    tax
    tay
    lda #music.startSong - 1
    jsr music.init

    // set border and background colors
    lda #VIC.black
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR
    
    // set sprite colors
    ldx #VIC.lblue
    stx VIC.SPRITE_MULTICOLOR_1
    ldx #VIC.blue
    stx VIC.SPRITE_MULTICOLOR_2
    ldx #VIC.cyan
    stx VIC.SPRITE_MULTICOLOR_3_0
    stx VIC.SPRITE_MULTICOLOR_3_1
    stx VIC.SPRITE_MULTICOLOR_3_2
    stx VIC.SPRITE_MULTICOLOR_3_3
    stx VIC.SPRITE_MULTICOLOR_3_4
    stx VIC.SPRITE_MULTICOLOR_3_5
    stx VIC.SPRITE_MULTICOLOR_3_6
    stx VIC.SPRITE_MULTICOLOR_3_7

    jsr clearScreen
    jsr set38ColumnMode

    // enable all sprites
    lda #$ff
    sta VIC.SPRITE_ENABLE                   

    // stretch all sprites
    lda #$ff
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y

    // set initial x coordindates
    // we display 7 sprites within visible screen and 
    // one sprite exactly starting in the border. All sprites
    // are separated with even space (2x8x2 == char width, (320 - 7*32) / 6)
    lda #(31 + 0 * 45)
    sta VIC.SPRITE_0_X
    lda #(31 + 1 * 45)
    sta VIC.SPRITE_1_X
    lda #(31 + 2 * 45)
    sta VIC.SPRITE_2_X
    lda #(31 + 3 * 45)
    sta VIC.SPRITE_3_X
    lda #(31 + 4 * 45)
    sta VIC.SPRITE_4_X
    lda #<(31 + 5 * 45)
    sta VIC.SPRITE_5_X
    lda #<(31 + 6 * 45)
    sta VIC.SPRITE_6_X
    lda #<(31 + 7 * 45)
    sta VIC.SPRITE_7_X

    // MSB for sprites are in $d010, bit 7 for sprite 7, ...
    // sprites on screen are 01234567
    lda #%11100000
    sta VIC.SPRITE_MSB_X

    // configure sprite pointers for all 8 sprites
    lda #(sprite0Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_0_OFFSET
    lda #(sprite1Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_1_OFFSET
    lda #(sprite2Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_2_OFFSET
    lda #(sprite3Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_3_OFFSET
    lda #(sprite4Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_4_OFFSET
    lda #(sprite5Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_5_OFFSET
    lda #(sprite6Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_6_OFFSET
    lda #(sprite7Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_7_OFFSET

    // set them all to multicolor mode
    ldx #$ff
    stx VIC.SPRITE_HIRES

    BusyWaitForNewScreen()
    jsr enableDisplay
    rts

disableDisplay:
    lda VIC.SCREEN_CONTROL_REG 
    and #VIC.ENABLE_SCREEN_CLEAR_MASK
    sta VIC.SCREEN_CONTROL_REG 
    rts

enableDisplay:
    lda VIC.SCREEN_CONTROL_REG 
    ora #VIC.ENABLE_SCREEN_MASK
    sta VIC.SCREEN_CONTROL_REG 
    rts

set38ColumnMode:
    lda VIC.CONTR_REG
    and #VIC.ENABLE_40_COLUMNS_CLEAR_MASK
    sta VIC.CONTR_REG
    rts

updateYCoords:
    ldx #$7  
!:  lda Data.spriteOrder,x                      // get number of sprite for x-th positiom
    asl
    tay
    iny 
.label SineTableSourceLo = *+1                  // make offset to $d000 out of sprite number
    lda sinetable,x                             // sine table is $ff+8(!) bytes long, use x to read backwards. 
    sta VIC.SPRITE_0_X,y                        // store y value to x-th sprite number
    dex
    bpl !-
    inc SineTableSourceLo                       // increment start index for next iteration

    rts

    // accumulator = sprite number
updateSpriteXCoordMsbAfterDecrement: {
    .var spriteMsbMasks = Data.spriteMsbMasks
    tay                                         // save number of strite for later in y register
    asl         
    tax
    lda VIC.SPRITE_0_X,x                        // load x coord
    cmp #$ff                                    // overflown?
    bne exit                                    // nope, go ahead with y coord updates
    lda spriteMsbMasks,y
    eor #$ff
    and VIC.SPRITE_MSB_X                        // use the 0 bit from above to clear x coord MSB
    sta VIC.SPRITE_MSB_X
exit:
    rts
}


.segment Default "Scroll text"
scrollText:
    .text "hey mr. curly, thanks for the c64 breadbin ... using it a lot! cheers to abyss-connection and all moonshiners."
    .byte $0

.align $100
.segment Default "Sine data"
sinetable:
    .fill $108, 100 + 50 * cos(toRadians((i * 360.0) / 64))

.segment Default "Data"

.namespace Data {
spriteOrder:                                    // buffer for the order of sprites
    .byte 0, 1, 2, 3, 4, 5, 6, 7                // storing first, increment and & with $7 would work as well. I am just lazy.

spriteMsbMasks:
    .byte %00000001
    .byte %00000010
    .byte %00000100
    .byte %00001000
    .byte %00010000
    .byte %00100000
    .byte %01000000
    .byte %10000000  
}

* = $5000 "Charset"
charset:
.import c64 "06.prg"                            // "c64" format to skip over 2 header bytes

* = $5800 "Sprite data"
.align $100                                     // set lo address to 0 to simplify sprite memory calculations
spriteDataStart:
sprite0Data:                                    // instead of aligning each sprite to 64 we
	.fill 3*21+3, $0                            // just fill 3 addtl. bytes with 0. Hey, it's just RAM!
sprite1Data:
	.fill 3*21+3, $0
sprite2Data:
	.fill 3*21+3, $0
sprite3Data:
	.fill 3*21+3, $0
sprite4Data:
	.fill 3*21+3, $0
sprite5Data:
	.fill 3*21+3, $0
sprite6Data:
	.fill 3*21+3, $0
sprite7Data:
    .fill 3*21+3, $0