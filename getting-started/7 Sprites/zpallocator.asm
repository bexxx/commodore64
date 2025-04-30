// orinally started by Geon (Victor Widell) on https://github.com/geon/c64-tests
// extended to support arrays, renamed to not assume (de)allocations.

#importonce
.filenamespace ZpAllocator

.var freeZpAddresses

.const @hardwiredPortRegisters = List().add($00, $01).lock()

.function @zpAllocatorInit(addressLists) {
	.eval freeZpAddresses = Hashtable()

	.for(var i=0; i<256; i++) {
		.eval freeZpAddresses.put(i, true)
	}

	.eval reserveUnsafeAddresses(addressLists)
}

.function reserveUnsafeAddresses(addressLists) {
	.for(var j=0; j<addressLists.size(); j++) {
		.var addressList = addressLists.get(j)
		.for(var i=0; i<addressList.size(); i++) {
			.eval allocateSpecificZpByte(addressList.get(i), "")
		}
	}
}

.function @allocateZpByte(name) {
	.for(var i=255; i>=0; i-=1) {
		.if(freeZpAddresses.containsKey(i)) {
            .print "Allocate ZP byte " + name + ": $" + toHexString(i)
            
			.return allocateSpecificZpByte(i, "")
		}
	}

	.errorif true, "No free bytes available in zero page."
}

.function @allocateZpBytes(count, name) {
	.for(var i=255-count; i>=0; i--) {
        .var foundIndex = true
        .for(var j=0; j < count; j++) {
            .if (!freeZpAddresses.containsKey(i+j)) {
                .eval foundIndex = false
            }
        }

        .if (foundIndex) {
            .print "Allocate ZP " + name + ": $" + toHexString(i) + "-$" + toHexString(i+count-1)

            .for(var j=0; j < count; j++) {
                .eval allocateSpecificZpByte(i+j, "")
            }

            .return i
        }
	}

	.error "No free bytes available in zero page for array of size" + count + "."
}



.function @allocateZpWord(name) {
	.for(var i=0; i<256; i+=2) {
		.if(freeZpAddresses.containsKey(i) && freeZpAddresses.containsKey(i+1)) {
			.var lowByte = allocateSpecificZpByte(i, name)
			.eval allocateSpecificZpByte(i+1, name)
            .if (name.size() > 0) {
                .print "Allocate ZP word $" + toHexString(i) + " + $" + toHexString(i+1)
            } 
			.return lowByte
		}
	}

	.errorif true, "No free words available in zero page."
}

.function @allocateSpecificZpByte(requestedAddress, name) {
	.errorif !freeZpAddresses.containsKey(requestedAddress), "Address $"+toHexString(requestedAddress)+" is taken."
	.eval freeZpAddresses.remove(requestedAddress)
    .if (name.size() > 0) {
        .print "Allocate specific ZP byte " + name + ": $" + toHexString(requestedAddress)
    }
	.return requestedAddress
}

.function @allocateSpecificZpWord(requestedAddress, name) {
	.var address = allocateSpecificZpByte(requestedAddress, name)
	.eval allocateSpecificZpByte(requestedAddress+1, name)
	.return address
}

.function @deallocateZpByte(freeAddress) {
	.errorif freeZpAddresses.containsKey(freeAddress), "Address $"+toHexString(freeAddress)+" is aldready free."
	.eval freeZpAddresses.put(freeAddress, true)
}

.function @deallocateZpWord(freeAddress) {
	.eval @deallocateZpByte(freeAddress)
	.eval @deallocateZpByte(freeAddress+1)
}