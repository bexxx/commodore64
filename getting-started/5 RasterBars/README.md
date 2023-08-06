# Rasterbar

With the knowledge of bad lines, I needed to find a good start line to setup the raster interrupts.
Ideally this happens 4 lines before a bad line to time the code correctly.
A good learning was, that YSCROLL is not 0, but 3 by default.
It's a good idea to load values into regs before bad line to have as many as possible cycles
available (increment color index & load color from memory).

Moving rasterbars uses a larger buffer for raster colors and fills in background color
in the beginning before raster colors by using a sine table. This way we do not have to
update the raster interrupt start each frame, and instead just clear and copy colors in the larger buffer. It might be a good improvement to do the clearing and possibly copying during good lines wher ewe only waste time otherwise.

Used sources:
- [Stretching the C64 palette](http://www.krajzewicz.de/blog/stretching-the-c64-palette.php)
- [Retro Programming, Raster articles](https://www.retro-programming.de/programming/nachschlagewerk/interrupts/]der-rasterzeileninterrupt/raster-irq-endlich-stabil/)
- [C64 wiki, Raster interrupt](https://www.c64-wiki.de/wiki/Rasterzeilen-Interrupt)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
