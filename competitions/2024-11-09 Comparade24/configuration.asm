#importonce

#import "../../../commodore64/includes/common_gfx_constants.asm"

#define EnableMusic                             // before this drives you insane during development, just turn it off
#define Integrated                              // together with petscii animation, or just scroller
//#define DebugView                             // debug characters to see start of scrolling, ... just screen garbage
//#define Timing                                // border coloring to show raster time of different code parts
#define TheWholeShebang                         // to produce just the binary with fader and scroller comment this out

#if EnableMusic
    .var music = LoadSid("comparade-9000.sid")
#endif

.namespace Configuration {
    .label Irq1AccuZpLocation = $02
    .label Irq1XRegZpLocation = $03
    .label Irq1YRegZpLocation = $04

    .label ScreenPointerZP = $05
    .label ScreenPointerHiZP = $06
    .label ColorPointerZP = $07
    .label ColorPointerHiZP = $08

    .label ScreenPointer2ZP = $09
    .label ScreenPointer2HiZP = $0a
    .label ColorPointer2ZP = $0b
    .label ColorPointer2HiZP = $0c

    .label CharSourceLoZp = $5
    .label CharSourceHiZp = $6
    .label CharColorSourceLoZp = $7
    .label CharColorSourceHiZp = $8

    .label RasterLineFaderInitialIrq = $01
    .label RasterLineBlackOutIrq = $ea
    .label RasterLinePetsciiIrq = $10
    .label RasterLineScrollerTopIrq = rasterLineOfBadLine(ScrollerYOffset) - 3
    .label RasterLineScrollerBottomIrq = $33 + 25 * 8

    .label ScreenRamStartAddress = $0400
    .label ScrollerInterruptAddress = $0900
    .label FaderInterruptAddress = $3000
    .label SourceLogoAddress = $3500
    .label SourceLogoColorAddress = $3900
    .label PetsciiScrollerAnimationCodeAddress = $4000
    .label PetsciiAnimationSetupAddress = $6000

    .label FldLines = 24
    .label BounceHeightChars = 3
    .label BounceHeight = BounceHeightChars * 8

    .label CharHeight = 7
    .label ScrollerYOffset = 25 - CharHeight - BounceHeightChars
    .label PetsciiCharsStartAddress = $2000
    .label PetsciiCharsColorsStartAddress = $2800
    .label ScrollSpeed = 3

    .label BlinkTextLength = 12
}
