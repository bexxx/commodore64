# Invalid grafics mode

Setting the invalid text mode at one raster line and reset to default a couple of lines later. 
In each frame advance the start by one raster line. The start is within the border to demonstrate what happens.

You can see, that for the duration of the mode, only black pixels are shown, but the screen is left untouched. The whole mode change also only affects the screen and not the border.

Not super nice in this program, but with some sine values and better timing this could make a nice basic fader.

Used sources:
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
