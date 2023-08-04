# Rasterbar

With the knowledge of bad lines, I needed to find a good start line to setup the raster interrupts.
Ideally this happens 4 lines before a bad line to time the code correctly.
A good learning was, that YSCROLL is not 0, but 3 by default.
It's a good idea to load values into regs before bad line to have as many as possible cycles
available (increment color index & load color from memory).

Used sources:
- [Stretching the C64 palette](http://www.krajzewicz.de/blog/stretching-the-c64-palette.php)
- [Retro Programming, Raster articles](https://www.retro-programming.de/programming/nachschlagewerk/interrupts/]der-rasterzeileninterrupt/raster-irq-endlich-stabil/)
- [C64 wiki, Raster interrupt](https://www.c64-wiki.de/wiki/Rasterzeilen-Interrupt)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
