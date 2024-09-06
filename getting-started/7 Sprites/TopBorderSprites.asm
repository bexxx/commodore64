#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

BasicUpstart2(main)

.const Line24RasterLine = $f8
.const Line25RasterLine = $fb

main:
    lda #%00000111
    sta VIC.SPRITE_ENABLE                   
    lda #%00000000
    sta $d01d
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y

    lda #343-24-24-24
    sta VIC.SPRITE_0_X
    clc
    lda #343-24-24
    sta VIC.SPRITE_1_X
    clc
    lda #343-24
    sta VIC.SPRITE_2_X

    lda #16
    sta VIC.SPRITE_0_Y
    sta VIC.SPRITE_1_Y
    sta VIC.SPRITE_2_Y
    lda #%00000111
    sta VIC.SPRITE_MSB_X

    lda #WHITE
    sta VIC.SPRITE_SOLID_0
    sta VIC.SPRITE_SOLID_1
    sta VIC.SPRITE_SOLID_2

    ldx #(spriteData / 64)
    stx VIC.SPRITE_POINTER_0_OFFSET + $0400
    inx
    stx VIC.SPRITE_POINTER_1_OFFSET + $0400
    inx
    stx VIC.SPRITE_POINTER_2_OFFSET + $0400

    sei

    lda #Line25RasterLine                       // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register

    lda #<interruptHandlerStart                 // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandlerStart                 // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda VIC.INTERRUPT_ENABLE                    // load current value of VIC interrupt control register
    ora #VIC.ENABLE_RASTER_INTERRUPT_MASK       // set bit 0 - enable raster line interrupt
    sta VIC.INTERRUPT_ENABLE                    // store back to enable raster interrupt

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    cli                                         // allow interrupts to happen again

    lda #$0
    sta $3fff

!: jmp !-
    rts

.segment Default "Raster interrupt"
interruptHandlerStart:
    lda VIC.INTERRUPT_EVENT                     // is this triggered by VIC?
    bmi rasterInterruptHandler                  // VIC interrupt == bit 7, negative flag is copy of bit 7 of accumulator

    lda CIA1.INTERRUPT_CONTROL_REG              // then it's a timer irq. ack timer interrupt, reading resets bits
    jmp Internals.InterruptHandlerPointer       // call system interrupt handler
 
rasterInterruptHandler:
    sta VIC.INTERRUPT_EVENT                    
    lda VIC.CURRENT_RASTERLINE_REG             
    cmp #Line25RasterLine                          
    bne set24                        

    lda VIC.SCREEN_CONTROL_REG  
    ora #VIC.ENABLE_25_LINES_MASK
    sta VIC.SCREEN_CONTROL_REG 
    lda #$0                  
    sta VIC.CURRENT_RASTERLINE_REG 

    lda #%00000000
    sta VIC.SPRITE_ENABLE   

    jmp exit

set24:
    cmp #Line24RasterLine
    bne enableSprites

    lda VIC.SCREEN_CONTROL_REG           
    and #VIC.ENABLE_25_LINES_CLEAR_MASK
    sta VIC.SCREEN_CONTROL_REG
    lda #Line25RasterLine
    sta VIC.CURRENT_RASTERLINE_REG

exit:    
    ReturnFromInterrupt()                       // leave interrupt handler

enableSprites:
    cmp #$0
    bne exit

    lda #Line24RasterLine                
    sta VIC.CURRENT_RASTERLINE_REG 
    lda #%00000111
    sta VIC.SPRITE_ENABLE 
    jmp exit

.align 64
.segment Default "Sprites"
spriteData:
// Sprite #1
// Single color mode, BG color: 6, Sprite color: 1
	.byte 255, 255, 255
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   0
	.byte  12,   0,   3
	.byte  12,   3, 225
	.byte  15,   7, 240
	.byte  15, 231,  48
	.byte  15, 230,  48
	.byte  14,  54,  48
	.byte  12,  22,  96
	.byte  12,  23, 224
	.byte  12,  23, 128
	.byte  14, 119,   0
	.byte   7, 227, 254
	.byte   7, 192, 254
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

.align 64
// Sprite #2
// Single color mode, BG color: 6, Sprite color: 1
	.byte 255, 255, 255
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   6
	.byte 195,  98, 196
	.byte 103,  38,  76
	.byte  54,  52, 108
	.byte  28,  20,  40
	.byte   8,  12,  56
	.byte  28,   8,  24
	.byte  62,  28,  24
	.byte  50,  22,  60
	.byte  97,  18,  36
	.byte  65, 178,  98
	.byte  64,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

.align 64
// Sprite #3
// Single color mode, BG color: 6, Sprite color: 1
	.byte 255, 255, 255
	.byte   0,   8,   6
	.byte   0, 124,   6
	.byte  15, 248,  14
	.byte 127, 226,  14
	.byte  63, 199,  24
	.byte  25, 195, 152
	.byte   0, 193, 248
	.byte   0, 225, 240
	.byte   0, 224, 240
	.byte   0, 240, 112
	.byte   0, 112,  96
	.byte   0, 112,  32
	.byte   0,  32,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte   0,   0,   0
	.byte 255, 255, 255

