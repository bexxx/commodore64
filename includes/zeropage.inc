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
    .label ENABLE_ROM_MASK = %10
}