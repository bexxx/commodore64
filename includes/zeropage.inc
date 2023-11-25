#importonce 

.namespace Zeropage
{
    .label PORT_REG = $01       // Bit 0 - LORAM: Configures RAM or ROM at $A000-$BFFF (see bankswitching)
                                // Bit 1 - HIRAM: Configures RAM or ROM at $E000-$FFFF (see bankswitching)
                                // Bit 2 - CHAREN: Configures I/O or ROM at $D000-$DFFF (see bankswitching)
                                // Bit 3 - Cassette Data Output Line (Datasette)
                                // Bit 4 - Cassette Switch Sense; 1 = Switch Closed
                                // Bit 5 - Cassette Motor Control; 0 = On, 1 = Off
                                // Bit 6 - Undefined
                                // Bit 7 - Undefined
                                // Note: This reg uses low active bits (0 = enable, 1 = disable)
    .label ENABLE_ROM_MASK = %10

    .label ENABLE_CHAREN_MASK = ~%00000100                  // active low! Use and to set
    .label ENABLE_CHAREN_CLEAR_MASK = ~ENABLE_CHAREN_MASK   // active low! Use ora to clear
    .label ENABLE_LORAM_MASK = ~%00000001
    .label ENABLE_HIRAM_MASK = ~%00000010

    .label Unused_02 = $02
    .label Unused_FB = $FB
    .label Unused_FC = $FC
    .label Unused_FD = $FD
    .label Unused_FE = $FE
}

.macro SetMemoryConfig(mask) {
    lda #mask
    sta Zeropage.PORT_REG 
}

.macro SetFullRamWithIoConfig() {
    SetMemoryConfig(%00110101)
}