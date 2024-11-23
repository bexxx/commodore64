.filenamespace BurnholeFader

#import "../../../commodore64/includes/vic_constants.inc"
#import "../../../commodore64/includes/common.inc"
#import "../../../commodore64/includes/zeropage.inc"

BasicUpstart2(main)

.namespace Configuration {
    .label zpRestDelayLo = $30
    .label zpRestDelayHi = $31
    .label zpRestDelay = zpRestDelayLo

    .label zpNeuronLo = $32
    .label zpNeuronHi = $33
    .label zpNeuron = zpNeuronLo

    .label zpNeuronLeftLo = $34
    .label zpNeuronLeftHi = $35
    .label zpNeuronLeft = zpNeuronLeftLo

    .label zpNeuronRightLo = $36
    .label zpNeuronRightHi = $37
    .label zpNeuronRight = zpNeuronRightLo

    .label zpNeuronTopLo = $38
    .label zpNeuronTopHi = $39
    .label zpNeuronTop = zpNeuronTopLo  

    .label zpNeuronBottomLo = $3a
    .label zpNeuronBottomHi = $3b
    .label zpNeuronBottom = zpNeuronBottomLo   

    .label zpScreenLo = $3c
    .label zpScreenHi = $3d
    .label zpScreen = zpScreenLo        

    .label zpReactionDelayLo = $3e
    .label zpReactionDelayHi = $3f
    .label zpReactionDelay = zpReactionDelayLo

    .label zpColorRamLo = $40
    .label zpColorRamHi = $41
    .label zpColorRam = zpColorRamLo

    .label restDelayMax = 12

    .label reactionDelayBufferAddress = $0e00
    .label restDelayBufferAddress = $1200
    .label neuronBufferAddress = $1600
}

main:
    // disable NMI by no acking one which prevents new ones.
    // taken from codebase 64: https://codebase64.org/doku.php?id=base:nmi_lock
    sei                                         // don't allow other irqs to happen during setup
    lda #<nmiHandler                            // change nmi vector to unacknowledge "routine"
    sta $0318
    lda #>nmiHandler
    sta $0319
    lda #$00
    sta $dd0e                                   // stop timer a
    sta $dd04                                   // set timer a to 0, after starting nmi will occur immediately
    sta $dd05
    lda #$81
    sta $dd0d                                   // set timer a as source for nmi
    lda #$01
    sta $dd0e                                   // start timer a and trigger nmi

    lda #%01111111                              // disable timer on CIAs mask
    sta $dc0d                                   // disable all CIA1 irqs
    sta $dd0d                                   // disable all CIA2 irqs

    lda #$35                                    // configure ram
    sta $1 
    
    lda #%01111111
    sta $dc0d
    sta $dd0d 

    lsr $d019

    cli                                         // allow irqs again
    
    // use current border color as color for characters and later on for sliding down the raster
    lda $d020
    and #$f
    sta neuronColor
    sta currentBottomColor
    tax
    lda borderColors,x 
    sta currentTopColor

    // we have 40 x 25 neurons, padded by one empty neuron which makes it 
    // 42 x 27 neuron values.
    // rest delay and reaction delay == 25 x 40 neurons

    // initialize the neurons & rest delay both to 0 (no energy and no rest)

    lax #0
!:
    // initialize rest delays with 0, because there was no reaction yet
    sta restDelays + $0000,x
    sta restDelays + $0100,x
    sta restDelays + $0200,x
    sta restDelays + $02e8,x

    // initialize neurons with 0 energy
    sta neurons + $0000,x
    sta neurons + $0100,x
    sta neurons + $0200,x
    sta neurons + $0300,x
    sta neurons + $036e,x
    dex
    bne !-

    // initialize reactio delays with random values
    // this will make the growth of the neurons random und therefore less uniform
    
    // configure SID to provide random values
    lda #$ff                                    // maximum frequency value
    sta $d40e                                   // voice 3 frequency low byte
    sta $d40f                                   // voice 3 frequency high byte
    lda #$80                                    // noise waveform, gate bit off
    sta $d412                                   // voice 3 control register

    ldx #0
!:
    lda $d41b                                   // read random value
    and #3                                      // mask value to 0-7
    sta reactionDelays + $0000,x                // store in reaction delays
    lda $d41b
    and #3
    sta reactionDelays + $0100,x
    lda $d41b
    and #3
    sta reactionDelays + $0200,x
    lda $d41b
    and #3
    sta reactionDelays + $02e8,x
    dex
    bne !-

    // seed a single neuron in the lower right screen area
    lda #1
    sta neurons + 18 * 42 + 25

processNeuronFrame:
    // reset ZP address to the start
    lda #<Configuration.restDelayBufferAddress
    sta Configuration.zpRestDelayLo
    lda #>Configuration.restDelayBufferAddress
    sta Configuration.zpRestDelayHi

    lda #<reactionDelays
    sta Configuration.zpReactionDelayLo
    lda #>reactionDelays
    sta Configuration.zpReactionDelayHi

    lda #<(42 + 1)
    sta Configuration.zpNeuronLo

    lda #<1
    sta Configuration.zpNeuronTopLo

    lda #<(2 * 42 + 1)
    sta Configuration.zpNeuronBottomLo

    lda #<(1 * 42)
    sta Configuration.zpNeuronLeftLo

    lda #<(1 * 42 + 2)
    sta Configuration.zpNeuronRightLo

    lda #>neurons
    sta Configuration.zpNeuronHi
    sta Configuration.zpNeuronTopHi
    sta Configuration.zpNeuronBottomHi
    sta Configuration.zpNeuronLeftHi
    sta Configuration.zpNeuronRightHi

    lda #<$0400
    sta Configuration.zpScreenLo
    sta Configuration.zpColorRamLo
    lda #>$0400
    sta Configuration.zpScreenHi
    lda #>$d800
    sta Configuration.zpColorRamHi

    // reset row counter for each full frame
    lda #25
    sta rowCounter
neuronScreenLoop:
    lda rowCounter: #$ff
    bne !+
    jmp processNeuronFrame

!:
    dec rowCounter                              // one row less

    ldy columnIterationInitValue: #39           // start index for y
neuronRowLoop:
    lda (Configuration.zpRestDelay),y           // get remaining rest delay
    beq calculateNeuron                         // is this neuron still resting?
    sec                                         // yes
    sbc #1                                      // reduce one
    sta (Configuration.zpRestDelay),y           // save back
    jmp doneWithNeuron                          // and we are done with this one

calculateNeuron:                        
    lda (Configuration.zpNeuron),y              // get neuron value
    bne growNeuron                              // if it's > 0, grow/develop it
	
    lda	(Configuration.zpNeuronTop),y		    // it does not have energz, so check if any neighbor have energy
	bne	neighbourHasEnergy
	lda	(Configuration.zpNeuronBottom),y
	bne	neighbourHasEnergy
	lda	(Configuration.zpNeuronLeft),y
	bne	neighbourHasEnergy
	lda	(Configuration.zpNeuronRight),y   
	bne	neighbourHasEnergy

    jmp	doneWithNeuron				            // no neighbor has energy, give up and check next neuron

neighbourHasEnergy:
    lda	(Configuration.zpReactionDelay),y	    // is this neuron still lazy?
	bne	decreaseLazyness    	                // yes, still lazy, just make it less lazy
	lda	#1				     	                // no, it gets 1 energy (this is the infectious part)
	sta	(Configuration.zpNeuron),y              // save energy to neuron
    tax                                         // use energy (0-7) as index into character table for visualization
	lda $d41b                                   // load random value again
	and	#3  					                // reaction delay, and #1 0-1 fast, and #3 0-3 slow
    sta	(Configuration.zpReactionDelay),y	    // this value is the reason for the strange movement
	jmp	printNeuronCharacter

decreaseLazyness:
    // accumulator as current reactionDelay
	sec							                
	sbc	#$01                                    // decrease reaction delay by one
	sta	(Configuration.zpReactionDelay),y       // update the reaction delay
	jmp	doneWithNeuron

growNeuron:
    // accumulator as current neuron
	clc                                         
	adc	#$1                                     // increment neuron energy (energy value has a char representation)
	and	#$7                                     // limit to 0-7 (or define more chars)
	sta	(Configuration.zpNeuron),y              // update current neuron value
    tax                                         // use neuron value as index
printNeuronCharacter:
    lda chars,x                                 // load char representation
    sta (Configuration.zpScreen),y              // also print on screen
    lda neuronColor: #LIGHT_BLUE                // in this case now also set character color
    sta (Configuration.zpColorRam),y     
    txa                                         // move back to accumulator to make branch command work
    bne doneWithNeuron                          // if it has more than 0 energy the cycle is not done
        
    lda #Configuration.restDelayMax             // 0 energy means it has gone through a full cycle
    sta (Configuration.zpRestDelay),y           // and now it will not be touched until rest delay has passed

doneWithNeuron:
    iterationCountingOpcode: dey                // this will switch for each row from dey to iny and back
    cpy iterationTerminationValue: #$ff         // because opcode switches, this must be either 0 or neurons width
    bne neuronRowLoop

    // switch direction of procesing for each row. Fetch current values and opcodes and store for the next iteration
    ldx direction: #0
    lda iterationCountingOpcodes,x
    sta iterationCountingOpcode
    lda iterationTerminationValues,x
    sta iterationTerminationValue
    lda columnIterationInitValues,x
    sta columnIterationInitValue
    
    // switch direction for the next time
    lda direction
    eor #%00000001
    sta direction

    lda Configuration.zpNeuronTopLo
    clc
    adc #42
    sta Configuration.zpNeuronTopLo
    bcc !+
    inc Configuration.zpNeuronTopHi
    clc

!:
    lda Configuration.zpNeuronLeftLo
    clc
    adc #42
    sta Configuration.zpNeuronLeftLo
    bcc !+
    inc Configuration.zpNeuronLeftHi
    clc

!:
    lda Configuration.zpNeuronLo
    adc #42
    sta Configuration.zpNeuronLo
    bcc !+
    inc Configuration.zpNeuronHi
    clc

!:
    lda Configuration.zpNeuronRightLo
    adc #42
    sta Configuration.zpNeuronRightLo
    bcc !+
    clc
    inc Configuration.zpNeuronRightHi
    clc

!:
    lda Configuration.zpNeuronBottomLo
    clc
    adc #42
    sta Configuration.zpNeuronBottomLo
    bcc !+
    inc Configuration.zpNeuronBottomHi
    clc

!:
    lda Configuration.zpScreenLo
    adc #40
    sta Configuration.zpScreenLo
    sta Configuration.zpColorRamLo
    sta Configuration.zpRestDelayLo
    sta Configuration.zpReactionDelayLo
    bcc !+
    inc Configuration.zpScreenHi
    inc Configuration.zpColorRamHi
    inc Configuration.zpRestDelayHi
    inc Configuration.zpReactionDelayHi
    clc

!:  
    dec loopIterationLo
    bne !+
    dec loopIterationHi
    bne !+
    jmp slideDown
    nop 
!:

    jmp neuronScreenLoop

    //
    // Second phase of the fader, we are pulling down black screen from above with a little bump.
    // y values are basically -x^3 - x, with some adjustments to go from 0 to ~280.
    //

slideDown:
    lda #3                                      // set display enable to false, keep y scroll
    sta $d011  

frameLoop:
    ldy currentTopColor: #BLUE                  // load black to have it handy

upperPartOfScreen:
    lda $d011                      
    bpl upperPartOfScreen                       // 7th bit is MSB of rasterline, wait for the next frame

bottomPartOfScreen:  
    lda $d011
    bmi bottomPartOfScreen                      // wait until the 7th bit is clear (=> line 0 of raster)
    sty $d020                                   // start black on top
    ldy currentBottomColor: #LIGHT_BLUE         // load light blue already

    ldx tableIndex: #0                          // load current index into y values table
    lda offsetsLo,x                             // load lo byte of y value
    sta rasterLine                              // store in code
    lda offsetsHi,x                             // load the opcode used in code for the y value
    sta checkRasterMsbBranchOpcode              // store in code

checkRasterMsb:
    lda $d011                                   // check MSB of raster line
checkRasterMsbBranchOpcode:
    bpl checkRasterMsb                          // using either bmi or bpl from table below

checkRasterLine:  
    lda $d012                                   // load current raster line
    cmp rasterLine: #$ff                        // compare with current y value (previously written)
    bne checkRasterLine

    .fill 22, NOP                               // add some delay to push flickering to non visible part of screen

    inc tableIndex                              // set next index
    inc tableIndex                              // double speed, looks more dynamic :)
    beq checkAnotherRound                       // do nothing after $ff iterations
    
    sty $d020                                   // store black at desired raster line
    jmp frameLoop                               // again

checkAnotherRound:
    lda doAnotherRound: #1                      // doing two rounds of the slide down of raster colors
    beq waitForever

    lda currentTopColor
    sta currentBottomColor
    lda #BLACK                                  // set new colors
    sta currentTopColor
    dec doAnotherRound
    jmp slideDown

waitForever:                                    // stay a while, stay forever.
    jmp waitForever

nmiHandler:
    rti

.segment Default "Data"

    // -x^3 - x with some adjustments to get it from 0 to 280
    .align $100
offsetsLo:
    .fill $100, <(164.0-((-((i-128)/84.0)*((i-128)/84.0)*((i-128)/84.0))+(i-123)/84.0)*74.0)
offsetsHi:
    .fill $100, ((164.0-((-((i-128)/84.0)*((i-128)/84.0)*((i-128)/84.0))+(i-123)/84.0)*74.0)) < 256 ? BMI_REL : BPL_REL

// chars for neuron values 0-7
chars:
    .byte 160, 46, 58, 43, 91, 86, 219, 171

borderColors:
    //    BLACK      WHITE       RED    CYAN        PURPLE GREEN      BLUE       YELLOW  ORANGE BROWN      LIGHT_RED DARK_GREY   GREY       LIGHT_GREEN LIGHT_BLUE LIGHT_GREY
    .byte DARK_GREY, LIGHT_GREY, BROWN, LIGHT_BLUE, RED,   DARK_GREY, DARK_GREY, ORANGE, BROWN, DARK_GREY, PURPLE,   LIGHT_GREY, DARK_GREY, GREEN,      BLUE,      DARK_GREY  

// 16bit counter for iterations (neuron code would run infinit)
loopIterationLo:
    .byte $ff
loopIterationHi:
    .byte 7

iterationTerminationValues:
    .byte -1
    .byte 40
columnIterationInitValues:
    .byte 39
    .byte 0
iterationCountingOpcodes:
    .byte DEY
    .byte INY

// filling them with 0 is not needed since this is virtual anyway, but it looks better in memory viewer in VS code.
* = Configuration.reactionDelayBufferAddress "Reaction delays" virtual
reactionDelays:
    .fill 40*25, 0

// the amount of time needed before another change can happen
* = Configuration.restDelayBufferAddress "Rest delays" virtual
restDelays:
    .fill 40*25, 0

// the current value of the neuron
* = Configuration.neuronBufferAddress "Neurons Buffer" virtual
neurons:
    .fill 42*27, 0