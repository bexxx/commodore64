#import "../../includes/vic_constants.inc"
#import "../../includes/cia1_constants.inc"
#import "../../includes/internals.inc"
#import "../../includes/zeropage.inc"
#import "../../includes/common.inc"

.var music = LoadSid("1984-F.sid")

BasicUpstart2(main)

.segment Default "main"
main:
    sei

    ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2000_MASK, VIC.SELECT_CHARSET_AT_2800_MASK)

    ldx #0
    ldx #0
	ldy #0
	lda #music.startSong - 1
    jsr music.init

    lda #BLACK
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    lda #BLUE
    sta VIC.TXT_COLOUR_1
    lda #LIGHT_BLUE
    sta VIC.TXT_COLOUR_2

    ldx #$00
    lda #CYAN_mc
!:  sta $d800,x
    sta $d900,x
    inx
    bne !-

    lda VIC.CONTR_REG
    ora #VIC.ENABLE_MULTICOLOR_MASK
    sta VIC.CONTR_REG

    lda #<interruptHandler                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamLo  // store to RAM interrupt handler
    lda #>interruptHandler                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRamHi  // store to RAM interrupt handler

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    lda #$ff                                    // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure

    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load current value of VIC interrupt control register
    sta VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    cli                                         // allow interrupts to happen again

  !:
    jmp !-

.segment Default "raster interrupt"             // shows the bytes for this code, when using -showmem
                             
interruptHandler:
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // (2 cycles) ack raster interrupt to enable 2nd one
    sta VIC.INTERRUPT_EVENT                     // (4 cycles) ack interrupt

    jsr music.play 

    ReturnFromInterrupt()

*=music.location "music" // $1000
.fill music.size, music.getData(i)
  
* = $2000 "screen data"
.import binary "screen.bin"

* = $2800 "charset"
.import binary "font.bin"
