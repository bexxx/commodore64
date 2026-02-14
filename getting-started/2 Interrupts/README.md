# Raster interrupt

This sample shows how to set up a raster interrupt to execute code at a specific position
of the raster beam on screen. 

The code in this example only sets the color of the border to a specific color and after some lines set it back to the original color.

With more precise timing this mechanism can be used to draw rasterbars.


# Nested raster interrupt

In case you have a long running rastre irq, but need short work to happen at specific rasters, those irqs can of course be nested (sure, the execution sum should alwazy be less than a frame to not look ugly). This example shows how to set up a second irq that fires while the first one is still running.