#import "../../includes/vic_constants.inc"


.namespace Configuration {
    .label accuSaveZp = $2
    .label xRegisterSaveZp = $3
    .label yRegisterSaveZp = $4

    .label ScreenRamAddress = $0400
    .label MAX_SPRITES = 24
}

.align $100
topSpriteIrq: {
    sta Configuration.accuSaveZp
    stx Configuration.xRegisterSaveZp
    sty Configuration.yRegisterSaveZp

    lda d015Value: #0
    sta $d015
    beq noSprites

    lda #<continuationSpriteIrq                      //Set up the sprite display IRQ
    sta $fffe
    lda #>continuationSpriteIrq
    sta $ffff

    jmp continuationSpriteIrq.displaySprites

noSprites: 
    lsr $d019

    ldy Configuration.yRegisterSaveZp
    ldx Configuration.xRegisterSaveZp
    lda Configuration.accuSaveZp

    rti
}

.align $100
continuationSpriteIrq: {
    sta Configuration.accuSaveZp
    stx Configuration.xRegisterSaveZp
    sty Configuration.yRegisterSaveZp

continuationSpriteIrqDirect:
Irq2_SprIndex:  
    ldx spriteIndex: #$00

Irq2_SprJump:   
    jmp spriteJumpAddressLo: sprite0Positions

displaySprites:
    ldx firstSortedSpriteIndex: #$0                        //Go through the first sprite IRQ immediately

sprite0Positions:      
    lda sortedSpritesY,x
    sta VIC.SPRITE_7_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_7_X
    sty $d010
    lda sortedSpritesPointers,x
sprite0Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_7_OFFSET
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
    lda sortedSpritesPointers,x
sprite1Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_6_OFFSET
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
    lda sortedSpritesPointers,x
sprite2Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_5_OFFSET
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
    lda sortedSpritesPointers,x
sprite3Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_4_OFFSET
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_4
    bpl !+
!done:
    jmp !done+
!:
    inx

sprite4Positions:      
    lda sortedSpritesY,x
    sta VIC.SPRITE_3_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_3_X
    sty $d010
    lda sortedSpritesPointers,x
sprite4Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_3_OFFSET
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
    lda sortedSpritesPointers,x
sprite5Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_2_OFFSET
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
    lda sortedSpritesPointers,x
sprite6Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_1_OFFSET
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_1
    bmi !done+
    inx

sprite7Positions:      
    lda sortedSpritesY,x
    sta VIC.SPRITE_0_Y
    lda sortedSpritesX,x
    ldy sortedSpritesD010,x
    sta VIC.SPRITE_0_X
    sty $d010
    lda sortedSpritesPointers,x
sprite7Pointer: 
    sta Configuration.ScreenRamAddress + VIC.SPRITE_POINTER_0_OFFSET
    lda sortedSpritesColors,x
    sta VIC.SPRITE_MULTICOLOR_3_0
    bmi !done+
    inx
    
    jmp sprite0Positions

    .errorif (>sprite7Positions) != (>sprite0Positions), "Code crosses a page!"

!done:
    ldy spriteIrqLines,x                //Get startline of next IRQ
    beq doneWithFrame                //(0 if was last)
    inx
    stx spriteIndex                      //Store next IRQ sprite start-index
    txa
    and #$07
    tax
    lda spriteIrqJumpTable,x             //Get the correct jump address
    sta spriteJumpAddressLo
    dey
Irq2_SprIrqDoneNoLoad:
    tya
    sec
    sbc #$03                        //Already late from the next IRQ?
    cmp $d012
    bcs doAnotherSpriteContinuationIrq
    jmp continuationSpriteIrqDirect     

doAnotherSpriteContinuationIrq:
    sty $d012
    dec $d019                       //Acknowledge raster IRQ

doneWithFrame:
    ldy Configuration.yRegisterSaveZp
    ldx Configuration.xRegisterSaveZp
    lda Configuration.accuSaveZp

    rti
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

spriteIrqJumpTable:  
    .byte <continuationSpriteIrq.sprite0Positions, <continuationSpriteIrq.sprite1Positions
    .byte <continuationSpriteIrq.sprite2Positions, <continuationSpriteIrq.sprite3Positions
    .byte <continuationSpriteIrq.sprite4Positions, <continuationSpriteIrq.sprite5Positions
    .byte <continuationSpriteIrq.sprite6Positions, <continuationSpriteIrq.sprite7Positions
