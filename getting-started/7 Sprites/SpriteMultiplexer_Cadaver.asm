// Sprite multiplexer isolated from Cadaver's game Hessian, available at:
// https://github.com/cadaver/hessian
// Check files raster.s and screen.s for the original code
//
// The code has been minimally changed to work with kickassembler
// and added some minor code style modernization as well as extensive comments
// to understand the code better.
// Cadaver has put a lot of thinking into the optimization of the code, I tried
// to document all tricks as comments and the general flow of the code into the beginning.

// The main flow of the code is separated into two large parts:
// 1. The irq driven changes of sprite positions, colors and pointers. Here the first part
//    sets up the first 8 sprites (this is safe, because it starts before the top border ends, raster line $16).
//    Then the rest of the sprites are either updated in subsequent irqs, or in a busy loop if there
//    is not enough time to set up and start irqs (less than 3 raster lines to the next irq)
// 2. In parallel, the main loop is responsible for sorting the arrays and preparing the irq raster line
//    numbers for the irqs. This work can be interrupted by the irqs, because the code uses double buffering to not
//    write the same bytes as the irqs read.
//
// There is some synchronization between these two parts to update the irq code to use the other half of the buffer when
// the main loop is done modifying the other part of the data.
//
// The sprite irq starts to set the first batch of max 8 sprites starting on raster line $16 and is done before the screen begins at $32.
// The code to sort the sprites starts at $100 (this is in the lower border) with sorting. The copying of the updated sprite data happends
// when the irq set the start signal in the beginnig (roughly $17, again outside of the screen).

#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "zpallocator.asm"
#import "../../includes/sprite_helpers.asm"
#import "page_warn.asm"

.eval zpAllocatorInit(List().add(hardwiredPortRegisters))

#define TIMING_IRQ
#define TIMING_SORT
#define TIMING_COPY

.namespace Configuration {
    .label EstimatedIrqExecutionRasterLines = 12
    .label MIN_SPRITE_Y = 34                            // this is the minimum y coordinate for a sprite to be visible
    .label TopSpriteIrqRasteLine = MIN_SPRITE_Y - EstimatedIrqExecutionRasterLines
    .label MAX_SPRITES = 24
    .label MAX_SPRITE_Y = 250

    .label ScreenRamAddress = $0400

    // those three ZP registers are used to store and restore the current register values in the sprite IRQ
    .label spriteIrqAccuSaveZp = allocateSpecificZpByte($2, "spriteIrqAccuSaveZp")
    .label spriteIrqXRegisterSaveZp = allocateSpecificZpByte($3, "spriteIrqXRegisterSaveZp")
    .label spriteIrqYRegisterSaveZp = allocateSpecificZpByte($4, "spriteIrqYRegisterSaveZp")

    // this is either 0 or MAX_SPRITES. It's used to store the start index into the sorted
    // double buffers (see sorted* buffers for x,y,pointers and colors)
    .label firstSortSprZP = allocateZpByte("firstSortSprZP")

    // shared memory location to synchronize between irq and main loop code
    .label newFrame = allocateZpByte("newFrame")

    // this is a pointer into the sprite data to enable only swapping two bytes when
    // swapping sprites during sort
    .label spriteOrder = allocateZpBytes(MAX_SPRITES + 1, "spriteOrder")

    // Sprite coordinates are used a lot during sortings, so they are stored in the zero page to
    // speed up access.
    // These values need to be managed by the animation/movement code.
    .label spriteY = allocateZpBytes(MAX_SPRITES + 1, "spriteY")    // + 1 byte as end marker in the loop
    .label spriteXLo = allocateZpBytes(MAX_SPRITES, "spriteXLo")
    .label spriteXHi = allocateZpBytes(MAX_SPRITES, "spriteXHi")

#if TIMING_IRQ
    .label savedTimingD020 = allocateZpByte("savedTimingD020")
    .label IrqTimingColor = RED
#endif
#if TIMING_SORT
    .label savedSortD020 = allocateZpByte("savedSortD020")
    .label IrqSortColor = WHITE
#endif
#if TIMING_COPY
    .label savedCopyD020 = allocateZpByte("savedCopyD020")
    .label IrqCopyColor = GREEN
#endif
}

BasicUpstart2(main)

main:
    jsr initSpriteMultiplexerData           // initialize datastructures
    jsr initSprites                         // set up initial coordinates
    jsr initInterrupts                      // configure memory and interrupts
    lda #$ff                                // signal wait to the main loop initially
    sta Configuration.newFrame

mainLoop:
    jsr mainSpriteLoop.UpdateFrame          // main loop just sorts and copies the sprite data
    jmp mainLoop

//
// Initialize the sprite multiplexing system data structures
// Call once only 
//
initSpriteMultiplexerData: {
    .var tempBitmaskZp = allocateZpByte("tempBitmaskZp")

    lda #$0                                 // set index to the first half of the double buffer
    sta Configuration.firstSortSprZP

    ldx #Configuration.MAX_SPRITES
    lda #$01
    sta tempBitmaskZp
spriteLoop:
    txa
    sta Configuration.spriteOrder,x

    lda #$ff
    sta Configuration.spriteY,x             // init all Y coordinates with $ff to skip them by default

    cpx #Configuration.MAX_SPRITES          // we initialize an additional byte at the end of the spriteOrder and spriteY array
                                            // to have a least one sprite with the y coordinate $ff to have at minimum one end marker
    beq bitmaskStillOk                      // for this spare sprite at the end we do not want to set bitmasks, so skip for this iteration

    lda tempBitmaskZp                                   // get current bit mask
    sta spriteOrTable,x                                 // store on lower half of the double buffer
    sta spriteOrTable + Configuration.MAX_SPRITES,x     // store on upper half of the double buffer

    eor #$ff                                            // and mask is the inverse of or mask, so simply eor $ff it
    sta spriteAndTable,x                                // store on lower half of the double buffer
    sta spriteAndTable + Configuration.MAX_SPRITES,x    // store on upper half of the double buffer

    asl tempBitmaskZp                       // shift bitmask one bit to the left
    bne bitmaskStillOk                      // this is the negated bitmask, so there will be a 1, not 0 as stored in tempBitmaskZp

    lda #$01                                // after 8 sprites, restart with bit 0 again
    sta tempBitmaskZp

bitmaskStillOk:
    dex
    bpl spriteLoop

    rts

    .eval deallocateZpByte(tempBitmaskZp)
}

//
// Initialize the sprite data itself, like expansion, (multi)colors, bg priority
//
initSprites: {
    lda #$0
    lda $d011
    and #%01111111
    sta $d011
    lda #$0
    sta $d01b                               // Sprites on top of BG
    sta $d01d                               // Sprite X-expand off
    sta $d017                               // Sprite Y-expand off
    sta $d026                               // Set sprite multicolors
    lda #$0a
    sta $d025
    lda #$00                                // set all sprites to hires
    sta $d01c

    lda $ff
    ldx #$10
!spriteLoop:
    dex
    dex
    sta $d001,x                             // == $ff, Set all sprites on & to the bottom
    bne !spriteLoop-
    sta $d015                               // all sprites on and to the bottom
    jsr WaitBottom                          // (some C64's need to "warm up" sprites
                                            // to avoid one frame flash when they're
    stx $d015                               // actually used for the first time)

    // initialize sprite pointers and positions with demo data

    // place sprites on x coords
    ldx #Configuration.MAX_SPRITES - 1
    lda #254
!spriteLoop:
    sta Configuration.spriteXLo,x
    sec
    sbc #9
    dex
    bpl !spriteLoop-

    // no msb / coord >= $100 for now
    ldx #Configuration.MAX_SPRITES - 1
    lda #0
!spriteLoop:
    sta Configuration.spriteXHi,x
    dex
    bpl !spriteLoop-

    // set sprites y coords
    ldx #Configuration.MAX_SPRITES - 1
    lda #225
!spriteLoop:
    sta Configuration.spriteY,x
    sec
    sbc #7
    dex
    bpl !spriteLoop-

    // set sprite pointers
    ldx #Configuration.MAX_SPRITES - 1
    ldy #(spriteData24  / 64)
!spriteLoop:
    tya
    sta spritePointers,x
    dey
    dex
    bpl !spriteLoop-

    // set sprite colors
    ldx #Configuration.MAX_SPRITES - 1
    ldy #0
!spriteLoop:
    tya
    and #$7
    cmp #BLUE
    bne !+
    iny
    tya
!:
    sta spriteColors,x
    iny
    dex
    bpl !spriteLoop-

    rts
}

//
// Disable CIA and enable raster irqs and set handler address
//
initInterrupts:
    sei

    // disable kernal rom
    lda #$35
    sta $01

    // set up top raster irq
    lda #<topSpriteIrq
    sta $fffe
    lda #>topSpriteIrq
    sta $ffff
    lda #Configuration.TopSpriteIrqRasteLine
    sta $d012
    lda #$01
    sta $d01a
    lsr $d019

    // disable cia irqs
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs
    lda CIA1.INTERRUPT_CONTROL_REG              // ACK CIA 1 interrupts in case there are pending ones
    lda CIA2.INTERRUPT_CONTROL_REG              // ACK CIA 2 interrupts in case there are pending ones

    cli

    rts


    ///
    /// Irq handler for the initial sprites on top of the screen.
    ///
.align $100
topSpriteIrq: {
    // save registers
    sta Configuration.spriteIrqAccuSaveZp
    stx Configuration.spriteIrqXRegisterSaveZp
    sty Configuration.spriteIrqYRegisterSaveZp

#if TIMING_IRQ
    lda $d020
    and #$f
    sta Configuration.savedTimingD020

    lda #Configuration.IrqTimingColor
    sta $d020
#endif 

    ldx #$00                                // Reset frame update
    stx Configuration.newFrame

    lda d015Value: #0                       // initially disable all sprites
    sta $d015
    beq noSprites

    lda #<continuationSpriteIrq             // there are more sprites, handle them in the next raster irq
    sta $fffe
    lda #>continuationSpriteIrq
    sta $ffff

    jmp continuationSpriteIrq.displaySprites    // jump straight to the sprite display code

noSprites:
    lsr $d019                               // acknowledge raster IRQ                

#if TIMING_IRQ
    lda Configuration.savedTimingD020
    sta $d020
#endif 

    ldy Configuration.spriteIrqYRegisterSaveZp
    ldx Configuration.spriteIrqXRegisterSaveZp
    lda Configuration.spriteIrqAccuSaveZp

    rti
}

    // after the initial sprite irq, this one will be used to handle the next batch of sprites
    // which could be used (raster line and number of sprites vary, will be determined in the updateFrame function)
.align $100
continuationSpriteIrq: {
    sta Configuration.spriteIrqAccuSaveZp
    stx Configuration.spriteIrqXRegisterSaveZp
    sty Configuration.spriteIrqYRegisterSaveZp

#if TIMING_IRQ
    lda #Configuration.IrqTimingColor
    sta $d020
#endif 


    // if there is no time to set up the next sprite irq, we need to do it in a busy loop
    // this will be the jump target
continuationSpriteIrqDirect:
Irq2_SprIndex:
    ldx spriteIndex: #$00                   // get the sprite index for this irq


    // to keep track of the hw sprite that will be used next, this jump will be updated
    // with the lo-address of that part of code that will write the data
    // (labels: sprite0Pointer-sprite7Pointer, all in a single page to just require lo address update)
    // can't do a bpl here, because we need to jump more than 128 bytes away. 
Irq2_SprJump:
    jmp spriteJumpAddressLo: sprite0Positions       // Go through the first sprite IRQ immediately

displaySprites:
    ldx firstSortedSpriteIndex: #$0         

sprite0Positions:
    .eval startPageCheck()
    lda sortedSpritesY,x
    sta VIC.SPRITE_7_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_7_X
    sty $d010
sprite0Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_7_OFFSET
sprite0Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_7
    bmi !done+
    inx

sprite1Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_6_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_6_X
    sty $d010
sprite1Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_6_OFFSET
sprite1Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_6
    bmi !done+
    inx

sprite2Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_5_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_5_X
    sty $d010
sprite2Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_5_OFFSET
sprite2Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_5
    bmi !done+
    inx

sprite3Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_4_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_4_X
    sty $d010
sprite3Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_4_OFFSET
sprite3Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_4
    bpl !+

!done:                                      // the real done label is > 128 bytes away from the previous bmi commands
    jmp !done+                              // so this one need to jump to the final one instead
!:
    inx

sprite4Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_3_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_3_X
    sty $d010
sprite4Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_3_OFFSET
sprite4Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_3
    bmi !done+
    inx

sprite5Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_2_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_2_X
    sty $d010
sprite5Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_2_OFFSET
sprite5Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_2
    bmi !done+
    inx

sprite6Positions:
    lda sortedSpritesY,x
    sta VIC.SPRITE_1_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_1_X
    sty $d010
sprite6Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_1_OFFSET
sprite6Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_1
    bmi !done+
    inx

sprite7Positions:
    .eval verifySamePage()
    lda sortedSpritesY,x
    sta VIC.SPRITE_0_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_0_X
    sty $d010
sprite7Pointer:
    lda sortedSpritesPointers,x
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_0_OFFSET
sprite7Colors:
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_0
    bmi !done+
    inx

    // not done with changing sprite positions, but out of hw sprites, so start reusing sprite_7
    jmp sprite0Positions

    // make sure all spriteNPosition labels are in the same page
    .errorif (>sprite7Positions) != (>sprite0Positions), "Code crosses a page!"

!done:
    ldy spriteIrqLines,x                    // Get startline of next IRQ
    beq doneWithFrame                       // (0 if was last)
    inx
    stx spriteIndex                         // Store next IRQ sprite start-index to fetch the next sprite data 
    txa
    and #$07
    tax
    lda spriteIrqJumpTable,x                // Get the correct jump address to have the next irq start
    sta spriteJumpAddressLo                 // with the next hw sprite
    dey

spriteIrqDone:
    tya                                     // Get the raster line for the next sprite irq
    sec             
    sbc #$03                                // are we already late for the next IRQ? (<= 4 raster lines away)
    cmp $d012
    bcs doAnotherSpriteContinuationIrq
    jmp continuationSpriteIrqDirect

doAnotherSpriteContinuationIrq:
    sty $d012                               // we have enough time, just set next raster irq line
                                            // handler code will stay the same
    lsr $d019                               // acknowledge raster IRQ

doneWithInterrupt:
#if TIMING_IRQ
    lda Configuration.savedTimingD020
    sta $d020
#endif 

    ldy Configuration.spriteIrqYRegisterSaveZp
    ldx Configuration.spriteIrqXRegisterSaveZp
    lda Configuration.spriteIrqAccuSaveZp

    rti

doneWithFrame:
    lda #<topSpriteIrq
    sta $fffe
    lda #>topSpriteIrq
    sta $ffff
    lda #Configuration.TopSpriteIrqRasteLine
    sta $d012
    dec $d019
    bne doneWithInterrupt
}

sortedSpritesX:
    .fill Configuration.MAX_SPRITES * 2,0
sortedSpritesY:
    .fill Configuration.MAX_SPRITES * 2,0
sortedSpritesPointers:
    .fill Configuration.MAX_SPRITES * 2,0
sortedSpritesColors:
    .fill Configuration.MAX_SPRITES * 2,0
sortedSpritesD010:
    .fill Configuration.MAX_SPRITES * 2,0

spriteIrqLines:
    .fill Configuration.MAX_SPRITES * 2,0

spritePointers:
    .fill Configuration.MAX_SPRITES,0
spriteColors:
    .fill Configuration.MAX_SPRITES,0

spriteOrTable:
    .fill Configuration.MAX_SPRITES * 2,0
spriteAndTable:
    .fill Configuration.MAX_SPRITES * 2,0

spriteIrqJumpTable:
    .byte <continuationSpriteIrq.sprite0Positions, <continuationSpriteIrq.sprite1Positions
    .byte <continuationSpriteIrq.sprite2Positions, <continuationSpriteIrq.sprite3Positions
    .byte <continuationSpriteIrq.sprite4Positions, <continuationSpriteIrq.sprite5Positions
    .byte <continuationSpriteIrq.sprite6Positions, <continuationSpriteIrq.sprite7Positions

sprIrqAdvanceTbl:
    .byte -2, -3, -4, -5, -7, -8, -9, -10 // more sprites to handle take more time, these
    // are the offsets to allow more time fore more sprites (added to the rasterline of the next irq)

d015Tbl:
    .byte $00,$80,$c0,$e0,$f0,$f8,$fc,$fe,$ff

mainSpriteLoop:{
    .var tempSpriteIndex = allocateZpByte("tempSpriteIndex")
    .var tempPreviousOrder = allocateZpByte("tempPreviousOrder")
    .var tempD010 = allocateZpByte("tempD010")
    .var sortedSpriteEndIndex = allocateZpByte("sortedSpriteEndIndex")
    .var temp8 = allocateZpByte("temp8")

WF_Done:
    rts

WaitFrame:
    sta temp8
WF_Loop:
    lda Configuration.newFrame
    and temp8
    beq WF_Done
    jmp WF_Loop

UpdateFrame:
#if TIMING_SORT
    lda $d020
    and #$f
    sta Configuration.savedSortD020

    lda #Configuration.IrqSortColor
    sta $d020
#endif 

    lda Configuration.firstSortSprZP        // Switch sprite doublebuffer side
    eor #Configuration.MAX_SPRITES
    sta Configuration.firstSortSprZP
    lax #$00
    stx tempD010                            // D010 bits for first IRQ

SSpr_Loop1:
    ldy Configuration.spriteOrder,x         // check for coordinates being in order (old y <= new y for all ys)
    cmp Configuration.spriteY,y             // a=0 in first iteration, otherwise a=previous sprite y
    beq SSpr_NoSwap2                        // both value are the same, no need to lda new value
    bcc SSpr_NoSwap1                        // case new y is bigger than previous y, all ok, just go on

    // if not in order, begin insertion loop
    stx tempSpriteIndex                     // store current sprite index
    sty tempPreviousOrder                   // and store its previous order
    lda Configuration.spriteY,y             // load the new y corrdinate into accumulator
    ldy Configuration.spriteOrder-1,x       // load previous order into y register
    sty Configuration.spriteOrder,x         // and store it as new order. This pair has to be swapped at least.

    dex                                     // sort it backwards until it is at the correct position
    beq SSpr_SwapDone1                      // 0 means we reached the beginning and are done

SSpr_Swap1:
    ldy Configuration.spriteOrder-1,x       // load previous order into y register
    sty Configuration.spriteOrder,x         // and store it as new order.
    cmp Configuration.spriteY,y             // compare against the previous y
    bcs SSpr_SwapDone1                      // order correct?
    dex                                     // not correct, go backwards
    bne SSpr_Swap1                          // swap another pair

SSpr_SwapDone1:
    ldy tempPreviousOrder
    sty Configuration.spriteOrder,x
    ldx tempSpriteIndex
    ldy Configuration.spriteOrder,x

SSpr_NoSwap1:
    lda Configuration.spriteY,y
SSpr_NoSwap2:
    inx                                     // next sprite
    cpx #Configuration.MAX_SPRITES          // are we done yet?
    bne SSpr_Loop1

#if TIMING_SORT
    lda Configuration.savedSortD020
    sta $d020
#endif 

    lda #$80                                // Wait until last set sprites have displayed
    jsr WaitFrame                           // and the second doublebuffer half is free

#if TIMING_COPY
    lda $d020
    and #$f
    sta Configuration.savedCopyD020

    lda #Configuration.IrqCopyColor
    sta $d020
#endif 

    lda #<Configuration.spriteOrder         // get ZP address of sprite order array start
    sec
    sbc Configuration.firstSortSprZP        // subtract 0 or MAX_SPRITES (buffer area 1 or 2)
    sta copyLoopSourceAddress
    ldy Configuration.firstSortSprZP        // use the index also for y indexing to stay within spriteOrder array
                                            // the subtract needs to happen because y is used in the copy loop to index into both
                                            // a double buffered array and the single buffered temp zp array (spriteY, spriteXLo, ...)
    tya                                     // calculate the end of the first copy (8 sprites)
    adc #8-1                                // Carry is 1 because we set it with sec above, so one less to add
    sta copyEndIndex                        // Set endpoint for first copyloop


    bpl SSpr_CopyLoop1                      // this is never 0, so bpl just is faster than a jmp

SSpr_CopyLoop1Skip:
    inc SSpr_CopyLoop1+1

SSpr_CopyLoop1:
    // here sprites are ordered. The first sprite we'll see with a Y coordinate of $ff means the possible following ones will be $ff too
    // or it's the last one
    // this part of the code will copy data for 8 sprites and set the end mark

    // x register is used to index into the sprite data arrays (spriteY, spriteXLo, spriteXHi, spriteColors, spritePointers)
    // y register is used to index into the sorted arrays (first or second half of double buffers when writing)
    ldx copyLoopSourceAddress: Configuration.spriteOrder,y      // load sprite index (start will be modified before)
                                                                // because y is used to index into the sorted arrays, the base address has been reduced
                                                                // by the offset (0 or MAX_SPRITES) before to be able to also use y as index into the spriteOrder array
    lda Configuration.spriteY,x                                 // load y coord of this sprite. ($ff when invisible)
    cmp #Configuration.MAX_SPRITE_Y                             // if reach the maximum Y-coord endmark, all done
    bcs SSpr_CopyLoop1Done

    sta sortedSpritesY,y                    // save sprite's y coord into sorted y coord array (into the currently active buffer)
    lda spriteColors,x                      // check invisibility / flicker, sprite colors are "| $80"
    bmi SSpr_CopyLoop1Skip                  // skip
    sta sortedSpritesColors,y               // store into sorted sprite color array (into the currently active buffer)
    lda spritePointers,x                    // load sprite pointer
    sta sortedSpritesPointers,y             // store into sorted sprite color array (into the currently active buffer)
    lda Configuration.spriteXLo,x           // load sprite lo-x coord
    sta sortedSpritesX,y                    // store into sorted sprite lo-x array (into the currently active buffer)
    lda Configuration.spriteXHi,x           // load sprite hi-x coord bit
    beq SSpr_CopyLoop1MsbLow                // if 0 nothing to do
    lda tempD010                            // load temp msb sprites' msb byte
    ora spriteOrTable,y                     // or the bit into it
    sta tempD010                            // store back

SSpr_CopyLoop1MsbLow:
    iny                                     // next sprite
SSpr_CopyLoop1End:
    cpy copyEndIndex: #$00                  // value was overwritten with the current end
    bcc SSpr_CopyLoop1                      // no, more copying

    lda tempD010                            // load msb byte
    sta sortedSpritesD010-1,y               // for the 8th sprite store the d010 value
                                            // y was increased before, so -1 on address to accomodate for this.
    lda sortedSpritesColors-1,y             // Make first IRQ endmark.
    ora #$80                                // colors with bit 7 set indicate end for irq iteration
    sta sortedSpritesColors-1,y

    lda copyLoopSourceAddress               // Copy sortindex from first copyloop
    sta copyLoopSourceAddress2              // to second
    bcs SSpr_CopyLoop2                      // branch instead if jmp, we know carry is set because bcc above
                                            // did not jump (Cadaver really knows his shit)

    // if we are done with all sprites with less than 8 sprites
SSpr_CopyLoop1Done:
    lda tempD010                            // store d010 value to the current sprite
    sta sortedSpritesD010-1,y
    sty sortedSpriteEndIndex                // Store sorted sprite end index
    cpy Configuration.firstSortSprZP        // Any sprites at all?
    bne SSpr_EndMark                        // Make first (and final) IRQ endmask
SSpr_NoSprites:
    jmp SSpr_AllDone

    // this part of the code copies the sprite data to the sorted arrays, but checks for overlap of each sprite, to make sure
    // that no more than 8 sprites will overlap at the same time.
    // if this happens, that sprite is skipped

SSpr_CopyLoop2Skip:
    inc copyLoopSourceAddress2              // this will read from the next sprite, but not increase write indexes (because we want to skip)
SSpr_CopyLoop2:
    ldx copyLoopSourceAddress2: Configuration.spriteOrder,y
    lda Configuration.spriteY,x
    cmp #Configuration.MAX_SPRITE_Y         // check for end of sprite list
    bcs SSpr_CopyLoop2Done

    sta sortedSpritesY,y                    // save sprite's y coord into sorted y coord array (into the currently active buffer)
    sbc #21-1                               // -1 to avoid doing a sec, carry is clear at this point (because bcs above)
    cmp sortedSpritesY-8,y                  // check for physical sprite overlap (if they are right after each other, sprite[n].y-21 == sprite[n-8].y, carry is still set)
    bcc SSpr_CopyLoop2Skip

    lda spriteColors,x                      // Check invisibility / flicker (color is or'ed with $80 for invisiblity)
    bmi SSpr_CopyLoop2Skip
    sta sortedSpritesColors,y               // store color
    lda spritePointers,x
    sta sortedSpritesPointers,y             // store sprite pointer
    lda Configuration.spriteXLo,x
    sta sortedSpritesX,y                    // store x coord
    lda Configuration.spriteXHi,x           // x msb of this sprite
    beq SSpr_CopyLoop2MsbLow                // if 0, jump to clear this bit
    lda sortedSpritesD010-1,y               // load d010 value of the previous sprite
    ora spriteOrTable,y                     // or the bit for the current sprite
    bne SSpr_CopyLoop2MsbDone
SSpr_CopyLoop2MsbLow:
    lda sortedSpritesD010-1,y               // load d010 value of the previous sprite
    and spriteAndTable,y                    // and the bit for the current sprite
SSpr_CopyLoop2MsbDone:
    sta sortedSpritesD010,y                 // store d010 value of the current sprite
    iny
    bne SSpr_CopyLoop2                      // will during this loop always be positive, non zero so better
                                            // than jmp
    .eval deallocateZpByte(tempPreviousOrder)
    .eval deallocateZpByte(tempSpriteIndex)

SSpr_CopyLoop2Done:
    // all sorted sprite data has been written and overlapping sprites have been skipped at this point.
    // now we need to determine the irq raster lines in advance.

    sty sortedSpriteEndIndex                // Store sorted sprite end index
    ldy copyEndIndex                        // Go back to the second IRQ start (this is the index of the 8th sprite either in 1st or 2nd half of the double buffer)
    cpy sortedSpriteEndIndex
    beq SSpr_FinalEndMark                   // previous end index is equal to current y, so done without more irqs

    .var tempIrqSpriteIndex = allocateZpByte("tempIrqSpriteIndex")

SSpr_IrqLoop:
    sty tempIrqSpriteIndex                  // Store sprite index for IRQ (startindex)
    lda sortedSpritesY,y                    // load y coord of current sprite
                                            // C=0 here (cmp could result < 0 or ==, beq jumped, so only case with C=0 is possible here)
    sbc #21 + 12 - 1                        // First sprite of IRQ: store the Y-coord
    sta irqYCmpValue1                       // compare values
    adc #21 + 12 + 6 - 1                    // this allows the írq to handle sprites for
    sta irqYCmpValue2
SSpr_IrqSprLoop:
    iny
    cpy sortedSpriteEndIndex
    bcs SSpr_IrqDone

    lda sortedSpritesY-8,y                  // Add next sprite to this IRQ?
SSpr_IrqYCmp1:
    cmp irqYCmpValue1: #$00                 // (try to add as many as possible while
    bcc SSpr_IrqSprLoop                     // avoiding glitches)

    lda sortedSpritesY,y
SSpr_IrqYCmp2:
    cmp irqYCmpValue2: #$00
    bcc SSpr_IrqSprLoop

SSpr_IrqDone:
    tya
    sbc tempIrqSpriteIndex
    tax
    lda sprIrqAdvanceTbl-1,x
    ldx tempIrqSpriteIndex
    adc sortedSpritesY,x
    sta spriteIrqLines-1,x                  // Store IRQ start line (with advance)

SSpr_EndMark:
    lda sortedSpritesColors-1,y             // Make IRQ endmark
    ora #$80
    sta sortedSpritesColors-1,y
    cpy sortedSpriteEndIndex                // Sprites left?
    bcc SSpr_IrqLoop

SSpr_FinalEndMark:
    lda #$00                                // Make final endmark
    sta spriteIrqLines-1,y

    .eval deallocateZpByte(tempIrqSpriteIndex)

SSpr_AllDone:

#if TIMING_COPY
    lda Configuration.savedCopyD020
    sta $d020
#endif 

UF_ShowSprites:
    lda sortedSpriteEndIndex                // Check which sprites are on
    tay
    sec
    sbc Configuration.firstSortSprZP
    cmp #$09
    bcc UF_NotMoreThan8
    lda #$08
UF_NotMoreThan8:
    tax
    lda d015Tbl,x
UF_NoSprites2:  
    sta topSpriteIrq.d015Value
    beq UF_NoSprites
    ldx Configuration.firstSortSprZP                
    stx continuationSpriteIrq.firstSortedSpriteIndex
UF_NoSprites:
    dec Configuration.newFrame              // $ff = process new frame

    .eval deallocateZpByte(sortedSpriteEndIndex)
    .eval deallocateZpByte(tempD010)

    // some dummy movements
    inc Configuration.spriteY+23
    inc Configuration.spriteY+23
    inc Configuration.spriteY+23

    inc Configuration.spriteY+20
    inc Configuration.spriteY+20
    inc Configuration.spriteY+20
    inc Configuration.spriteY+20

    inc Configuration.spriteY+10
    inc Configuration.spriteY+10

    inc Configuration.spriteY+5

    // wait for the screen part to end before starting the sorting operations
    jsr WaitBottom

    // update raster irq to start again with the top part
    lda #<topSpriteIrq
    sta $fffe
    lda #>topSpriteIrq
    sta $ffff

    lda #Configuration.TopSpriteIrqRasteLine
    sta $d012

    rts
}

WaitBottom:     
    lda $d011                               // wait until bottom of screen
    bmi WaitBottom
WB_Loop2:
    lda $d011
    bpl WB_Loop2
    rts

* = $2000
.align 64
.segment Default "Sprite data"
spriteData01:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData02:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData03:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData04:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData05:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData06:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....######.......###")
SpriteLine("###....#.............###")
SpriteLine("###....#.............###")
SpriteLine("###.....#####........###")
SpriteLine("###..........#.......###")
SpriteLine("###....######........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData07:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....######.......###")
SpriteLine("###....#.............###")
SpriteLine("###....#.............###")
SpriteLine("###....######........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData08:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....#######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........#........###")
SpriteLine("###.......####.......###")
SpriteLine("###........#.........###")
SpriteLine("###........#.........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData09:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData10:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData11:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData12:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData13:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData14:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData15:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData16:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....######.......###")
SpriteLine("###....#.............###")
SpriteLine("###....#.............###")
SpriteLine("###.....#####........###")
SpriteLine("###..........#.......###")
SpriteLine("###....######........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData17:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....######.......###")
SpriteLine("###....#.............###")
SpriteLine("###....#.............###")
SpriteLine("###....######........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData18:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....#######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........#........###")
SpriteLine("###.......####.......###")
SpriteLine("###........#.........###")
SpriteLine("###........#.........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData19:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData20:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.....#.......###")
SpriteLine("###....#.....#.......###")
SpriteLine("###.....######.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData21:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###......####........###")
SpriteLine("###.....#....#.......###")
SpriteLine("###....#......#......###")
SpriteLine("###....#......#......###")
SpriteLine("###.....#....#.......###")
SpriteLine("###......####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData22:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..........#.......###")
SpriteLine("###.........##.......###")
SpriteLine("###........#.#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.........###......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData23:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
spriteData24:
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###....#.............###")
SpriteLine("###.....######.......###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###....######........###")
SpriteLine("###..........#.......###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..........#.......###")
SpriteLine("###.....#####........###")
SpriteLine("###..................###")
SpriteLine("########################")
SpriteLine("########################")