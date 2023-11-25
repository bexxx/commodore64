// basic starter
BasicUpstart2(main)

* = $080d // assembler start address
 
main:
		ldy #$0	// y will be the offset into the lengths and offsets byte array
		ldx #0
loop:
		tya
		pha
		// calc y as offset for start printing *

		lda #11
		clc
		sbc lengths,y
		tay
		
		// calc length of asteriks
		txa
		asl // lengths only stores half of the length excluding the middle *, so multiply by 2
		tax
		inx // add middle * to length

		// the asteriks itself
		lda #$2a
sta1:
		// print as many * as given in lengths
		sta $0400+19-11+5*40,y
		iny // continue writing on the right
		dex 
		bne sta1 // write all *

		pla
		tay

		// increase index in to bytes
		iny	

		lda lengths,y 	// load offset for this line into accumulator
		beq out			// 0 terminated byte sequence
		tax
		
		// go to next line
		lda #40
		clc
		adc sta1+1
		sta sta1+1
		lda #0
		adc sta1+2
		sta sta1+2

		jmp loop	
out:
		rts

lengths:
	.byte 0,1,2,3, 1,3,5,7, 2,4,7,10, 1,1, 0