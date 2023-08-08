# Scrolling

# 1x1 scroller

Using 7 pixel x scrolling by modifying $d016 XSCROLL and move characters by one character if needed. This combined with a raster irq to only scroll the line we want to scroll.
The scroller can handle 8 speed bytes which are used to add/sub pixels.

Challenges were supporting > 255 characters, I had to read through existing code to get myself more familiar with using self modifying code. Going to love this!

Used sources:
- [Scrollers, general details](https://codebase64.org/doku.php?id=base:text_scroll)
- [1x1 Scroller by groepaz](https://codebase64.org/doku.php?id=base:1x1_scroll)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
