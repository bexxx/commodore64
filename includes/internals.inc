.namespace Internals
{
    .label InterruptHandlerPointer = $ea31
    .label InterruptHandlerPointerRamLo = $0314
    .label InterruptHandlerPointerRamHi = $0315
    .label InterruptHandlerPointerRomLo = $fffe
    .label InterruptHandlerPointerRomHi = $ffff
}

.namespace Kernal {
    .label ClearScreen = $e544
}