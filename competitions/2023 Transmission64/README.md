# Fader for Transmission64

My interest in 6502 and Commodore 64 programming was sparked by an online class for 6502 Assembly game programming offered for free by the [Oldenburger Computer Museum](https://computermuseum-oldenburg.de/) and given by [Stefan H&ouml;ltgen](http://www.stefan-hoeltgen.de/). A while later I started to discover a lot of in depth programming resources and started to follow them and reimplement everything I could get my hands on. At this time I decided to join the C64 demo scene with my first contribution at the [Transmission64, 2023](http://www.transmission64.com/). The fader category is a good start for beginners, so here it is.
You can follow my journey in the directory "getting-started". Let me know how to improve or let me know of anything I should try to implement to get more practice!

Special thanks to [Fieser Wolf from Abyss Connection](https://englishclass.de/~wolf/ac/) for answering all my beginner questions with great patience ad suggesting improvements that really made an impact!

## Fader
I created a fader effect only in text mode. It has a couple of stages as follows:
1. chars on screen melt down into a single line
1. lines flow from center towards both sides (to clean up the "molten" chars)
1. blinds effect from top to bottom
1. color flash/fade to black

### Melting chars
Needs a copy of the charset from ROM to RAM and in 8 steps the bytes of each character will be copied to the next row, where the last line will be or'ed instead of simply stored. This gives a bit of a melting look. Because VIC banks are eing switched, the screen ram has to be copied as well. Also each start screen can have different border, background or character colors, so they need to be reset to a default to have the effect look the same on all machine configurations.

### Lines to sides
Synced to raster, increase/decrease column indexes to print a "_" in each line. Added white as bg for the outermost location to make it a bit more interesting.

### Blinds
Synced to raster, print whole lines of characters with bars of increasing height. This will give a blinds effect.

### Color flash
Used the list of c64 colors sorted by luminescence to fade from light blue to white and down to black. This is simply changing $d020 and $d021 on raster line 0 to the same values.

## Submission
In order to submit my fader I decided to go for a full disk image (.d64) instead of a single .prg file. This forced me to learn more about PETSCII, directories, ... 
I painted a screen of dimension 16x25 with the tool Petmate, created a .d64 out of it using the tool Dart. Then I copied my fader on this disk using Dirmaster and had to move it around and rename it a bit, because the tool cannot import a new file under an exiting name. 

Used sources/tools:
- [Petmate](https://nurpax.github.io/petmate/)
- [Dirmaster](https://style64.org/dirmaster)
- [Dart](https://csdb.dk/release/?id=226262&show=summary)
- [Directory Art Howto](https://mingos-commodorepage.com/tutorials/c64dirart.php)
- [Directory Art Inspired by Arcanum by Xenon, X Party 2000](https://csdb.dk/release/?id=11588)
- [C64 Wiki](https://www.c64-wiki.de/)
- [Exomizer2](https://github.com/bitshifters/exomizer)