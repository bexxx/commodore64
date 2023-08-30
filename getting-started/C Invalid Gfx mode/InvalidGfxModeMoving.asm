#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/common.inc"

.const StartLine = 20                           // start must be at the end of a char line

BasicUpstart2(main)

main:

    sei                                         // disable all interrupts
    jsr Kernel.ClearScreen

    ldx #$00
drawCharacters:
.label character = *+1
    lda #$01                                    // draw alphabet on column 0 to fill screen
.label screenTargetLo = *+1
.label screenTargetHi = *+2
    sta $0400
    inx
    cpx #$19                                    // draw on all 25 columns (notice missing lines on bottom)
    beq startNewFrame

    inc character                               // next character
    lda screenTargetLo
    clc
    adc #$28                    
    sta screenTargetLo
    bcc drawCharacters
    inc screenTargetHi
    jmp drawCharacters


startNewFrame:

    BusyWaitForNewScreen()                      // wait for new frame
 
 .label startLine = * + 1 
    lda #StartLine                              // wait for starting line
!:  cmp VIC.CURRENT_RASTERLINE_REG
    bne !-

    inc $d020

    // 3.7.3.6. Invalid text mode (ECM/BMM/MCM=1/0/1)
    // (Extended Color Mode, Bit Map Mode and Multi Color Mode)

// $D011	53265	17	Steuerregister, Einzelbedeutung der Bits (1 = an):
// Bit 7: Bit 8 von $D012, Rasterzeile
// Bit 6: Extended-Color-Modus
// Bit 5: Bitmap-Modus
// Bit 4: Bildausgabe eingeschaltet (Effekt erst beim nächsten Einzelbild)
// Bit 3: 25 Zeilen (sonst 24)
// Bit 2..0: Offset Text/Grafik in Rasterzeilen vom oberen Bildschirmrand (YSCROLL), gilt nicht für Sprites

// $D016	53270	22	Steuerregister, Einzelbedeutung der Bits (1 = an):
// Bit 7..5: unbenutzt
// Bit 4: Multicolor-Modus
// Bit 3: 40 Spalten (an)/38 Spalten (aus)
// Bit 2..0: Offset Text/Grafik in Pixeln vom linken Bildschirmrand (XSCROLL), gilt nicht für Sprites
    lda #%11011011
    sta $d011

    lda #%11111000
    sta $d016

    ldx #20                     // skip n lines on top 
!:  BusyWaitForNextRasterLine()
    dex
    bne !-

    lda #%10011011
    sta $d011

    lda #%11101000
    sta $d016

    dec $d020

    inc startLine
    lda startLine
    cmp #180
    bne next
    lda #StartLine
    sta startLine
next:
    jmp startNewFrame                           // do this forever
