# Flexible Line Delay

## FLD BusyWaitingStatic.asm

First try of FLD. Just busy waiting and wasting cycles. FLD effects at static raster lines
Just to see that it works and just the screen memory on top is spread differently over the screen.
1. Wait for a new screen (raster == 0 or 1) and set defaults
1. Wait for the last good line before a bad line where the scrolling should happen (after first text line == )
1. Delay bad lines for 8 raster lines
1. Wait 3 text lines raster lines and display them
1. Delay bad lines for 16 raster lines

## FLD BusyWaitingMoving.asm

Same as the first one, but this time we use FLD on top and bottom of fixed content to make it bounce.




Used sources:
- [Retro-programming blog](https://www.retro-programming.de/programming/assembler/demo-effekte/flexible-line-distance-fld/)
- [FLD explained](http://www.0xc64.com/2015/11/17/simple-fld-effect/#:~:text=The%20FLD%20effect%20is%20generated%20by%20delaying%20the,line%20to%20fetch%20the%20next%20character%20row%20data)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
