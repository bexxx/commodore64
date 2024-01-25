# TechTech

## TechTech Charset8px

Showing how to change XSCROLL for each raster line within a row of characters.
This limits swing to 8 pixel, but it's a good start for more. Still doing the exact cycle counting, which is not necessary for this effect. 

## TechTech

Same as the previous one, but more pixel swing.
The idea is to switch to a different character set which is shifted (B -> A) when XSCROLL is larger than 8. Because there is not a lot of time, we use a second table which contains the value for $D016. So during bad line we only have to fetch two table values.

Used sources:
- [Codebase64, TechTech](https://codebase64.org/doku.php?id=magazines:chacking7#tech-tech_-_more_resolution_to_vertical_shift)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
