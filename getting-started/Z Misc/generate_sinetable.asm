.const sine = $0200
.const amplitude = 150
.const mul1 = 4
.const mul2 = 5 

BasicUpstart2(main)

main:
    jsr make_sinus

    ldy #0
!:  lda sine,y
    ldx #amplitude
    jsr multiply
    ror             // +/-63 amplitude
    sta sine,y
    iny
    bne !-

    rts

make_sinus:
        ldx #0              // nasty routine, 256b sinus in 96b code+data
        ldy #0
mksin1: lda stable,y        // feel free to find out how it works
        beq _dtok           // create curve until 0
        pha
        and #15             // extract repeat counter
        sta 2
        pla
        lsr
        lsr
        lsr
        lsr
!:      sta $100,x         // temporarily fill stack to delta-table
        inx
        dec 2
        bne !-
        iny                 // next data
        bne mksin1          // branch always as data is very small
_dtok:  ldy #0
        ldx #64
        lda #128            // middle-value
mksin2: sta sine,y          // render positive rising curvee
        sta sine+64,x       // falling curve backwards
        pha
        and #$7f
        sta 2               // save current level
        lda #128
        sec
        sbc 2               // flip to negative level
        sta sine+128,y      // and render negative curves
        sta sine+192,x
        pla                 // restore original current value
        clc
        adc $0100,y         // apply delta
        iny                 // iterate until done.
        dex
        bpl mksin2
        rts

multiply:
        sta mul1            // multiply value mul1 by value mul2 
        stx mul2
        lda #0
        ldx #8
        clc
!:      bcc !+
        clc 
        adc mul2
!:      ror
        ror mul1
        dex
        bpl !--
        // ldx mul1        ; result in accu+xr
        rts  

stable:
  .byte $34,$41,$3b,$21,$34,$21,$32,$21,$31,$21,$31,$22,$31,$29,$11
  .byte $22,$12,$21,$13,$21,$12,$01,$13,$01,$11,$02,$11,$03,0