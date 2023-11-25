// luminance mapping
// jsr fadeStart om 0 naar wit mapping te initialiseren
// jsr fadeStep om naar volgende stap te gaan

// TODO: aanmaken luminance nibble map (256 bytes)
// op basis van for loop en 1x4 shift per 16 shades

// TODO: hoe fade out? achteruit? steepness 255-16 en dan sbc?

BasicUpstart2(start)


start:
		jsr $E544
		jsr fadeStart	// level0
		jsr fadeStep	// level1
		jsr fadeStep	// level2
		jsr fadeStep	// level3
		jsr fadeStep	// level4
		jsr fadeStep	// level5
		jsr fadeStep	// 6
		jsr fadeStep	// 7
		jsr fadeStep	// 8
		jsr fadeStep	// 9
		jsr fadeStep	// 10
		jsr fadeStep	// 11
		jsr fadeStep	// 12
		jsr fadeStep	//13
		jsr fadeStep	//14
		jsr fadeStep	//15
		rts
		
* = $0900
		
fadeStart:
		ldx #15
		lda #0
 fadeStart_1:	sta v_lumindex,x	// 8.8 index
		sta v_lumfrac,x
		dex
		bne fadeStart_1
		// falls into fadeStep
		
fadeStep:
		ldy #15			// y=steepness 15/256
		ldx #0		
 fadeStep_loop:	tya
		clc
		adc v_lumfrac,x		// frac = frac+steepness
		sta v_lumfrac,x
		bcc fadeStep_next
		inc v_lumindex,x	// carry into index
 fadeStep_next:	tya
		clc
		adc #16			// steepness + 16
		tay
		inx
		cpx #16
		bne fadeStep_loop
		jmp debug


// luminance mapper

// te mappen kleuren oplopend in luminance
lijst: .byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
buffer: .fill 256,0
ZP: .byte 0		
		
		ldy #0		// 0..255 offset in dest buffer
		ldx #0		// 0..15 hn counter
		
L2:		txa
		pha		// stack: X
		// hn
		lda lijst,x
		asl
		asl
		asl
		asl
		ldx #0		// 16x
		// A=hn
L1:		and #$f0	// hn only
		ora lijst,x	// hn | ln
		sta buffer,y	// buffer[y] = hn|ln
		iny
		inx
		cpx #16
		bne L1
		
		pla
		tax
		inx
		cpx #16
		bne L2
		rts
		
// --- data

v_lumindex:	.fill 16,0
v_lumfrac:	.fill 16,0


// --- debug
* = $1000

debug:
		ldx #15
 debugnext:	lda v_lumindex,x
		sta $0400+40*5,x
		lda v_lumfrac,x
		sta $0400+40*6,x
		dex
		bpl debugnext
		// plot v_lumindex elke stap
		ldx debugptr
		lda v_lumindex
		sta $0400+40*8,x
		lda v_lumindex+1
		sta $0400+40*9,x
		lda v_lumindex+2
		sta $0400+40*10,x
		lda v_lumindex+3
		sta $0400+40*11,x
		lda v_lumindex+4
		sta $0400+40*12,x
		lda v_lumindex+5
		sta $0400+40*13,x
		lda v_lumindex+6
		sta $0400+40*14,x
		lda v_lumindex+7
		sta $0400+40*15,x
		lda v_lumindex+8
		sta $0400+40*16,x
		lda v_lumindex+9
		sta $0400+40*17,x
		lda v_lumindex+10
		sta $0400+40*18,x
		lda v_lumindex+11
		sta $0400+40*19,x
		lda v_lumindex+12
		sta $0400+40*20,x
		lda v_lumindex+13
		sta $0400+40*21,x
		lda v_lumindex+14
		sta $0400+40*22,x
		lda v_lumindex+15
		sta $0400+40*23,x
		inc debugptr
		rts
	
 debugptr:	.byte 0