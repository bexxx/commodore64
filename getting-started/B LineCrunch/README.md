# Line crunch

This VIC trick is used to scroll up text or graphics without moving memory around.

Codebase article says:
This is done by changing the YSCROLL value in $d011 on a badline, but before the VIC starts stealing CPU cycles (cycle 14 to be exact), to make the badline-condition no longer true.

VIC text is a bit more precise, but I find more confusing to beginners:
You may also abort a Bad Line before its correct completion by negating the Bad Line Condition within an already begun Bad Line before cycle 14.

We use the stable raster double irq code from the other samples (I really need to learn the sprite sync!), prepare data and wait for the bad line. On the bad line we write an YSCROLL value to $d011 which is different from the last three bits of the raster line, which is the famous badline condition. This should show in a text line that is crunched to a single pixel row and we should see some garbage on the bottom (sprite pointers, ...). After 1024 bytes, the screen wraps around and scrolls in the top again.

In this source I continuously increase $d011 to always make the next line a bad line again and then cancel it on cycle 8 to be done on cycle 12. For me, startin on cycle 10 does not work, but cycle 8 does.

Used sources:
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
- [Bumbershootsoft blog, Partial badline glitches](https://bumbershootsoft.wordpress.com/2015/10/18/partial-badlines-glitching-on-purpose/)
- [Codebase64, Linecrunch](https://codebase64.org/doku.php?id=base:linecrunch)
- [Codebase64, Smooth Linecrunch](https://codebase64.org/doku.php?id=base:smooth_linecrunch)