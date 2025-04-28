// coded in parallel to Martin Piper's great sprite multiplexer explanation video
// https://www.youtube.com/watch?v=BtTCzjmwsMA

#import "../../includes/cia1_constants.inc"
#import "../../includes/cia2_constants.inc"
#import "../../includes/vic_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"
#import "../../includes/irq_helpers.asm"
#import "../../includes/sprite_helpers.asm"

BasicUpstart2(main)

.const VIC2MaxSprites = 8
.const MaxSprites = 24
.const ScreenRamBase = $0400

main:
    sei                                         // don't allow other irqs to happen during setup

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES       // disable timer on CIAs mask
    sta CIA1.INTERRUPT_CONTROL_REG              // disable all CIA1 irqs
    sta CIA2.INTERRUPT_CONTROL_REG              // disable all CIA2 irqs

    lda #$1b
    sta $d011                                   // set MSB of raster line, it's bit 7
    
    lda #1
    sta $d01a                    // enable raster irq

    lda #$35    
    sta Zeropage.PORT_REG                       // disable ROM

	lda #%11111111                              // 1 = sprite enable
	sta $d015 

    irq_set(irqHandler, 20)

    lda CIA1.INTERRUPT_CONTROL_REG              // ACK CIA 1 interrupts in case there are pending ones
    lda CIA2.INTERRUPT_CONTROL_REG              // ACK CIA 2 interrupts in case there are pending ones
    lsr $d019

    cli                                         // now we are done and can enable interrupts again

waitForever: 
    inc ScreenRamBase
    jmp waitForever

.align $100                                     // align to $100 to avoid page crossing and branches (costs 1 extra cycle)
irqHandler: {
    irq_save()

    inc $d020

setSpriteValues:
.for (var i = 0; i < VIC2MaxSprites; i++ ) {
    ldx spriteIndexes + i
    lda spriteXCoords,x
    sta VIC.SPRITE_0_X + i * 2
    lda spriteYCoords,x
    sta VIC.SPRITE_0_Y+ i * 2
    lda SpriteColors,x
    sta VIC.SPRITE_SOLID_0 + i
    lda spritePointers,x
    sta ScreenRamBase + VIC.SPRITE_POINTER_0_OFFSET + i
}    
 
    lda #0
	sta nextVICSpriteIndex
	lda #8
	sta nextSpriteIndexToProcess

    // Calculate the first safe raster position, underneath the first sprite Y position
	lda VIC.SPRITE_0_Y
	clc
	adc #22                                     // sprite is 21 high, add 22 to be safe    

    cmp #50-21
	bcs okPosition
	lda #50-21
okPosition:
    sta $d012
    irq_set_no_line(subsequentSpriteIrq)
    
    dec $d020

    irq_endRaster()
}

subsequentSpriteIrq: {
    irq_save()
    
    inc $d020

    lda nextVICSpriteIndex                      // next index of hw sprite index
    asl                                         // hw sprite * 2 == index of x,y coors
    tay
setSpriteValues:
    ldx nextSpriteIndexToProcess                // next index of virtual sprite number
    lda spriteIndexes,x
    tax
    lda spriteXCoords,x
	sta VIC.SPRITE_0_X,y                        // 0 + sprite * 2
	lda spriteYCoords,x
	sta VIC.SPRITE_0_Y,y                        // 1 (!) + sprite * 2     
	lda SpriteColors,x
    ldy nextVICSpriteIndex
	sta VIC.SPRITE_SOLID_0,y
	lda spritePointers,x
	sta ScreenRamBase + VIC.SPRITE_POINTER_0_OFFSET,y
	
    inc nextSpriteIndexToProcess
    ldx nextSpriteIndexToProcess
	
    cpx #MaxSprites
	bcs startTopRowAgain

	iny
	tya
	and #7
	sta nextVICSpriteIndex
	asl
	tay

	// Test the next sprite Y position bottom edge with the current raster
	lda VIC.SPRITE_0_Y,y
	clc
	adc #22
	sta nextSafePosition
	lda $d012
	cmp nextSafePosition
	bcs setSpriteValues


closeTime:
	lda nextSafePosition
	sec
	sbc $d012
	cmp #2
	bcs notCloseTime

quickWait:
	lda $d012
	cmp nextSafePosition
	bcc quickWait
	jmp setSpriteValues

notCloseTime:
    lda nextSafePosition
	sta $d012                                   // sme irq handler, just later
    
    dec $d020

    irq_endRaster()
   
startTopRowAgain:

    inc spriteYCoords+4

	inc $d020
doSort:
	ldy #0
	sty changedFlag
sortLoop1:
	ldx spriteIndexes+1,y
	lda spriteYCoords,x
	ldx spriteIndexes,y
	cmp spriteYCoords,x
	bcs isGreaterEQThan

	// Swap index
	lda spriteIndexes+1,y
	pha
	lda spriteIndexes,y
	sta spriteIndexes+1,y
	pla
	sta spriteIndexes,y
	inc changedFlag

isGreaterEQThan:
	iny
	cpy #MaxSprites-2
	bne sortLoop1

	lda changedFlag
	bne doSort
.break
    dec $d020

    irq_set(irqHandler, 20)
    
    dec $d020

    irq_endRaster()    
}

spriteIndexes:
    .fill MaxSprites, i

spriteXCoords:
    .fill MaxSprites, 30 + (i * 9)

spriteYCoords:
	.byte 50 , 50 , 50 , 50 , 51 , 51 , 60 , 72
	.byte 80 , 100 , 100 , 110 , 120 , 130 , 140 , 150
	.byte 160 , 170 , 180 , 190 , 200 , 220 , 220 , 230

spritePointers:
    .fill MaxSprites, ($3e00 / 64) + mod(i, 7)

SpriteColors:
    .fill MaxSprites, (i & 15) == BLUE ? 1 : i & 15

nextVICSpriteIndex:
	.byte 0
nextSpriteIndexToProcess:
	.byte 0
nextSafePosition:
    .byte 0
changedFlag:
    .byte 0

*=$3e00
.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####.......##.......####")
SpriteLine("###.#......##......#.###")
SpriteLine("###..#.....##.....#..###")
SpriteLine("###...#....##....#...###")
SpriteLine("###....#...##...#....###")
SpriteLine("###.....#..##..#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###......#####.......###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#..#..#......###")
SpriteLine("###....#...#...#.....###")
SpriteLine("###...#....#....#....###")
SpriteLine("###..#.....#.....#...###")
SpriteLine("###.#......#......#..###")
SpriteLine("####.......#.......#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###........##.......####")
SpriteLine("###........##......#.###")
SpriteLine("###........##.....#..###")
SpriteLine("###........##....#...###")
SpriteLine("###........##...#....###")
SpriteLine("###........##..#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###......#####.......###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#..#..#......###")
SpriteLine("###....#...#...#.....###")
SpriteLine("###...#....#....#....###")
SpriteLine("###..#.....#.....#...###")
SpriteLine("###.#......#......#..###")
SpriteLine("####.......#.......#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("###.................####")
SpriteLine("###................#.###")
SpriteLine("###...............#..###")
SpriteLine("###..............#...###")
SpriteLine("###.............#....###")
SpriteLine("###............#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###......#####.......###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#..#..#......###")
SpriteLine("###....#...#...#.....###")
SpriteLine("###...#....#....#....###")
SpriteLine("###..#.....#.....#...###")
SpriteLine("###.#......#......#..###")
SpriteLine("####.......#.......#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####.......##........###")
SpriteLine("###.#......##........###")
SpriteLine("###..#.....##........###")
SpriteLine("###...#....##........###")
SpriteLine("###....#...##........###")
SpriteLine("###.....#..##........###")
SpriteLine("###......####........###")
SpriteLine("###......####........###")
SpriteLine("##############.......###")
SpriteLine("###......#####.......###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#..#..#......###")
SpriteLine("###....#...#...#.....###")
SpriteLine("###...#....#....#....###")
SpriteLine("###..#.....#.....#...###")
SpriteLine("###.#......#......#..###")
SpriteLine("####.......#.......#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####.......##.......####")
SpriteLine("###.#......##......#.###")
SpriteLine("###..#.....##.....#..###")
SpriteLine("###...#....##....#...###")
SpriteLine("###....#...##...#....###")
SpriteLine("###.....#..##..#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###..................###")
SpriteLine("###..................###")
SpriteLine("###........#..#......###")
SpriteLine("###........#...#.....###")
SpriteLine("###........#....#....###")
SpriteLine("###........#.....#...###")
SpriteLine("###........#......#..###")
SpriteLine("###........#.......#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####.......##.......####")
SpriteLine("###.#......##......#.###")
SpriteLine("###..#.....##.....#..###")
SpriteLine("###...#....##....#...###")
SpriteLine("###....#...##...#....###")
SpriteLine("###.....#..##..#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###......###.........###")
SpriteLine("###......##..........###")
SpriteLine("###.....#............###")
SpriteLine("###....#.............###")
SpriteLine("###...#..............###")
SpriteLine("###..#...............###")
SpriteLine("###.#................###")
SpriteLine("####.................###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####................####")
SpriteLine("###.#..............#.###")
SpriteLine("###..#............#..###")
SpriteLine("###...#..........#...###")
SpriteLine("###....#........#....###")
SpriteLine("###.....#......#.....###")
SpriteLine("###......######......###")
SpriteLine("###......#####.......###")
SpriteLine("########################")
SpriteLine("###......#####.......###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#.....#......###")
SpriteLine("###....#.......#.....###")
SpriteLine("###...#.........#....###")
SpriteLine("###..#...........#...###")
SpriteLine("###.#.............#..###")
SpriteLine("####...............#.###")
SpriteLine("########################")
SpriteLine("########################")

.align 64
SpriteLine("########################")
SpriteLine("########################")
SpriteLine("####.......##.......####")
SpriteLine("###.#......##......#.###")
SpriteLine("###..#.....##.....#..###")
SpriteLine("###...#....##....#...###")
SpriteLine("###....#...##...#....###")
SpriteLine("###.....#..##..#.....###")
SpriteLine("###......######......###")
SpriteLine("###..................###")
SpriteLine("###..................###")
SpriteLine("###..................###")
SpriteLine("###......#####.......###")
SpriteLine("###.....#..#..#......###")
SpriteLine("###....#...#...#.....###")
SpriteLine("###...#....#....#....###")
SpriteLine("###..#.....#.....#...###")
SpriteLine("###.#......#......#..###")
SpriteLine("####.......#.......#.###")
SpriteLine("########################")
SpriteLine("########################")
