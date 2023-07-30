.namespace Internals
{
    .label InterruptHandlerPointer = $ea31
}

.macro ReturnFromInterrupt() {
    pla
    tay
    pla
    tax
    pla
    rti
}
