#importonce 

.namespace VIC
{
    .label BASE  = $d000

    // control registers
    .label CONTR_REG = $d016
    .label SCREEN_CONTROL_REG = $d011
    .label RASTERLINE_BIT9_MASK = %10000000
    .label RASTERLINE_BIT9_CLEAR_MASK = ~RASTERLINE_BIT9_MASK
    .label ENABLE_SCREEN_MASK = %00010000
    .label ENABLE_SCREEN_CLEAR_MASK = ~ENABLE_SCREEN_MASK
    .label ENABLE_25_LINES_MASK = %00001000
    .label ENABLE_25_LINES_CLEAR_MASK = ~ENABLE_25_LINES_MASK
    .label ENABLE_40_COLUMNS_MASK = %00001000
    .label ENABLE_40_COLUMNS_CLEAR_MASK = ~ENABLE_40_COLUMNS_MASK

    .label CURRENT_RASTERLINE_REG = $d012

    // screen color registers
    .label BORDER_COLOR = $d020
    .label SCREEN_COLOR = $d021
    .label TXT_COLOUR_1 = $d022
    .label TXT_COLOUR_2 = $d023
    .label TXT_COLOUR_3 = $d024

    // sprite colors registers
    .label SPRITE_MULTICOLOR_1 = $d025
    .label SPRITE_MULTICOLOR_2 = $d026
    .label SPRITE_MULTICOLOR_3_0 = $d027
    .label SPRITE_MULTICOLOR_3_1 = $d028
    .label SPRITE_MULTICOLOR_3_2 = $d029
    .label SPRITE_MULTICOLOR_3_3 = $d02a
    .label SPRITE_MULTICOLOR_3_4 = $d02b
    .label SPRITE_MULTICOLOR_3_5 = $d02c
    .label SPRITE_MULTICOLOR_3_6 = $d02d
    .label SPRITE_MULTICOLOR_3_7 = $d02e

    // sprite enable
    .label SPRITE_ENABLE = $d015
    .label SPRITE_0_ENABLE_MASK = %00000001
    .label SPRITE_1_ENABLE_MASK = %00000010
    .label SPRITE_2_ENABLE_MASK = %00000100
    .label SPRITE_3_ENABLE_MASK = %00001000
    .label SPRITE_4_ENABLE_MASK = %00010000
    .label SPRITE_5_ENABLE_MASK = %00100000
    .label SPRITE_6_ENABLE_MASK = %01000000
    .label SPRITE_7_ENABLE_MASK = %10000000

    // address holding pointer info to graphics area
    .label GRAPHICS_POINTER = $d018

    // sprite pointers - relative to GRAPHICS_POINTER
    // sprite data address / 64


    .label SPRITE_POINTER_0_OFFSET = $03f8
    .label SPRITE_POINTER_1_OFFSET = $03f9
    .label SPRITE_POINTER_2_OFFSET = $03fa
    .label SPRITE_POINTER_3_OFFSET = $07fb
    .label SPRITE_POINTER_4_OFFSET = $037fc
    .label SPRITE_POINTER_5_OFFSET = $03fd
    .label SPRITE_POINTER_6_OFFSET = $03fe
    .label SPRITE_POINTER_7_OFFSET = $03ff

    // sprite screen locations
    .label SPRITE_0_X = $d000
    .label SPRITE_0_Y = $d001
    .label SPRITE_1_X = $d002
    .label SPRITE_1_Y = $d003
    .label SPRITE_2_X = $d004
    .label SPRITE_2_Y = $d005
    .label SPRITE_3_X = $d006
    .label SPRITE_3_Y = $d007
    .label SPRITE_4_X = $d008
    .label SPRITE_4_Y = $d009
    .label SPRITE_5_X = $d00a
    .label SPRITE_5_Y = $d00b
    .label SPRITE_6_X = $d00c
    .label SPRITE_6_Y = $d00d
    .label SPRITE_7_X = $d00e
    .label SPRITE_7_Y = $d00d
    .label SPRITE_MSB_X = $d010

    // high res or multicolor
    .label SPRITE_HIRES = $d01c

    // sprite size expanders
    .label SPRITE_DOUBLE_X = $d01d
    .label SPRITE_DOUBLE_Y = $d017

    // sprite color settings
    .label SPRITE_SOLID_ALL_1 = $d025
    .label SPRITE_SOLID_ALL_2 = $d026
    .label SPRITE_SOLID_0 = $d027
    .label SPRITE_SOLID_1 = $d028
    .label SPRITE_SOLID_2 = $d029
    .label SPRITE_SOLID_3 = $d02a
    .label SPRITE_SOLID_4 = $d02b
    .label SPRITE_SOLID_5 = $d02c
    .label SPRITE_SOLID_6 = $d02d
    .label SPRITE_SOLID_7 = $d02e

    // sprite priority over background
    .label SPRITE_BG_PRIORITY = $d01b

    // collision detection
    .label SPRITE_COLL_SPRITE = $d01e
    .label SPRITE_COLL_BG = $d01f

    // interrupt registers
    .label INTERRUPT_EVENT = $d019
    .label INTERRUPT_ENABLE = $d01a
    .label ENABLE_RASTER_INTERRUPT_MASK = %1 // Bit 0

    // C64 Colour Codes 
    .label black = $0
    .label white = $1
    .label red = $2
    .label cyan = $3
    .label purple  = $4
    .label green = $5
    .label blue = $6
    .label yellow = $7
    .label orange = $8
    .label brown = $9
    .label lred = $a
    .label dgrey = $b
    .label grey = $c
    .label lgreen = $d
    .label lblue = $e
    .label lgrey = $f

    .label BITMAP_MODE = %00100000
    .label MULTI_COLOR = %00010000

    .label SELECT_SCREENBUFFER_AT_0000_MASK = %0000 << 4 // start at $0000
    .label SELECT_SCREENBUFFER_AT_0400_MASK = %0001 << 4 // start at $0400	
    .label SELECT_SCREENBUFFER_AT_0800_MASK = %0010 << 4 // start at $0800	
    .label SELECT_SCREENBUFFER_AT_0C00_MASK = %0011 << 4 // start at $0C00
    .label SELECT_SCREENBUFFER_AT_1000_MASK = %0100 << 4 // start at $1000
    .label SELECT_SCREENBUFFER_AT_1400_MASK = %0101 << 4 // start at $1400
    .label SELECT_SCREENBUFFER_AT_1800_MASK = %0110 << 4 // start at $1800
    .label SELECT_SCREENBUFFER_AT_1C00_MASK = %0111 << 4 // start at $1C00
    .label SELECT_SCREENBUFFER_AT_2000_MASK = %1000 << 4 // start at $2000
    .label SELECT_SCREENBUFFER_AT_2400_MASK = %1001 << 4 // start at $2400
    .label SELECT_SCREENBUFFER_AT_2800_MASK = %1010 << 4 // start at $2800
    .label SELECT_SCREENBUFFER_AT_2C00_MASK = %1011 << 4 // start at $2C00	
    .label SELECT_SCREENBUFFER_AT_3000_MASK = %1100 << 4 // start at $3000
    .label SELECT_SCREENBUFFER_AT_3400_MASK = %1101 << 4 // start at $3400	
    .label SELECT_SCREENBUFFER_AT_3800_MASK = %1110 << 4 // start at $3800
    .label SELECT_SCREENBUFFER_AT_38C0_MASK = %1111 << 4 // start at $3C00
    .label SELECT_SCREENBUFFER_CLEAR_MASK = ~(%1111 << 4) // select screenbuffer with bits 7-4

    .label SELECT_CHARSET_AT_0000_MASK = %0000 // start at $0000
    .label SELECT_CHARSET_AT_0800_MASK = %0010 // start at $0800
    .label SELECT_CHARSET_AT_1000_MASK = %0100 // start at $1000
    .label SELECT_CHARSET_AT_1800_MASK = %0110 // start at $1800
    .label SELECT_CHARSET_AT_2000_MASK = %1000 // start at $2000
    .label SELECT_CHARSET_AT_2800_MASK = %1010 // start at $2800	
    .label SELECT_CHARSET_AT_3000_MASK = %1100 // start at $3000	
    .label SELECT_CHARSET_AT_3800_MASK = %1110 // start at $3800	
    .label SELECT_CHARSET_CLEAR_MASK = ~%00001111 // select screenbuffer with bits 3-0, 0 unused in textmode

}

.macro ConfigureVicMemory(ScreenBufferMask, CharsetBufferMask) {
    lda VIC.GRAPHICS_POINTER
    and #VIC.SELECT_CHARSET_CLEAR_MASK
    ora #VIC.SELECT_CHARSET_AT_0000_MASK
    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
    ora #VIC.SELECT_SCREENBUFFER_AT_2000_MASK
    sta VIC.GRAPHICS_POINTER
}

