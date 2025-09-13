.importonce 

.macro irq_set(label, rasterline) {
    irq_set_no_line(label)
    lda #rasterline
    sta $d012
}

.macro irq_set_no_line(label) {
    lda #<label
    sta $fffe
    lda #>label
    sta $ffff
}

.macro irq_wait(rasterLine) {
    .errorif rasterLine > 255, "raster line number > 255, implement a irq_wait_ex instead"
    
    irq_set(next, rasterLine)

    irq_endRaster()                             // restore reg values and return from irq

next:
    irq_save()                                  // stash reg values away
}

.macro irq_save() {
    pha
    txa
    pha
    tya
    pha
}

.macro irq_endRaster() {
    lsr $d019                                   // ack raster irq
    irq_restore()                               // restore reg values and return from irq

    rti
}

.macro irq_restore() {
    pla
    tay
    pla
    tax
    pla
}

.macro delay(pt, frames) {
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
next:
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts
    
done:
    lda #<after
    sta pt
    lda #>after
    sta pt + 1

after:
}

.macro parallel_delay(pt, frames) {
    .errorif (frames > 255), "delay too long, use parallel_long_delay instead"
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts
    
done:
    lda #<after
    sta pt
    lda #>after
    sta pt + 1

after:
}

.macro parallel_long_delay(pt, frames) {
    lda counterHi: #$0
    cmp #>frames
    bne !+
    lda counterLo: #0
    cmp #<frames
    beq done
!:
    inc counterLo
    bne !+
    inc counterHi
!:
    rts

done:
    lda #<after
    sta pt
    lda #>after
    sta pt + 1

after:
}


.macro continue_with(pt, label) {
    lda #<label
    sta pt
    lda #>label
    sta pt + 1
}

.macro delay_repeatable(pt, frames) {
    .errorif (frames > 255), "delay too long, use longdelay_repeatable instead"
    
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
next:
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts
   
done:
    lda #0
    sta counter
}

.macro longdelay_repeatable(pt, frames) {
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
    lda #0
    sta counterLo
    sta counterHi
next:
    lda counterHi: #$0
    cmp #>frames
    bne !+
    lda counterLo: #0
    cmp #frames
    beq done
!:
    inc counterLo
    bne !+
    inc counterHi
!:
    rts
   
done:
}

.macro delay_autorepeat(pt, frames) {
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
    lda #0
    sta counter
next:
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts

done:
    lda #0
    sta counter
}

.macro stabilizeIrq() {
start:
    inc $d012
    irq_set_no_line(secondStabilizerIrq)
    lsr $d019
    tsx
    cli
    nop(20)

secondStabilizerIrq:
    // get here on 9-10
    txs                                         // 2, 11 or 12
    pause_loop #44                              // 44, 55 or 56
    lda $d012                                   // 4,  59 or 60
    cmp $d012                                   // 4,  63 or 01
    beq !+                                      // 2 or 3, 03 of raster irq line + 2
!:
}

// from csdb
.macro ensureImmediateArgument(arg) {
	.if (arg.getType()!=AT_IMMEDIATE)	
        .error "The argument must be immediate!" 
}

.macro nop(value) {
	.fill value, NOP
}

// from csdb
.pseudocommand pause_loop cycles {
	:ensureImmediateArgument(cycles)
	
    .var x = floor(cycles.getValue())
	.if (x < 2) 
        .error "Cant make a pause on " + x + " cycles"

	// Make a delay loop
	.if ( x >= 11) {
		.const cfirst = 6	// cycles for first loop
		.const cextra = 5	// cycles for extra loops
		.var noOfLoops = 1+floor([x-cfirst]/cextra)
		.eval x = x - cfirst - [noOfLoops-1]*cextra
		.if (x==1){
			.eval x=x+cextra
			.eval noOfLoops--	
		}
		ldx #noOfLoops
!:		dex
		bne !-
	}

	// Take care of odd cyclecount	
	.if ([x&1]==1) {
		bit $00
		.eval x=x-3
	}	
	
	// Take care of the rest
	.if (x>0)
		nop(x/2)
}