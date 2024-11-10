#importonce 

#import "vic_constants.inc"

.function rasterLineOfBadLine(badLineNumber, yscroll) {
    .return $30 + (badLineNumber * 8) + yscroll
}

.function rasterLineOfBadLine(badLineNumber) {
    .return rasterLineOfBadLine(badLineNumber, %011)
}