#import "vic_constants.inc"

.function rasterLineOfBadLine(number, yscroll) {
    .return $30 + (number * 8) + yscroll
}

.function rasterLineOfBadLine(number) {
    .return rasterLineOfBadLine(number, %011)
}