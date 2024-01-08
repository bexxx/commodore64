# Scrolling

# 1x1 scroller

Using 7 pixel x scrolling by modifying $d016 XSCROLL and move characters by one character if needed. This combined with a raster irq to only scroll the line we want to scroll.
The scroller can handle 8 speed bytes which are used to add/sub pixels.

Challenges were supporting > 255 characters, I had to read through existing code to get myself more familiar with using self modifying code. Going to love this!

Added some color cycling as well to make this fancy. Now the 80s are calling to get their scrollers back.

# Dotted 8x scale charset scroller
Here we zoom a char to 8x8 characters. As a nice addition, there is a matrix of dot characters and instead of drawing 8x8 characters, I write to color ram to color the dots. 
On top we'll use a custom charset because the one from rom is boring.
Interesting parts are how to calculate the char's 8 bitmap address (shift letter 3 times left and inc to hi address on carry). The rest is basic. Nice extensions will be color support or blinking words. 
It may need some code optimization, looks a bit slow raster time wise.

# DYCP
Usign the free positioning method as described in the excellent codebase64 article. Added sprites in background and sod music, as well as minimal color ram changes to give it a nice touch. Uses cudly font from font collection and custom sine values. 
Code should be optimized a bit more. Currently two buffers are used to draw charset while it's displayed (use 80% of raster time currently).

Used sources:
- [Scrollers, general details](https://codebase64.org/doku.php?id=base:text_scroll)
- [1x1 Scroller by groepaz](https://codebase64.org/doku.php?id=base:1x1_scroll)
- [8x8 Zoom Scroller by conrad/onslaught/samar](https://codebase64.org/doku.php?id=base:8x_scale_charset_scrolling_message)
- [Peter Kofler's Font Collection, Roger Font](http://home-2002.code-cop.org/c64/)
- [Peter Kofler's Font Collection, Cudly Font](http://home-2002.code-cop.org/c64/)
- [Fieser Wolf / Abyss-Connection, Sinusgen](https://github.com/fieserWolF/sinusgen)
- [SID tune Retrospectful by Drax](https://csdb.dk/release/?id=115027)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
- [SpriteMate to export to asm](https://www.spritemate.com/)
- [Petscii editor to create sprites](https://petscii.krissz.hu/)
