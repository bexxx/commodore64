import sys
 
file = open(sys.argv[1], "rb")

#data = file.read(2)

data = file.read(16)

# Printing data by iterating with while loop
while data:
    print ("    .byte ", end= "")
    for d in data:
#        i = ord(d)   # Get the integer value of the byte
        hex = "${0:x}, ".format(d) # hexadecimal: ff    
        print(hex, end="")
    print("")
    data = file.read(16)

# Close the binary file
file.close()