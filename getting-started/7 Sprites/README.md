# Sprites

## Top Border Sprites

Displaying sprites by enabling and configuring them and moving them into the upper border.

Tasks:
    - learn sprites, config and data placement (damn 64th byte!)
    - time code to open borders AND to disable sprites to avoid showing them on bottom border too

## SpriteScrollerHorizontal

Task:
    - move sprites smoothly through all x coords handling x coord value overflow as needed
    - add sine data to y coords just because
    - use multicolor charset to fill multicolor sprites, stretch them in both dimensions to fill screen
    - spread them over the screen evenly to look good

    This is the first time I totally underestimated the complexity and had to rewrite the parts multiple times.
    I am using a buffer to sort the sprite numbers as shown on screen to simplify my life and to reduce cycles.
    
    Thanks Fieser Wolf^Abyss Connection for the homework!

## Starfield

    Move sprites with single pixel in different speeds over the screen. Took codebase64 code, added more randomness and changed direction.

Used sources:
- [Retro-programming blog](https://www.retro-programming.de/programming/assembler/demo-effekte/oberen-unteren-rand-offnen/)
- [THE vic ii text](http://www.zimmers.net/cbmpics/cbm/c64/vic-ii.txt)
- [06.prg, multicolor Font, unknown source](404)
- [Coebase64, Sprite Starfield](https://codebase64.org/doku.php?id=base:8_sprite_starfield&s[]=sprite&s[]=starfield)
