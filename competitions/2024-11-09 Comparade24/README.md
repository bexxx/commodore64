# Comparade24 entry "We come in PETSCII"

These are the sources for the fader part and the scroller. The Petscii animations on top of scroller are added as binary blob - they have been coded by LDX#40.

1. Use VS Code and kickassembler to build from file we_come_in_petscii_main.asm
1. exomize with command line similar to "./exomizer sfx basic ./bin/we_come_in_petscii_main.prg -o ./bin/we_come_in_petscii_main.prg -s "jsr highest_addr_out" -X 'inc $dbe4' -f 'ldx #$6 lda #$20 lp: sta $07e1,x dex bpl lp'"
1. Build we_come_in_petscii_crunched.asm
1. Copy file to we-come-in-petscii.d64, e.g. with Dirmaster on Windows

Let me know if you have questions or if you want to show me hot to do things better :).

Party on!
bexxx