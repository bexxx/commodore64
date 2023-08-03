# Double Raster aka stable raster

This example shows how to time code exactly to the raster beam to be in full control about when code happens.
It is highly important to master this because a lot of effects only work when being executed cycle acurrate at
specific times.

The main idea is to set up a first raster interrupt to initiate the timed execution. The next stage is setting up a second raster interrupt AND be in control of the code that is executing when that interrupt fires (to avoid randomness of execution cycles of different opcodes). With that only the last cycle differences need to smoothened out with a conditional jump which takes different cycles depending on condition hit or miss.

Another trick is to not leave the first interrupt routine with rti and instead save the stack pointer and 
use it in the second interrupt to return properly with rti.

Used sources:
- [Retro Programming, Raster articles](https://www.retro-programming.de/programming/nachschlagewerk/interrupts/]der-rasterzeileninterrupt/raster-irq-endlich-stabil/)
- [C64 wiki, Raster interrupt](https://www.c64-wiki.de/wiki/Rasterzeilen-Interrupt)
- [C64 wiki, Zeropage](https://www.c64-wiki.de/wiki/Zeropage)
- [C64 wiki, VIC](https://www.c64-wiki.de/wiki/VIC)
- [C64 wiki, CIA](https://www.c64-wiki.de/wiki/CIA)
- [KickAssembler manual](http://theweb.dk/KickAssembler/KickAssembler.pdf)