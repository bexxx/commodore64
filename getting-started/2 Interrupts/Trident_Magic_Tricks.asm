.importonce 

.macro irq_set(label, rasterline) {
    lda #<label
    sta $fffe
    lda #>label
    sta $ffff
    lda #rasterline
    sta $d012
}

.macro irq_wait(rasterLine) {
    .errorif rasterLine > 255, "raster line number > 255, implement a irq_wait_ex instead"
    
    irq_set(next, rasterLine)

    lsr $d019                                   // ack raster irq
    irq_endRaster()                             // restore reg values and return from irq

next:
    irq_save()                                  // stash reg values away
}

.macro irq_save() {
    pha
    txa
    pha
    tya
    pha
}

.macro irq_endRaster() {
    lsr $d019                                   // ack raster irq
    irq_restore()                               // restore reg values and return from irq

    rti
}

.macro irq_restore() {
    pla
    tay
    pla
    tax
    pla
}

.macro delay(pt, frames) {
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
next:
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts
    
done:
}

.macro delay_repeatable(pt, frames) {
setupProtothread:
    lda #<next
    sta pt
    lda #>next
    sta pt + 1
    lda #0
    sta counter
next:
    lda counter: #$0
    inc counter
    cmp #frames
    beq done
    rts
    
done:
}