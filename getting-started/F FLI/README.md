# FLI

FLI means "Flexible line interpretation" and is a software driven graphics mode. The main principle is to create bad line conditions for each raster line to force VIC to reread the data. At the same time the VIC memory config is being changed to show different data to the vic (in the remaining 23 cycles of a bad line there is no time to do other work).

## TechTech FLI

Instead of different shifted charsets in memory, this sample has shifted screen buffers (less memomy than charsets) and switches to them depending on the swing value for each raster line. 7px shift through XScroll.
Because of the time constraints, the values need to be prepared in data tables and use self modifying code. There is literally not a single cycle left for nop'ing it out.

I combined this with multicolor chars, where the main learning for me was setting the bit 3 of colors in color ram to enable multicolor for the character. This means the first 8 colors can be used and should be stored as #(color + 8).

Last learning moment was that I had my loop setup to use exactly 23 cycles for a bad line (nop and bit $01 at the end) and after I started to add a sprite to cover the FLI bug on the left, everything was messed up. Turns out sprites on the same line have an overheader for fetching their data. Fortunately, this was exactly 2 data fetch and 3 bus arbitration cycles, that I had to spare (byebye nop and bit).

Used sources:
- [Codebase64, TechTech FLI](https://codebase64.org/doku.php?id=base:techtech_fli)
- [Retroprogramming blog, FLI](https://www.retro-programming.de/programming/nachschlagewerk/vic-ii/vic-ii-grafikmodes-fli/)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
- [Pasi 'Albert' Ojala, The missing cycles](http://www.antimon.org/dl/c64/code/missing.txt)
- [Asm instructions, vic registers docs on C64 wiki](https://www.c64-wiki.de/)
- [Logo generator, Font by Jaws used in Wasted Years (1989)](https://codepo8.github.io/logo-o-matic/#goto-tempest)
- [CharPad](https://subchristsoftware.itch.io/charpad-c64-free)
- [PNG image converted to charset by "Der boese Wolf" from Abyss Connection, thanks mate!](https://englishclass.de/~wolf/ac/)