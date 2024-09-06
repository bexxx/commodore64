#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/internals.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/zeropage.inc"
#import "../../../commodore64/includes/cia1_constants.inc"
#import "../../../commodore64/includes/cia2_constants.inc"
 
// use d020 colors to see raster timing
//#define TIMING

// assemble as stand-alone or to be loaded as a part of a demo
//#define integrated

#if !integrated
    BasicUpstart2(main)
#endif

.namespace Configuration {
    .label VIC_Bank = 0
    .label ScreenRamOffset = $2400 
    .label ScreenRamStart = VIC_Bank * $4000 + ScreenRamOffset
    .label CharsetScrollerOffset = $3000
    .label CharsetScrollerStart = VIC_Bank * $4000 + CharsetScrollerOffset
    .label CharsetBarsOffset = $3800
    .label CharsetBarsStart = VIC_Bank * $4000 + CharsetBarsOffset 

    .label IrqTestbildRasterLine = 0                // irq to keep the test sound ringing
    .label IrqMotiveRasterLine = 1                  // irq to write color ram before display of chars starts
    .label IrqHeadlineRasterLine = 90               // modify headline message and colors for next frame (after display)
    .label IrqMusicRasterLine = 180                 // music irq in middle of screen, can move around if needed
    .label IrqBarsRasterLine = 251                  // modify charset after screen was displayed
    .label IrqFadeoutRasterLine = 250               // fade petscii after screen was displayed
    .label IrqScrollerRasterLine = ($33 + 23*8 - 1) // switch xscroll 

    .label startAddressCharsetScroller = $3000
    .label startAddressCharsetBars = $3800
    .label startAddressZoomedBuffer = $4000
    .label startAddressCode = $6900

    .label TextBufferOffsetScroller = (Configuration.ScreenRamStart + 23*40)
    .label TextBufferOffsetHeadlines = (Configuration.ScreenRamStart + 0*40)
    .label ControlCommandBoundary = $f7                     // value before speed bytes. speed byte
                                                            // this value will be used to add or sub from xscroll
    .label ScrollSpeed = 3
    .label motiveCount = 20

    .label KrillLoaderResidentAddress = $cb00
    .label TestBildIrqAddress = $bf40
    .label BarsWidth = 20
}

.namespace Phases {
    .label Phase_DisplayMessage = 0
    .label Phase_FadeOutMessage = 1
    .label Phase_FadeInLetter = 2

    .label MusicPhase_Setup = 0
    .label MusicPhase_Greetings = 1
    .label MusicPhase_Fadeout = 2
    .label MusicPhase_VolumeDown = 3
    .label MusicPhase_Testbild = 4
}

.var music = LoadSid("sonic-sofa_dancer.sid")

* = Configuration.startAddressCode "Setup code"
main:
    BusyWaitForNewScreen()    

#if !integrated
    jsr disableDisplay
#endif 

#if !integrated
    // disable kernel rom
    lda #$35
    sta Zeropage.PORT_REG

    lda #CIA1.CLEAR_ALL_INTERRUPT_SOURCES
    sta CIA1.INTERRUPT_CONTROL_REG              // disable timer interrupt, no rom better no timer
    lda CIA1.INTERRUPT_CONTROL_REG              // confirm interrupt, just to be sure    

    lda #<interruptMusic
    sta Internals.InterruptHandlerPointerRomLo
    lda #>interruptMusic
    sta Internals.InterruptHandlerPointerRomHi
    lda #Configuration.IrqMusicRasterLine
    sta VIC.CURRENT_RASTERLINE_REG    
    lda VIC.SCREEN_CONTROL_REG                  // clear high bit of raster interrupt
    and #VIC.RASTERLINE_BIT9_CLEAR_MASK         // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register
    
    lda #VIC.ENABLE_RASTER_INTERRUPT_MASK       // load mask with bit for raster irq
    sta VIC.INTERRUPT_ENABLE                    // store to this register acks irq associated with bits

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
#else 
    lda #%00001011                              // text mode, hires, 40 cols, default
    sta VIC.SCREEN_CONTROL_REG
#endif 

    // fill first five rows with spaces (== empty, default charset at $1000)
    ldx #39   
    lda #32
!:      .for(var i = 0; i < 5; i++)
    {
        sta Configuration.ScreenRamStart + i * 40,x
    }    
    dex
    bpl !-

    // draw columns of same letters on screen for dynamically created charset
    ldx #39   
!:  txa
    clc
    adc #21         // chars start on column 0 with char 21 (20 is bar width) to allow bar to completely disappear
    .for(var i = 5; i < 22; i++)
    {
        sta Configuration.ScreenRamStart + i * 40,x
    }    
    dex
    bpl !-

    // clear bar charset with 0s
    ldx #0
    txa
!:  
    .for(var i = 0; i < 8; i++)
    {
        sta Configuration.CharsetBarsStart + i * $100,x
    }
    dex
    bne !-

    // init color ram with black on first rows for headline
    lda #BLACK
    ldx #0
!:  
    .for(var i = 0; i < 4; i++)
    {
        sta VIC.ColorRamBase + i * $100,x
    }
    dex
    bne !-

    ldx #2*40        
!:  lda #WHITE
    sta $d800 + 23*40,x
    lda #(' ' * 4)
    sta Configuration.ScreenRamStart + 23*40,x
    dex
    bpl !-

#if !integrated
    lda #0
    jsr music.init
#endif

#if integrated
    lda #$03
    sta $dd00
#else 
    SelectVicMemoryBank(CIA2.VIC_SELECT_BANK0_MASK)
#endif
    
    // switch to new char set
    lda #%10011110          // VIC.SELECT_SCREENBUFFER_AT_2400_MASK, VIC.SELECT_CHARSET_AT_3800_MASK
    sta VIC.GRAPHICS_POINTER
    
    lda #BLACK
    sta VIC.BORDER_COLOR
    sta VIC.SCREEN_COLOR

    lda #WHITE
    sta currentScrolltextColor

    jsr generateShiftedBarBytes
    jsr generateBarsInCharset
    jsr generateZoomedColorRamData

    // setup sprites

    // stretch all sprites
    lda #%11000000
    sta VIC.SPRITE_DOUBLE_X
    sta VIC.SPRITE_DOUBLE_Y

    ldx #$0
    stx VIC.SPRITE_HIRES

    lda #RED
    sta VIC.SPRITE_SOLID_0
    sta VIC.SPRITE_SOLID_1
    sta VIC.SPRITE_SOLID_2
    sta VIC.SPRITE_SOLID_3
    sta VIC.SPRITE_SOLID_4
    sta VIC.SPRITE_SOLID_5
    lda #WHITE
    sta VIC.SPRITE_SOLID_6
    sta VIC.SPRITE_SOLID_7

    lda #0
    sta VIC.SPRITE_MULTICOLOR_1
    lda #1
    sta VIC.SPRITE_MULTICOLOR_2

    // position sprites on top left for headline, no need to bother with MSB for x
    lda #<(24 + 0 * 24)
    sta VIC.SPRITE_0_X
    lda #<(24 + 1 * 24)
    sta VIC.SPRITE_1_X
    lda #<(24 + 2 * 24)
    sta VIC.SPRITE_2_X

    lda #<(24 + 0 * 24)
    sta VIC.SPRITE_3_X
    sta VIC.SPRITE_6_X

    lda #<(24 + 1 * 24)
    sta VIC.SPRITE_4_X
    sta VIC.SPRITE_7_X
    lda #<(24 + 2 * 24)
    sta VIC.SPRITE_5_X

    lda #49
    sta VIC.SPRITE_0_Y
    sta VIC.SPRITE_1_Y
    sta VIC.SPRITE_2_Y
    sta VIC.SPRITE_6_Y
    sta VIC.SPRITE_7_Y
    lda #49+21
    sta VIC.SPRITE_3_Y
    sta VIC.SPRITE_4_Y
    sta VIC.SPRITE_5_Y

    lda #%11111111
	sta VIC.SPRITE_ENABLE
    lda #%00000000
    sta VIC.SPRITE_MSB_X

    ldx #(sprite_image_0 / 64)
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_0_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_1_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_2_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_3_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_4_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_5_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_6_OFFSET
    inx
    stx Configuration.ScreenRamStart + VIC.SPRITE_POINTER_7_OFFSET
    
    lda #<newsAlerts
    sta scrollTextPointerLo
    lda #>newsAlerts
    sta scrollTextPointerHi

    lda #Phases.MusicPhase_Greetings
    sta interruptMusic.currentMusicPhase

    lda #%00011011                              // clear or set depending on desired raster line, here clear
    sta VIC.SCREEN_CONTROL_REG                  // write back to VIC control register

#if integrated
    ldx #<filename
    ldy #>filename
    jsr Configuration.KrillLoaderResidentAddress
#endif

waitForever: jmp waitForever

#if integrated
filename:
    .encoding "petscii_upper"
    .text "B";.byte $0
    .encoding "screencode_mixed"
#endif 

generateShiftedBarBytes: {
    lda #<barCharsetDefinition
    sta Zeropage.Unused_FB
    lda #>barCharsetDefinition
    sta Zeropage.Unused_FC

    lda #<barCharsetDefinionShifted
    sta Zeropage.Unused_FD
    lda #>barCharsetDefinionShifted
    sta Zeropage.Unused_FE

    // shift bar bytes by 1 pixel to the right, make a total of 0-7=8 pixel shifts
    ldx #6
loopBars:
    ldy #0
    clc
    .for(var i = 0; i < Configuration.BarsWidth; i++)
    {
        lda (Zeropage.Unused_FB),y
        ror
        sta (Zeropage.Unused_FD),y
        iny
    }
    dex
    bmi doneShifting

    lda Zeropage.Unused_FB
    clc
    adc #Configuration.BarsWidth // # total chars of the bars
    sta Zeropage.Unused_FB
    bcc !noPageInc+
    inc Zeropage.Unused_FC
!noPageInc:
    lda Zeropage.Unused_FD
    clc
    adc #Configuration.BarsWidth
    sta Zeropage.Unused_FD
    bcc !noPageInc+
    inc Zeropage.Unused_FE
!noPageInc:
    jmp loopBars

doneShifting:
    rts
}

generateBarsInCharset: {
loopShiftedBars:
.label charsetCounter = * + 1
    ldy #$ff
    iny
    cpy #8
    beq done
    sty charsetCounter

    lda shiftedBarCharsStartLo,y
    sta targetCharsetAddressLo
    lda shiftedBarCharsStartHi,y
    sta targetCharsetAddressHi

loopShiftedBar:
    ldy #$0
loopBarCharacter:
.label sourceBarByteAddressLo = * + 1
.label sourceBarByteAddressHi = * + 2
    lda barCharsetDefinition,y
    ldx #7
loopBarCharacterBytes:
.label targetCharsetAddressLo = * + 1
.label targetCharsetAddressHi = * + 2
    sta $dead,x
    dex
    bpl loopBarCharacterBytes

    lda targetCharsetAddressLo
    clc
    adc #8
    sta targetCharsetAddressLo
    bcc !+
    inc targetCharsetAddressHi
!:
    iny
    cpy #Configuration.BarsWidth
    bne loopBarCharacter

    lda sourceBarByteAddressLo
    clc
    adc #Configuration.BarsWidth
    sta sourceBarByteAddressLo
    bcc loopShiftedBars
    inc sourceBarByteAddressHi
    jmp loopShiftedBars

done:
    rts
}

generateZoomedColorRamData: {
    // loop as often as we have icons
.label currentIcon = * + 1
    ldx #$0   
    jsr zoomMotiveChars

    ldx currentIcon
    inx
    cpx #Configuration.motiveCount
    beq !+
    stx currentIcon
    jmp generateZoomedColorRamData
!:
    rts
}

// the music irq is the main driver for states in this part. Here most of the state machine
// is updated and read to setup the irqs. E.g. the phases setup and greetings are different, same for 
// volume fading and slackers logo color fading. 
.align $100
.segment Default "Raster IRQ music"
interruptMusic: {
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

#if TIMING
    lda #GREEN
    sta VIC.BORDER_COLOR
#endif

    // once the test tone was setup, we should not call play any more.
    .label skipMusicPlay = * + 1
    lda #0
    bne !+
    jsr music.play
!:
#if TIMING
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif 

.label currentMusicPhase = * + 1
    lda #Phases.MusicPhase_Setup
    cmp #Phases.MusicPhase_Setup
    beq exitMusicInterrupt  // not complete, just ack the irq and check again next frame

    cmp #Phases.MusicPhase_Greetings
    beq configureIrqsDuringGreetings  // not complete, just ack the irq and check again next frame
    
    cmp #Phases.MusicPhase_Fadeout
    beq configureIrqsDuringFadeout  // not complete, just ack the irq and check again next frame
    
    cmp #Phases.MusicPhase_VolumeDown
    beq configureIrqsDuringVolumeDown  // not complete, just ack the irq and check again next frame
    
    cmp #Phases.MusicPhase_Testbild
    beq configureIrqsDuringTestbild  // not complete, just ack the irq and check again next frame

    // this should never happen. if it does, the debugger will point to this address ;)
!:  jmp !-

configureIrqsDuringGreetings:
    lda #<interruptScroller
    sta Internals.InterruptHandlerPointerRomLo
    lda #>interruptScroller
    sta Internals.InterruptHandlerPointerRomHi
    lda #Configuration.IrqScrollerRasterLine
    sta VIC.CURRENT_RASTERLINE_REG
    jmp exitMusicInterrupt

configureIrqsDuringFadeout:
    lda #<interruptFadeout
    sta Internals.InterruptHandlerPointerRomLo
    lda #>interruptFadeout
    sta Internals.InterruptHandlerPointerRomHi
    lda #Configuration.IrqFadeoutRasterLine
    sta VIC.CURRENT_RASTERLINE_REG
    jmp exitMusicInterrupt

configureIrqsDuringTestbild:
    lda #<(Configuration.TestBildIrqAddress)
    sta Internals.InterruptHandlerPointerRomLo
    lda #>(Configuration.TestBildIrqAddress)
    sta Internals.InterruptHandlerPointerRomHi
    lda #Configuration.IrqTestbildRasterLine
    sta VIC.CURRENT_RASTERLINE_REG
    jmp exitMusicInterrupt

configureIrqsDuringVolumeDown:
    jsr doTestbildSoundSetup
    jsr doVolumeFade
    jmp exitMusicInterrupt
    
exitMusicInterrupt:

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack

    rti
}

doTestbildSoundSetup:
.label doTestbildSetup = * + 1
    ldx #0
   beq !+
                    lda     #$04                    //volume
                       sta     $d418
                       lda     #$1f                    //ADSR for all voices
                       sta     $d405
                       sta     $d40c
                       sta     $d413
                       lda     #$fc
                       sta     $d406
                       sta     $d40d
                       sta     $d414
                       lda     #$23                    //frequency hi byte all voices
                       sta     $d401
                       sta     $d408
                       sta     $d40f
                       lda     #$84                    //frequency lo byte all voices
                       sta     $d400
                       sta     $d407
                       sta     $d40e
        lda #Phases.MusicPhase_Testbild
        sta interruptMusic.currentMusicPhase
        inc interruptMusic.skipMusicPlay
        dec doTestbildSetup
!:    rts

doVolumeFade:
                                                        //initial delay (testing only)
dly_0:                   lda     #$8
                        beq     mfd_act
                                                        //decrease delay
                        dec     dly_0+$01
                        bne     !+
                                                        //activate music fade
                        inc     mfd_act+$01    


                                                        //check if music fade is active
mfd_act:                 lda     #$00
                        beq     !+     
                                                        //delay between fade steps by A frames
mfd_dly:                 lda     #$10
                                                        //decrease delay
                        dec     mfd_dly+$01
                        bne     !+
                                                        //restore delay
                        lda     #$10
                        sta     mfd_dly+$01
                                                        //decrease volume by 1 in player routine
                        dec     $098c

                        bne     !+ 
                                                        //turn off music fade if volume has reached 0
                        dec     mfd_act+$01       
                        inc     doTestbildSetup
!:
    rts

.segment Default "Raster IRQ fadeout"
interruptFadeout: {
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

#if TIMING
    lda #LIGHT_RED
    sta VIC.BORDER_COLOR
#endif 


                                                        //logo
                        ldx     #$c8
sms_sps_lp0:                        
                        lda     fadeoutScreen-$01,x
                        sta     Configuration.ScreenRamStart+$13f,x
                        dex
                        bne     sms_sps_lp0     
                                                        //presents
                        ldx     #$0b
sms_sps_lp1:                        
                        lda     fadeoutScreenPresents,x        //    <=ANPASSEN, DASS ES "WILL RETURN" KOMPLETT KOPIERT
                        sta     Configuration.ScreenRamStart+$2b8-40-1,x
                        dex
                        bpl     sms_sps_lp1
                                                        //drip
                        //lda     #$22
                        //sta     Configuration.ScreenRamStart+$21f
                        //lda     #$2e
                        //sta     Configuration.ScreenRamStart+$247  

//-----------------------------------------------------------------------------------------------------------------------------------------------------------
//color logo "Slackers"

//>> DEAKTVIERT SICH SELBST WENN FERTIG UND AKTIVIERT "//color "presents" and drip" (nachfolgende Routine)

sps_cl_lg:

sps_cl_lg_act:           lda     #$01
                        beq     sps_cl_lg_e
                                                        //handle wait
sps_cl_lg_dly:           lda     #$28
                        beq     sps_cl_lg_ndx
                        
                        dec     sps_cl_lg_dly+$01
                        
                        bne     sps_cl_lg_e                        
                                                        //bring in the color information 1 cell at a time
                        
sps_cl_lg_ndx:           ldx     #$27
sps_cl_lg_lp:                        
                        lda     fadeoutColor+$000,x
                        sta     VIC.ColorRamBase+$140,x
                        lda     fadeoutColor+$028,x
                        sta     VIC.ColorRamBase+$168,x
                        lda     fadeoutColor+$050,x
                        sta     VIC.ColorRamBase+$190,x
                        lda     fadeoutColor+$078,x
                        sta     VIC.ColorRamBase+$1b8,x//
                        lda     fadeoutColor+$0a0,x
                        sta     VIC.ColorRamBase+$1e0,x 

                        dex
                        bpl     sps_cl_10
                                                        //deactivate part         
                        dec     sps_cl_lg_act+$01
                                                        //activate color logo part
                        inc     sps_cl_ps_act+$01
sps_cl_10:
                                                        //set new index
                        stx     sps_cl_lg_ndx+$01     

sps_cl_lg_e:

//-----------------------------------------------------------------------------------------------------------------------------------------------------------
//color "presents" and drip

//>> DEAKTVIERT SICH SELBST WENN FERTIG UND AKTIVIERT "wait and fade out" (nachfolgende routine)

sps_cl_ps:
                                                        //check if active
sps_cl_ps_act:           lda     #$00
                        beq     sps_cl_ps_e

                                                        //color text in 4 frames
sps_cl_ps_ndx:           ldx     #$04
                        bne     sps_cl_ps_10
                                                        //deactivate part
                        dec     sps_cl_ps_act+$01
                                                        //activate wait & fade out
                        inc     wtfd_act+$01
                                                        //set drip
                                                        //first drop of drip
//                        lda     #$e8
//                        sta     Configuration.ScreenRamStart+$1f7
//                        lda     #$0b                        
//                        sta     VIC.ColorRamBase+$1f7
//                        sta     VIC.ColorRamBase+$227
//                        sta     VIC.ColorRamBase+$247
                        
                        bne     sps_cl_ps_99
sps_cl_ps_10:											//<= AB HIER ANPASSEN, DASS ALLE "WILL RETURN"-CHARS GEFÄRBT WERDEN							
                        cpx     #$04
                        bne     sps_cl_ps_20
                                                        //set white letters
                        lda     #$01
                        sta     VIC.ColorRamBase+$2bc-40
                        sta     VIC.ColorRamBase+$2bd-40
                        sta     VIC.ColorRamBase+$2be-40
                        
                        bne     sps_cl_ps_99
sps_cl_ps_20:
                        cpx     #$03
                        bne     sps_cl_ps_30
                                                        //set light grey letters
                        lda     #$0f
                        sta     VIC.ColorRamBase+$2bb-40
                        sta     VIC.ColorRamBase+$2bf-40
                        
                        bne     sps_cl_ps_99
sps_cl_ps_30:
                        cpx     #$02
                        bne     sps_cl_ps_40
                                                        //set grey letters
                        lda     #$0c            
                        sta     VIC.ColorRamBase+$2b9-40
                        sta     VIC.ColorRamBase+$2ba-40
                        sta     VIC.ColorRamBase+$2c0-40
                        sta     VIC.ColorRamBase+$2c1-40

                        bne     sps_cl_ps_99
sps_cl_ps_40:
                                                        //set dark grey letter
                        lda     #$0b
                        sta     VIC.ColorRamBase+$2b7-40
                        sta     VIC.ColorRamBase+$2b8-40
                       // sta     VIC.ColorRamBase+$2b9-40
                        //sta     VIC.ColorRamBase+$2c1-40
                        sta     VIC.ColorRamBase+$2c2-40
                        sta     VIC.ColorRamBase+$2c3-40

sps_cl_ps_99:            
                        dec     sps_cl_ps_ndx+$01    
sps_cl_ps_e:

//------------------------------------------------------------------------------------------------------------------------------------------------------------
//wait and fade out

//>> DEAKTVIERT SICH SELBST WENN FERTIG
//>> DANCH MÜSSTEST DU DEN MUSIC-FADE DEAKTIVIEREN  >> SIEHE UNTEN

wtfd:
                                                        //check if active
wtfd_act:                lda     #$00
                        beq     wtfd_e
                                                        //handle wait
wtfd_dur:                lda     #$a0
                        beq     wtfd_dly
                        
                        dec     wtfd_dur+$01
                        
                        jmp     wtfd_e  
                                                        //delay
wtfd_dly:                lda     #$04
                        dec     wtfd_dly+$01
                        bne     wtfd_e
                                                        //restore delay
                        lda     #$04
                        sta     wtfd_dly+$01
                                                        //set color memory
wtfd_ndx:                ldx     #$05
                        ldy     #$27
                        lda     fdi_coldat,x
wtfd_lp:                         
                        sta     $d940,y
                        sta     $d968,y
                        sta     $d990,y
                        sta     $d9b8,y
                        sta     $d9e0,y
                        sta     $da08,y
                        sta     $da30,y
                        sta     $da58,y
                        sta     $da80,y
                        sta     $daa8,y
                        dey
                        bpl     wtfd_lp     
                                                        //set new index
                        dex
                        bpl     wtfd_20
                                                        //deactivate part
                        dec     wtfd_act+$01
						
						lda #Phases.MusicPhase_VolumeDown
                        sta interruptMusic.currentMusicPhase
                
wtfd_20:
                        stx     wtfd_ndx+$01     
wtfd_e:

   inc VIC.INTERRUPT_EVENT          
    
   lda #<interruptMusic                    // low byte of our raster interrupt handler
   sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
   lda #>interruptMusic                    // high byte of our raster interrupt handler
   sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

   lda #Configuration.IrqMusicRasterLine    // load desired raster line
   sta VIC.CURRENT_RASTERLINE_REG           // low byte of raster line

#if TIMING
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif 

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack

    rti
}

.segment Default "Raster IRQ motives"
interruptMotive: {
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

#if TIMING
    lda #LIGHT_RED
    sta VIC.BORDER_COLOR
#endif 

    //ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2400_MASK, VIC.SELECT_CHARSET_AT_1000_MASK)
    lda #%10010100
    sta VIC.GRAPHICS_POINTER

    lda #%00001011
    sta VIC.CONTR_REG

    lda sineTableIndex
    and #%01111111
    bne !++
    
    ldx currentIcon
    inx
    cpx #Configuration.motiveCount
    bne !+
    ldx #$ff
!:  stx currentIcon

!:   
.label currentIcon = * + 1 
    ldx #$0
    jsr showMotive

!:    lda VIC.CURRENT_RASTERLINE_REG
    cmp #$30+41
    bne !-

    //ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2400_MASK, VIC.SELECT_CHARSET_AT_3800_MASK)
    lda #%10011110
    sta VIC.GRAPHICS_POINTER


exitMotiveInterrupt:
    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
   lda #<interruptHeadLines                    // low byte of our raster interrupt handler
   sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
   lda #>interruptHeadLines                    // high byte of our raster interrupt handler
   sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

   lda #Configuration.IrqHeadlineRasterLine    // load desired raster line
   sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

#if TIMING
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif 

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack

    rti
}

.segment Default "Raster IRQ bars"
interruptBars:
    sei
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop 


#if TIMING
    lda #RED
    sta VIC.BORDER_COLOR
#endif

.label colorIndex = * + 1
    ldx #$ff
    inx
    stx colorIndex
    ldy #BLACK
    sty colorValue
//    lda colors,x
    bpl !+

    ldx #$ff
    stx colorIndex 
    
//    ldx iconCounter1
//    dex
//    bpl !+
//    ldx #//!:
//    stx iconCounter1
//    stx iconCounter2
//    stx iconCounter3
//    stx iconCounter4

!:
.label colorValue = * + 1
    lda #$ff
    sta $d020
    sta $d021

.label sineTableIndex = * + 1
    ldx #0    
    jsr moveBars    
    inc sineTableIndex

.label endAfterBars = * + 1
    lda #0
    beq exitFromInterrupt

    lda sineTableIndex
    bne exitFromInterrupt

//.label barsAfterEnd = * + 1
//    ldx #0
//    bpl !+++
// now transition to logo
    lda #Phases.MusicPhase_Fadeout
    sta interruptMusic.currentMusicPhase
    lda #$0
    ldx #0
!:  sta VIC.ColorRamBase,x
    sta VIC.ColorRamBase+$100,x
    sta VIC.ColorRamBase+$200,x
    sta VIC.ColorRamBase+$300,x
    dex
    bne !-

    lda #$20
    ldx #0
!:  sta Configuration.ScreenRamStart,x
    sta Configuration.ScreenRamStart+$100,x
    sta Configuration.ScreenRamStart+$200,x
    sta Configuration.ScreenRamStart+$300,x
    dex
    bne !-

    //ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2400_MASK, VIC.SELECT_CHARSET_AT_1000_MASK)
    lda #%10010100
    sta VIC.GRAPHICS_POINTER

//!:  dec barsAfterEnd

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
    lda #<interruptMusic                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
    lda #>interruptMusic                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

    lda #Configuration.IrqMusicRasterLine        // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line
    jmp thisistheend


exitFromInterrupt:

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
    lda #<interruptMotive                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
    lda #>interruptMotive                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

    lda #Configuration.IrqMotiveRasterLine        // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

thisistheend:

#if TIMING
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack
    rti

moveBars: {
    lda sineTableHi,x
    sta targetCharAddressHi
    lda sineTableLo,x
    tay
    and #%11111000    
    sta targetCharAddressLo
    tya
    and #7 // get number of shifted pixels inside char
    tax
    lda shiftedBarCharsStartLo,x
    sta sourceCharAddressLo
    lda shiftedBarCharsStartHi,x
    sta sourceCharAddressHi

    ldx #Configuration.BarsWidth * 8 - 1 // FUCK > $80!
!:
.label sourceCharAddressLo = * + 1
.label sourceCharAddressHi = * + 2
    lda $dead,x
.label targetCharAddressLo = * + 1
.label targetCharAddressHi = * + 2
    sta $beef,x
    dex
    cpx #$ff
    bne !-

    rts
}

    // IN: x register, selecteced motive
showMotive: {
    lda screenbufferStartLo,x
    sta screenBufferSourceLo
    lda screenbufferStartHi,x
    sta screenBufferSourceHi

//    lda icons_xoffsets,x
//    clc
//    adc #10
//    sta xoffset

    ldy #5
!:
    lda colorRamOffsetsLo,y
    clc
.label xoffset = * + 1    
    adc #10
    sta colorRamTargetLo
    lda colorRamOffsetsHi,y
    adc #0
    sta colorRamTargetHi

    ldx #15
!:
.label screenBufferSourceLo = * + 1
.label screenBufferSourceHi = * + 2
    lda $dead,x
.label colorRamTargetLo = * + 1
.label colorRamTargetHi = * + 2
    sta $dead,x
    dex
    bpl !-

    lda screenBufferSourceLo
    clc
    adc #16
    sta screenBufferSourceLo
    bcc !+
    inc screenBufferSourceHi
!:
    iny
    cpy #21
    bne !---

   // dec $d020
    rts
}

zoomMotiveChars: {
    // make bytes out of the charset
    lda #3
    sta motiveCharIteration
    lda #0
    sta targetAddressIncrement
    lda #7
    sta currentCharByteIteration

    lda charsLo,x
    sta sourceCharAddressLo
    lda charsHi,x
    sta sourceCharAddressHi

charsLoop:
.label motiveCharIteration = * + 1
    ldy #3
    bmi doneWithMotive
    cpy #1
    bne !+
    clc
    lda #128
    sta targetAddressIncrement
!:
    dec motiveCharIteration

.label targetAddressIncrement = * + 1    
    lda #0
    clc
    adc screenbufferStartLo,x
    sta Zeropage.Unused_FD
    lda screenbufferStartHi,x
    adc #0
    sta Zeropage.Unused_FE

zoomSingleChar:
.label currentCharByteIteration = * + 1
    ldy #7
    bmi doneWithChar
.label sourceCharAddressLo = * + 1
.label sourceCharAddressHi = * + 2
    lda $dead

    ldy #7
zoomSingleCharByte:
    lsr
    pha
    bcc pixelNotSet

pixelSet:
    lda #LIGHT_GREY
    bne storePixel

pixelNotSet:  
    lda #BLACK

storePixel:
    sta (Zeropage.Unused_FD),y
    pla
    dey
    bpl zoomSingleCharByte    

doneWithCharByte:
    inc sourceCharAddressLo
    bne !+
    inc sourceCharAddressHi
!:
    lda Zeropage.Unused_FD
    clc
    adc #16
    sta Zeropage.Unused_FD
    dec currentCharByteIteration
    jmp zoomSingleChar

doneWithChar:
//    clc
//    lda sourceAddressIncrement
//    adc #8
//    sta sourceAddressIncrement

    lda targetAddressIncrement
    clc
    adc #8
    sta targetAddressIncrement
    lda #7
    sta currentCharByteIteration
    
    jmp charsLoop

doneWithMotive:
    rts
}

.segment Default "Raster IRQ scroller"
interruptScroller:
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

#if TIMING
    lda #LIGHT_BLUE //dec $d020                                   // comment out, leave in to check timing
    sta VIC.BORDER_COLOR
#endif 

    lda #%00001000
    ora currentXScrollOffset                       
    tax                                         // wait until we hit border before changing xscroll
    //lda VIC.GRAPHICS_POINTER
    lda #%10011100
    //and #VIC.SELECT_CHARSET_CLEAR_MASK
    //ora #VIC.SELECT_CHARSET_AT_3000_MASK
    nop
    nop
    nop
    nop
    nop

    nop
    nop
    nop
    nop
    stx VIC.CONTR_REG       
    sta VIC.GRAPHICS_POINTER                       
#if !TIMING
    ldy #BLACK
    sty VIC.BORDER_COLOR
    sty VIC.SCREEN_COLOR
#endif

    lda VIC.CONTR_REG                           // already calculate the 0 xscroll value for the next
    and #11111000                               // character line after the scrolling line
    ora #00000011

//    inc $d020
//    lda #0
//    ldx #39
//!:  .for (var i=5;i<23;i++) {
//    sta $d800+i*40,x
//    }
//    dex
//    bpl !-
//    dec $d020


exitFromScrollerInterrupt:
#if TIMING
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif
    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
    lda #<interruptBars                       // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
    lda #>interruptBars                       // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

    lda #Configuration.IrqBarsRasterLine      // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack
    cli
    rti

.segment Default "Raster IRQ headlines"
interruptHeadLines:
    pha        //store register A in stack
    txa
    pha        //store register X in stack
    tya
    pha        //store register Y in stack

#if TIMING
    lda #WHITE //dec $d020                                   // comment out, leave in to check timing
    sta VIC.BORDER_COLOR
#endif

//    lda VIC.GRAPHICS_POINTER
//    and #VIC.SELECT_CHARSET_CLEAR_MASK
//    ora #VIC.SELECT_CHARSET_AT_1000_MASK
//    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
//    ora #VIC.SELECT_SCREENBUFFER_AT_2400_MASK
//    sta VIC.GRAPHICS_POINTER        

.label delayCounter = * + 1
    lda #1
    beq waitCounterIsDone
    dec delayCounter
!:    jmp exit

jumpToFadeOut:
    jmp fadeoutMessage 

jumpToFadeInLetter:
    jmp fadeinLetter

waitCounterIsDone:
.label doNotShowHeadlines = * + 1
    lda #0
    bne !-

.label displayPhase = * + 1
    lda #Phases.Phase_DisplayMessage
    cmp #Phases.Phase_DisplayMessage
    beq displayMessage
    cmp #Phases.Phase_FadeOutMessage
    beq jumpToFadeOut
    cmp #Phases.Phase_FadeInLetter
    beq jumpToFadeInLetter

displayMessage:
    ldx currentXPosition

readNextCharacter:
.label disableScrolltext = * + 1
    lda #1
    beq exit
.label scrollTextPointerLo = * + 1
.label scrollTextPointerHi = * + 2
    lda $dead

    bmi doneWithCurrentMessageLine
    bne continueWithTyping
       
    ldy #<newsAlerts
    sty scrollTextPointerLo
    ldy #>newsAlerts
    sty scrollTextPointerHi
    jmp readNextCharacter

doneWithCurrentMessageLine:
    and #%01111111
    beq doneWithCurrentMessage
    inc currentYPosition
    inc currentYPosition
    lda #10
    sta currentXPosition
    ldy #1
    sty delayCounter
    clc
    inc scrollTextPointerLo
    bne !+
    inc scrollTextPointerHi
 !:   
    jmp exit

doneWithCurrentMessage:
    ldy #30
    sty delayCounter
    clc
    inc scrollTextPointerLo
    bne !+
    inc scrollTextPointerHi
!:    
    lda #Phases.Phase_FadeOutMessage
    sta displayPhase
    jmp exit

continueWithTyping:
    clc
    inc scrollTextPointerLo
    bne noPageIncrease
    inc scrollTextPointerHi  
noPageIncrease:
    pha
    ldy currentYPosition
    lda screenBufferOffsetsLo,y
    sta screenRamAddressLo
    lda screenBufferOffsetsHi,y
    sta screenRamAddressHi
    pla
.label screenRamAddressLo = * + 1
.label screenRamAddressHi = * + 2
    sta Configuration.ScreenRamStart,x
    lda #Phases.Phase_FadeInLetter
    sta displayPhase
    //lda #7
    //sta delayCounter
    //inc currentXPosition

exit:

#if TIMING
    lda #GREY
    sta VIC.BORDER_COLOR
#endif

scrollForward:                                  // not that we are passed the scrolled line with the raster
    lda currentXScrollOffset                    // we determine the next xscroll value and move the characters
    sec                                         // of the line if needed.
    sbc #Configuration.ScrollSpeed
    and #%00000111
    sta currentXScrollOffset
    bcc scrollOneSliceLeft
    jmp exitFromHeadlineInterrupt//exitFromScrollerInterrupt

scrollOneSliceLeft:    
    ldx #0                                      // move all characters one position to the left
!:                                              // loop forward to not overwrite character before
    lda Configuration.TextBufferOffsetScroller+1,x                    // reading
    sta Configuration.TextBufferOffsetScroller,x
    lda Configuration.TextBufferOffsetScroller+41,x                    
    sta Configuration.TextBufferOffsetScroller+40,x

    lda $d800 + 23 * 40 + 1,x
    sta $d800 + 23 * 40 + 0,x
    lda $d800 + 24 * 40 + 1,x
    sta $d800 + 24 * 40 + 0,x
    
    inx
    cpx #39
    bne !-

checkForNewCharacter:
    lda currentCharacterSlice
    bne readNextScrollTextCharacter
    lda currentRightmostCharacter
    clc
    adc #$1
    dec currentCharacterSlice
    jmp insertCharacterForward

readNextScrollTextCharacter:
.label scrollTextLo = *+1                   
.label scrollTextHi = *+2
    lda scrollText                              // we need to modify either this lda target by code 
    bne moveScrollPointerForward                // or use indirect addressing to have a scroll text
                                                // longer than 255 characters (limit of x/y indexing) 
    jmp transitionToNextPart

    lda #<scrollText                            // reset to start when we observe 0 byte (end marker)
    sta scrollTextLo
    lda #>scrollText
    sta scrollTextHi
    jmp readNextScrollTextCharacter

insertCharacterForward:
    dec currentCharacterSlice
    jmp printCharacterSlice

moveScrollPointerForward:    
    tax
    and #$80
    beq noControlByte
    txa
    and #$7f
    sta currentScrolltextColor
    
    inc scrollTextLo                            // insert new character on the right
    bne readNextScrollTextCharacter                     // and update scroll text pointer
    inc scrollTextHi
    jmp readNextScrollTextCharacter

noControlByte:
    txa
    ldx #0

!:
    stx currentCharacterSlice
    asl
    asl
    sta currentRightmostCharacter
    inc scrollTextLo                            // insert new character on the right
    bne printCharacterSlice                     // and update scroll text pointer
    inc scrollTextHi

printCharacterSlice:
    sta Configuration.TextBufferOffsetScroller+39                     // after moving the line to the left,
    clc
    adc #2
    sta Configuration.TextBufferOffsetScroller+39+40                  // after moving the line to the left,
    
    lda currentScrolltextColor
    sta $d800 + 23 * 40 + 39
    sta $d800 + 24 * 40 + 39

exitFromHeadlineInterrupt:
#if TIMING    
    lda #BLACK
    sta VIC.BORDER_COLOR
#endif 

//    lda VIC.GRAPHICS_POINTER
//    and #VIC.SELECT_CHARSET_CLEAR_MASK
//    ora #VIC.SELECT_CHARSET_AT_2000_MASK
//    and #VIC.SELECT_SCREENBUFFER_CLEAR_MASK
//    ora #VIC.SELECT_SCREENBUFFER_AT_2400_MASK
//    sta VIC.GRAPHICS_POINTER        

    inc VIC.INTERRUPT_EVENT                     // store back to enable raster interrupt
    
    lda #<interruptMusic                      // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo  // store to RAM interrupt handler
    lda #>interruptMusic                      // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi  // store to RAM interrupt handler

    lda #Configuration.IrqMusicRasterLine        // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG              // low byte of raster line

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack

    rti

transitionToNextPart:
    lda #1
    sta endAfterCurrentHeadline
    //lda #MusicPhase_Fadeout
    //sta interruptMusic.currentMusicPhase

//    lda #$20
//    ldx #0
//!:  sta Configuration.ScreenRamStart,x
//    sta Configuration.ScreenRamStart+$100,x
//    sta Configuration.ScreenRamStart+$200,x
//    sta Configuration.ScreenRamStart+$300,x
//    dex
//    bne !-
//
//    lda #$0
//    ldx #0
//!:  sta VIC.ColorRamBase,x
//    sta VIC.ColorRamBase+$100,x
//    sta VIC.ColorRamBase+$200,x
//    sta VIC.ColorRamBase+$300,x
//    dex
//    bne !-

    //ConfigureVicMemory(VIC.SELECT_SCREENBUFFER_AT_2400_MASK, VIC.SELECT_CHARSET_AT_1000_MASK)
//    lda #%10010100
//    sta VIC.GRAPHICS_POINTER

    inc VIC.INTERRUPT_EVENT                         // store back to enable raster interrupt
    
    lda #<interruptMusic                            // low byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomLo      // store to RAM interrupt handler
    lda #>interruptMusic                            // high byte of our raster interrupt handler
    sta Internals.InterruptHandlerPointerRomHi      // store to RAM interrupt handler

    lda #Configuration.IrqMusicRasterLine           // load desired raster line
    sta VIC.CURRENT_RASTERLINE_REG                  // low byte of raster line

    pla
    tay        //restore register Y from stack (remember stack is FIFO: First In First Out)
    pla
    tax        //restore register X from stack
    pla        //restore register A from stack
    cli
    rti

fadeinLetter:
    ldy currentYPosition
    lda colorRamOffsetsLo,y
    sta fadeInColorLo
    lda colorRamOffsetsHi,y
    sta fadeInColorHi
.label fadeInColorIndex = * + 1
    ldx #$0
    lda fadeInColors,x
    ldx currentXPosition
.label fadeInColorLo = * + 1
.label fadeInColorHi = * + 2
    sta $d800,x
    tax
    bmi doneWithFadeIn
    inc fadeInColorIndex
!:    
    jmp exit 

doneWithFadeIn:
    lda #0
    sta fadeInColorIndex
    inc currentXPosition
    lda #0
    sta delayCounter
    lda #Phases.Phase_DisplayMessage
    sta displayPhase
    jmp exit

fadeoutMessage:
.label currentFadeoutIteration = * + 1
    ldy #WHITE
    bpl continueFadeout

    ldx #29
    lda #32
!:  sta Configuration.TextBufferOffsetHeadlines+10,x
    sta Configuration.TextBufferOffsetHeadlines+40+10,x
    sta Configuration.TextBufferOffsetHeadlines+80+10,x
    dex
    bpl !-

    ldx #29
    lda #BLACK
c:  sta $d800+10,x
    sta $d800+40+10,x
    sta $d800+80+10,x
    dex
    bpl c    

.label endAfterCurrentHeadline = * + 1
    lda #0
    beq !+

    lda #$0
	sta VIC.SPRITE_ENABLE

    lda #1
    sta doNotShowHeadlines

    inc endAfterBars

!:  lda #Phases.Phase_DisplayMessage
    sta displayPhase
    lda #10
    sta currentXPosition
    lda #0
    sta currentYPosition
    lda #16
    sta currentFadeoutIteration


 !:   
    jmp exit

continueFadeout:
    lda fadeouttable,y
    sta currentFadeoutIteration

    ldx #29
!:  sta $d800+10,x
    sta $d800+40+10,x
    sta $d800+80+10,x   
    dex
    bpl !-
    jmp exit

#import "../../../commodore64/includes/common_gfx_functions.asm"

fadeouttable:
    .byte BLACK | $80, LIGHT_GREEN, DARK_GREY, GREEN, RED, LIGHT_RED, BROWN
    .byte LIGHT_GREY, PURPLE, BLACK, GREY, BLUE, LIGHT_BLUE, YELLOW
    .byte ORANGE, CYAN

currentYPosition:
    .byte $0
currentXPosition:
    .byte 10

screenBufferOffsetsLo:
    .fill 5, <(Configuration.ScreenRamStart + i * 40)
screenBufferOffsetsHi:
    .fill 5, >(Configuration.ScreenRamStart + i * 40)

fadeInColors:
    .byte DARK_GREY, GREY, WHITE, LIGHT_GREEN, LIGHT_GREY | $80

.segment Default "News Alert messages"
newsAlerts:
.text "+++ winning the hearts "; .byte 83; .text " +++"; .byte $81;
.text "sceners' mums love slackers"; .byte $80
.text "+++ tears of joy +++"; .byte $81;
.text "the group we all waited for"; .byte $80
.text "+++ eruption of emotions +++"; .byte $81;
.text "slackers entered the building"; .byte $80
.text "+++ overcoming laziness +++"; .byte $81;
.text "slackers don't care"; .byte $80
.text "+++ slackers are born +++"; .byte $81;
.text "slackers are porn!"; .byte $80
.text "+++ "; .byte 83; .text " full of love "; .byte 83; .text " +++"; .byte $81;
.text "slackers hugging the scene"; .byte $80
.text "+++ greetings 2 the scene +++"; .byte $81;
.text "hooray slackers!"; .byte $80
.text "+++ the place to be +++"; .byte $81;
.text "the sofa ... so good!"; .byte $80

.align $100
.segment Default "icons"

chars:
.import binary "motives3.64c", 0, Configuration.motiveCount * 4 * 8

charsLo:
    .fill Configuration.motiveCount, <(chars + i * 8 * 4)

charsHi:
    .fill Configuration.motiveCount, >(chars + i * 8 * 4)

screenbufferStartLo:
    .fill Configuration.motiveCount, <(screenbuffers + (i * 2 * 2 * 8 * 8))
screenbufferStartHi:
    .fill Configuration.motiveCount, >(screenbuffers + (i * 2 * 2 * 8 * 8))

.segment Default "bars"

barCharsetDefinition: // 20 chars wide bars
    // use this as shifted by 0
    .byte $00, $80, $00, $80, $81, $81, $83, $87, $9f, $be
    .byte $1e, $1c, $18, $18, $18, $40, $40, $00, $40, $00 
barCharsetDefinionShifted:
    .fill 20*7, $ff

shiftedBarCharsStartLo:
    .fill 8, <(Configuration.CharsetBarsStart + $280 + i * 8 * 20)
shiftedBarCharsStartHi:
    .fill 8, >(Configuration.CharsetBarsStart + $280 + i * 8 * 20)

colorRamOffsetsLo:
    .fill 25, <($d800 + i * 40)
colorRamOffsetsHi:
    .fill 25, >($d800 + i * 40)

currentXScrollOffset:
    .byte $07
currentRightmostCharacter:
    .byte $00
currentCharacterSlice:
    .byte $01
currentScrolltextColor:
    .byte WHITE

.align $100
.segment Default "scrolltext"
scrollText:
.text "  3AD " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "9.6)"; .byte WHITE | $80 ;
.text "  AC " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "8.7)"; .byte WHITE | $80 ;
.text "  ATL " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "8.9)"; .byte WHITE | $80 ;
.text "  BZ " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "8.9)"; .byte WHITE | $80 ;
.text "  DSR " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "9.0)"; .byte WHITE | $80 ;
.text "  EXT " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "8.3)"; .byte WHITE | $80 ;
.text "  F4CG " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "9.0)"; .byte WHITE | $80 ;
.text "  FCS " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "9.3)"; .byte WHITE | $80 ;
.text "  FF " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "0.0)"; .byte WHITE | $80 ;
.text "  FIG " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "8.8)"; .byte WHITE | $80 ;
.text "  FLT " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "9.6)"; .byte WHITE | $80 ;
.text "  FRQ " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "0.0)"; .byte WHITE | $80 ;
.text "  GP " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "8.7)"; .byte WHITE | $80 ;
.text "  HJB " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "0.0)"; .byte WHITE | $80 ;
.text "  INV " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "0.0)"; .byte WHITE | $80 ;
.text "  KRZ " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "0.0)"; .byte WHITE | $80 ;
.text "  LSD " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "8.5)"; .byte WHITE | $80 ;
.text "  LTH " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "8.9)"; .byte WHITE | $80 ;
.text "  LXT " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "8.4)"; .byte WHITE | $80 ;
.text "  MS " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "9.7)"; .byte WHITE | $80 ;
.text "  MYD " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "9.0)"; .byte WHITE | $80 ;
.text "  ONS " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "9.4)"; .byte WHITE | $80 ;
.text "  PDA " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "8.7)"; .byte WHITE | $80 ;
.text "  PL " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "9.1)"; .byte WHITE | $80 ;
.text "  RBS " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "0.0)"; .byte WHITE | $80 ;
.text "  RSC " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "8.9)"; .byte WHITE | $80 ;
.text "  SGR " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "8.4)"; .byte WHITE | $80 ;
.text "  SIDD " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "10.0)"; .byte WHITE | $80 ;
.text "  SMR " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "9.2)"; .byte WHITE | $80 ;
.text "  TRSI " ; .byte GREEN | $80 ; .text "("; .byte 42; .text "9.3)"; .byte WHITE | $80 ;
.text "  TRX " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "10.0)"; .byte WHITE | $80 ;
.text "  TST " ; .byte LIGHT_RED | $80 ; .text "("; .byte 43; .text "7.4)"; .byte WHITE | $80 ;
.text "  VSN " ; .byte LIGHT_GREY | $80 ; .text "("; .byte 35; .text "8.7) "; .byte WHITE | $80 ;
.text "                        "
.byte $00 

.align $100
.segment Default "Sine data Lo"
sineTableLo:
    .fill $100, <(Configuration.CharsetBarsStart + (240 + 239 * cos(toRadians((i * 360.0) / 255))))

.align $100
.segment Default "Sine data Hi"
sineTableHi:
    .fill $100, >(Configuration.CharsetBarsStart + (240 + 239 * cos(toRadians((i * 360.0) / 255))))

#if !integrated
* = music.location "music"
.fill music.size, music.getData(i)
#endif

//.align $100
* = $2c00
.segment Default "sprites"
spriteset_data:

sprite_image_0:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$8F,$E3,$FF,$E7,$F7,$FF
.byte $E7,$F7,$FF,$E3,$F7,$FF,$E1,$F7,$FF,$E0,$F7,$FF,$E8,$77,$FF,$EC
.byte $77,$FF,$EE,$37,$FF,$EF,$17,$FF,$EF,$87,$FF,$EF,$87,$FF,$EF,$C7
.byte $FF,$EF,$E7,$FF,$EF,$E7,$FF,$C7,$F7,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_1:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$00,$40,$F7,$8F,$63,$E7,$8F
.byte $63,$E7,$8F,$71,$E3,$8F,$F1,$E3,$8F,$F9,$C3,$8E,$F8,$D3,$80,$F8
.byte $D1,$8E,$FC,$B1,$8F,$FC,$B1,$8F,$FC,$B1,$8F,$FC,$39,$8F,$FC,$38
.byte $8F,$7E,$78,$8F,$7E,$7C,$00,$7E,$7D,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_2:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$87,$01,$FF,$CE,$39,$FF,$CE
.byte $39,$FF,$DC,$79,$FF,$9C,$7F,$FF,$BC,$3F,$FF,$BE,$0F,$FF,$3F,$03
.byte $FF,$7F,$81,$FF,$7F,$81,$FF,$7F,$C1,$FF,$7F,$E1,$FF,$FF,$F1,$FF
.byte $FC,$F1,$FF,$FC,$E3,$FF,$FC,$0F,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_3:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$BF,$83,$FF,$1F,$C7,$FF
.byte $1F,$C7,$FE,$1F,$C7,$FE,$8F,$C7,$FE,$8F,$C7,$FE,$8F,$C7,$FD,$C7
.byte $C7,$FD,$C7,$C7,$FD,$C7,$C7,$FD,$C7,$C7,$F8,$07,$C7,$FB,$E3,$C7
.byte $F3,$E3,$C7,$F7,$E3,$C7,$C1,$C0,$80,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_4:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$F0,$06,$00,$F8,$F7,$1C,$F8
.byte $F7,$1E,$F8,$FF,$1E,$F8,$FF,$1E,$F8,$DF,$1C,$F8,$1F,$1C,$F8,$DF
.byte $1C,$F8,$FF,$18,$F8,$FF,$01,$F8,$FF,$10,$F8,$FF,$18,$F8,$FF,$1C
.byte $B8,$F7,$1C,$B8,$F7,$1E,$30,$06,$0F,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_5:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$DF,$F0,$01,$8F,$77,$1D,$8F,$37
.byte $1D,$8F,$3F,$1D,$8F,$3F,$1F,$8F,$7F,$1F,$8F,$7F,$1F,$8F,$7F,$1F
.byte $9F,$FF,$1F,$9F,$FF,$1F,$DF,$FF,$1F,$DF,$FF,$1F,$DF,$7F,$1F,$FF
.byte $3F,$1F,$DF,$1F,$1F,$8F,$0C,$07,$DF,$FF,$FF,$FF,$FF,$FF,$FF,$02

sprite_image_6:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

sprite_image_7:
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
.byte $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF

* = $2400 "screen memory" virtual
.fill $400, 0

* = $2900 "Fadeout Logo & colors"
fadeoutScreen:
//$e8 need to be patched in at SCRMEM+$1f7
    .byte    $64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64,$64
    .byte    $e1,$51,$e2,$e2,$20,$e1,$ec,$20,$20,$20,$e1,$51,$e2,$fb,$20,$e1,$51,$e2,$fb,$20,$e1,$ec,$e1,$ec,$20,$e1,$ec,$e2,$e2,$20,$e1,$ec,$e2,$fc,$20,$e1,$51,$e2,$e2,$20
    .byte    $7c,$e2,$e2,$fb,$20,$e1,$61,$20,$6c,$20,$e1,$57,$51,$e1,$20,$e1,$61,$20,$20,$20,$e1,$57,$51,$7b,$20,$e1,$57,$51,$20,$20,$e1,$57,$51,$7b,$20,$7c,$e2,$e2,$fb,$20
    .byte    $e1,$a0,$a0,$51,$20,$e1,$a0,$a0,$a0,$20,$e1,$a0,$20,$a0,$20,$e1,$a0,$a0,$51,$20,$e1,$61,$20,$ae,$20,$e1,$a0,$a0,$57,$20,$e1,$a0,$20,$a0,$20,$e1,$a0,$a0,$51,$20
    .byte    $63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63,$63
fadeoutScreenPresents:
    .text    "will return!"

//color memory data "Slackers presents"

fadeoutColor:
    .byte    $0b,$0f,$01,$01,$0b,$0b,$01,$0b,$0b,$0b,$0b,$0f,$01,$01,$0b,$0b,$0f,$01,$01,$0b,$0b,$0f,$0b,$01,$0b,$0b,$0f,$01,$01,$0b,$0b,$0f,$01,$0b,$0b,$0b,$0f,$01,$01,$0b
    .byte    $0b,$0c,$0f,$01,$0e,$0b,$0f,$0e,$0e,$0e,$0b,$0c,$0f,$01,$0e,$0b,$0c,$0f,$01,$0e,$0b,$0c,$0b,$0f,$0e,$0b,$0c,$0f,$01,$0e,$0b,$0c,$0f,$01,$0e,$0b,$0c,$0f,$01,$0c
    .byte    $0c,$0f,$0c,$0f,$0e,$0c,$0b,$0e,$01,$0e,$0c,$0b,$0c,$0f,$0e,$0c,$0b,$0e,$0c,$0e,$0c,$0b,$0c,$0f,$0e,$0c,$0b,$0c,$0c,$0e,$0c,$0b,$0c,$0f,$0e,$0c,$0f,$0c,$0f,$01
    .byte    $01,$0f,$0c,$0c,$0e,$01,$0f,$0c,$0f,$0e,$01,$0f,$0e,$0c,$0e,$01,$0f,$0c,$0c,$0e,$01,$0f,$0e,$0c,$0e,$01,$0f,$0c,$0f,$0e,$01,$0f,$0e,$0c,$0e,$01,$0f,$0c,$0c,$0b
    .byte    $0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b,$0b                       
//presents:
    .byte    $0b,$0b,$0c,$0c,$0f,$01,$01,$01,$0f,$0c,$0c, $0b,$0b	//<= AUF "WILL RETURN"-CHARS ÄNDERN
   // .text    "will return"
//            presents
fdi_coldat:
    .byte    $00,$0b,$0c,$0f,$01,$03

* = Configuration.startAddressCharsetScroller "charset scroller"
.import binary "astra_xy_multi2.64c"

* = Configuration.startAddressCharsetBars "charset bars" virtual
.fill $800, 0

* = Configuration.startAddressZoomedBuffer "zoomed buffer" virtual
screenbuffers:
    .fill 2 * 2 * 8 * 8 * Configuration.motiveCount, $00
