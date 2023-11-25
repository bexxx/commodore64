#import "../../includes/vic_constants.inc"
#import "../../includes/cia2_constants.inc"

.namespace ZeroPage {
    .label frameCounter = $2
    .label sceneCounter= $3
}

.var waitFrameCount = 2
.var screenBufferStart = $4000

BasicUpstart2(main)

.segment Default "main"

main:
    jsr copyCharRom
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK1_MASK)
    jsr copyScreenRam
    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2000_MASK, VIC.SELECT_CHARSET_AT_0000_MASK)
    
    lda #0
    sta ZeroPage.sceneCounter

.segment Default "Merge down"

startNewCollapseFrame:
    jsr waitNFrames

    inc VIC.BORDER_COLOR
    ldy #0
collapseByOne:
    .for(var chunk=0; chunk<8; chunk++) {
        .for(var row=7; row>0; row--) {
            .if (row==7) {
    lda screenBufferStart+chunk*$100+row-1,y
    ora screenBufferStart+chunk*$100+row,y
    sta screenBufferStart+chunk*$100+row,y
            } else {
    lda screenBufferStart+chunk*$100+row-1,y
    sta screenBufferStart+chunk*$100+row,y
            }
        }

    lda #0
    sta screenBufferStart+chunk*$100+0,y
    }

    tya
    clc
    adc #8
    bcs doneMergeByOne
    tay
    jmp collapseByOne

doneMergeByOne:
    dec VIC.BORDER_COLOR

    inc ZeroPage.sceneCounter
    lda ZeroPage.sceneCounter
    cmp #8
    beq !+
    jmp startNewCollapseFrame

!:

    inc VIC.BORDER_COLOR
    ldy #0
centerByOne:
    .for(var chunk=0; chunk<8; chunk++) {
    lda screenBufferStart+chunk*$100,y
    tax
    clc
    and #$f0
    rol

    sta screenBufferStart+chunk*$100,y
    }






waitforever:
    jmp waitforever

.segment Default "Functions"

// make charset visible at $d000 (set charrom bit to 0)
// copy charset from $d000 (ROM) to $4000
copyCharRom: {
    sei 

    ldx #$08    // we loop 8 times (8x255 = 2Kb)
    lda $01     // clear charrom bit (active low)
    and #%11111011
    sta $01     // ...at $D000 by storing %00110011 into location $01

    lda #$d0    // load high byte of $D000    
    sta $fc     // store it in a free location we use as vector
    lda #$40
    sta $fe
    ldy #$00    // init counter with 0
    sty $fb     // store it as low byte in the $FB/$FC vector
    sty $fd

!copyLoop:
    lda ($fb),y // read byte from vector stored in $fb/$fc
    sta ($fd),y 
    iny         // do this 255 times...
    bne !copyLoop-    // ..for low byte $00 to $FF
    inc $fc     // when we passed $FF increase high byte...
    inc $fe
    dex         // ... and decrease X by one before restart
    bne !copyLoop-    // We repeat this until X becomes Zero

    lda $01    // switch in I/O mapped registers again...
    ora #%00000100
    sta $01     // ... with %00110111 so CPU can see them

    cli         // turn off interrupt disable flag
    
    rts
}

copyScreenRam: {
    ldx #0
!copyLoop:
    // copy 2k screen ram unrolled 4x 256 bytes
    .var sourceBufferStart = $0400
    .var targetBufferStart = $6000
.for(var i=0; i<4; i++) {    
    lda sourceBufferStart+i*$100,x
    sta targetBufferStart+i*$100,x
 }
    inx
    bne !copyLoop-

    rts
}

// takes number of frames in $02
waitNFrames: {
    lda #waitFrameCount
    sta ZeroPage.frameCounter

waitHighBitRasterLine:
    lda VIC.SCREEN_CONTROL_REG
    and #VIC.RASTERLINE_BIT9_MASK
    bne waitHighBitRasterLine
waitRasterLine:
    lda VIC.CURRENT_RASTERLINE_REG
    cmp #50 // pick a raster line
    bne waitRasterLine
    dec ZeroPage.frameCounter
    bne waitHighBitRasterLine

    rts
}

flowToMiddleTable:
flowToMiddleLeftTable:
    .byte %00000000     // %00000000
    .byte %00000010     // %00000001
    .byte %00000100     // %00000010
    .byte %00000110     // %00000011
    .byte %00001000     // %00000100
    .byte %00000110     // %00000101
    .byte %00000101     // %00000110
    .byte %00001110     // %00000111
    .byte %00001000     // %00001000
    .byte %00001010     // %00001001
    .byte %00001100     // %00001010
    .byte %00001101     // %00001011
    .byte %00001000     // %00001100
    .byte %00001110     // %00001101
    .byte %00001100     // %00001110
    .byte %00001110     // %00001111
    
    .fill $ff-2*$f, $0
    
    .byte %00000000     // %00000000
    .byte %00000000     // %00000001
    .byte %00000000     // %00000010
    .byte %00000000     // %00000011
    .byte %00000000     // %00000100
    .byte %00000000     // %00000101
    .byte %00000000     // %00000110
    .byte %00000000     // %00000111
    .byte %00000000     // %00001000
    .byte %00000000     // %00001001
    .byte %00000000     // %00001010
    .byte %00000000     // %00001011
    .byte %00000000     // %00001100
    .byte %00000000     // %00001101
    .byte %00000000     // %00001110
    .byte %00000000     // %00001111
