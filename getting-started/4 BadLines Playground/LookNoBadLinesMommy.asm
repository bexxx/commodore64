#import "../../includes/vic_constants.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/internals.inc"
#import "../../includes/cia2_constants.inc"

.namespace Consts {
    .label ScreenBase = $0000
    .label VicBankBase = $4000   
}

BasicUpstart2(init)

init:
                sei
                lda #%00110101
                                

                sta 1
                                // Bit 0 - LORAM: Configures RAM or ROM at $A000-$BFFF (see bankswitching)
                                // Bit 1 - HIRAM: Configures RAM or ROM at $E000-$FFFF (see bankswitching)
                                // Bit 2 - CHAREN: Configures I/O or ROM at $D000-$DFFF (see bankswitching)
                                // Bit 3 - Cassette Data Output Line (Datasette)
                                // Bit 4 - Cassette Switch Sense; 1 = Switch Closed
                                // Bit 5 - Cassette Motor Control; 0 = On, 1 = Off
                                // Bit 6 - Undefined
                                // Bit 7 - Undefined

    ldx #LIGHT_BLUE
    stx VIC.SPRITE_MULTICOLOR_1
    ldx #BLUE
    stx VIC.SPRITE_MULTICOLOR_2
    ldx #CYAN
    stx VIC.SPRITE_MULTICOLOR_3_0

    // enable all sprites
    lda #$1
    sta VIC.SPRITE_ENABLE                   

    // stretch all sprites
    lda #$01
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y

    lda #150
    sta VIC.SPRITE_0_X

    // MSB for sprites are in $d010, bit 7 for sprite 7, ...
    // sprites on screen are 01234567
    lda #%00000000
    sta VIC.SPRITE_MSB_X

    lda #150
    sta VIC.SPRITE_0_Y

    lda #(sprite0Data / 64)
    sta Consts.VicBankBase + Consts.ScreenBase + VIC.SPRITE_POINTER_0_OFFSET

                lda #<nmi
                sta $fffa
                lda #>nmi
                sta $fffb
                lda #<irq1
                sta $fffe
                lda #>irq1
                sta $ffff
                lda #$7f
                sta $dc0d       // disable timer
                lda #250
                sta $d012       // set Raster IRQ at line 51
                lda #$1b
                sta $d011
                lda #$81
                sta $dc0e
                lda #$01
                sta $d019       // ack raster IRQ if any
                sta $d01a       // select Raster as a source of VIC IRQ
                cli
                lda #85
                sta $3fff
                jmp *

irq1:           pha
                txa
                pha
                asl $d019
                lda #0        // set 24 lines mode on, screen off
                sta $d011       // y-scroll = 0
                lda #<irq2
                ldx #>irq2
                ldy #51
exitirq:
                sty $d012 
                sta $fffe
                stx $ffff
                lda $dc0d
                pla
                tax
                pla
                
nmi:             rti

irq2:           pha             // IRQ happening @ line 51
                txa
                pha
                asl $d019
                lda #$1b        // set 25 lines mode on
                sta $d011
                lda #<irq1
                ldx #>irq1
                ldy #250
                jmp exitirq


sprite0Data:
    .byte $fe, $56, $33
    .byte $ee, $56, $33
    .byte $3e, $56, $33
    .byte $4e, $56, $33
    .byte $f5, $56, $33
