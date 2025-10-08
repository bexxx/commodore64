// taken from https://codebase64.c64.org/doku.php?id=base:the_polling_method

BasicUpstart2(main)

.const startLine = $28

main:
    cli
    lda #$7f
    sta $dc0d
    sta $dd0d
    jsr stabilize
    inc $d020
nop
nop
nop
nop
    dec $d020
    jmp main   

stabilize:
    ldx #startLine
!:  
    cpx $d012           // 4: 4
    bne !-              // 2/3: 7

    // execution timing by opcode: 
    // https://codebase64.c64.org/doku.php?id=base:6510_instruction_timing&s[]=opcode
    // the earliest time when the cpx has read the row number in the last of the 4 cycles.
    // this means the longest execution is 
    // bne (3) + cpx (4) + bne (2) = 9
    // the shortest moment is before the cpx reads the value, which is in cycle 3 of cpx 
    // and the execution looks like 
    // last read cycles of cpx (1) + bne (2) = 3
    // this means the jitter is between 3 and 9
    // the main idea of the following code is to use the knowledge of the current jitter and
    // divide it by half with each further line

    // so here we want now to add 63 - (9 - 3 + 1) / 2 cycles and check again then we would know
    // we had 3-5 or 6-9 jitter
    jsr cycles_43       // 6 + 43:  [52-58]
    bit $ea             // 3:       [55-61]
    nop                 // 2:       [57-63]
    cpx $d012           // 4:       [61-67]
    beq skip1           // 2,3:
    // too early        // 2:       [63-69]             we could be in 63-65 now, jitter 1-3 cycles
    nop                 // 2:       [ 2- 5]
    nop                 // 2:       [ 4- 7]

skip1:    
    jsr cycles_43       // 49:      [53-56]
    bit $ea             //  3:      [56-59]
    nop                 //  2:      [58-61]
    cpx $d012           //  4:      [62-65]
    beq skip2           // 2,3
    // too early        //  2:      [ 1- 2]
    bit $ea             //  3:      [ 4- 5]


skip2:    
    jsr cycles_43       // 49:      [53-55]
    nop                 //  2:      [55-57]
    nop                 //  2:      [59-61]
    nop                 //  2:      [61-63]
    cpx $d012           //  4:      []
    bne onecycle
onecycle: 
.break
rts

.break
cycles_43:
    ldy #$06            // 2:            2
lp2:
    dey                 // 2:6*2=12     14
    bne lp2             // 3:5*3=15     29
                        // 2:           31   
    inx                 // 2:           33
    nop                 // 2:           35
    nop                 // 2:           37
    rts                 // 6:           43