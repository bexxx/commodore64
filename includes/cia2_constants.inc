.namespace CIA2
{
    .label DATA_PORT_A = $dd00

    .label VIC_SELECT_BANK3_MASK = %00000000 // 0: Bank 3: $C000-$FFFF, 49152-65535
    .label VIC_SELECT_BANK2_MASK = %00000001 // 1: Bank 2: $8000-$BFFF, 32768-49151
    .label VIC_SELECT_BANK1_MASK = %00000010 // 2: Bank 1: $4000-$7FFF, 16384-32767
    .label VIC_SELECT_BANK0_MASK = %00000011 // 3: Bank 0: $0000-$3FFF, 0-16383 (Standard)

    .label VIC_SELECT_BANK_CLEAR_MASK = ~%11 // bits 1-0 for bank selection

    .label INTERRUPT_CONTROL_REG = $dd0d
    .label CLEAR_ALL_INTERRUPT_SOURCES = %01111111
}

.macro SelectVicMemoryBank(BankMask) {
    lda CIA2.DATA_PORT_A 
    and #CIA2.VIC_SELECT_BANK_CLEAR_MASK
    ora #BankMask
    sta CIA2.DATA_PORT_A
}
