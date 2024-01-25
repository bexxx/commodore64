#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"
#import "../../includes/cia2_constants.inc"

BasicUpstart2(main)

main:
			sei
			jsr $ff81 // Clear the screen
			
            lda #VIC.black
			sta VIC.BORDER_COLOR
			sta VIC.SCREEN_COLOR

			lda #VIC.SPRITE_ALL_ENABLE_MASK
			sta VIC.SPRITE_ENABLE
			
            lda #$00  
			sta VIC.SPRITE_DOUBLE_X
            sta VIC.SPRITE_DOUBLE_Y
            sta VIC.SPRITE_BG_PRIORITY

            SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK) 

			ldx #$00
generateSpriteData:    
            lda #$00
			sta $4a00,x //Fill $2000 with zero
			inx
			bne generateSpriteData
			lda #$01    //Create a dot for the sprite starfield
			sta $4a00
			ldx #$00
setsprs:    lda #$28    //Sprite object data from $2000-$2080
			sta $47f8,x
			lda #$01    //All sprites are white
			sta $d027,x
			inx
			cpx #$08    //Do the sprite creation 8 times
			bne setsprs
			
            ldx #$f
positions:	lda postable,x          //Read label postable
			sta starpos,x         //Create data memory for current sprite position
			dex
			bpl positions

			lda #<irq //You should know this bit already //)
			sta $0314
			lda #>irq
			sta $0315
			lda #$00
			sta $d012
			lda #$7f
			sta $dc0d
			lda #$1b
			sta $d011
			lda #$01
			sta $d01a
			cli

            // write y pos once
            ldx #$f
!:
            lda starpos,x // Read virtual memory from starpos (odd number values)
			sta $d000,x     //Write memory to the actual sprite y position
            dex
            dex
            bpl !-

mainloop:	jmp mainloop
			
updateStars:	ldx #$e
xpdloop:
			lda starpos+0,x //Read virtual memory from starpos (odd number values)
			asl
			rol $d010 //increase the screen limit for sprite x position
			sta $d000,x //Write memory to the actual sprite x position
			dex
			dex
			bpl xpdloop
			
movestars:  ldx #$e
moveloop:	lda starpos+0,x //Read from data table (starpos)
			clc
			adc starspeed+0,x
			sta starpos+0,x
			dex // Add 2 to each value of the loop
			dex //
			bpl moveloop
			rts
			
irq:		inc $d019 //You should also know this bit already
			lda #$00
			sta $d012
            
            inc $d021
            inc $d020
            jsr updateStars     //Call label xpdpos for sprite position x expansion
			//jsr movestars   //Call label movestars for virtual sprite movement
            dec $d020
			dec $d021

			jmp $ea31
			
//Data tables for the sprite positions
                             // x    y
postable:	.byte $13,163 //We always keep x as zero, y is changeable
			.byte $01,171
			.byte $26,179
			.byte $17,185
			.byte $09,198
			.byte $04,203
			.byte $26,210
			.byte $05,$f6
			
//Data tables for speed of the moving stars (erm dots)
                             //x     y
starspeed:
	        .byte $ff-$05,$00 //Important. Remember that Y should always be zero. X is changable for
			.byte $ff-$03,$00 //varied speeds of the moving stars. :)
			.byte $ff-$01,$00
			.byte $ff-$04,$00
			.byte $ff-$03,$00
			.byte $ff-$01,$00
			.byte $ff-$07,$00
			.byte $ff-$02,$00

starpos:
    .fill $00, $10
