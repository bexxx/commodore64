#!/usr/bin/env python3
"""
EasyFlash crt to double 4Mbit binary files converter
Converted from C++ to Python by GitHub Copilot
Original by e5frog 2020
"""

import sys
import os


def main():
    # Default values
    inputfilename = "easy.crt"
    pad = False
    chipsize = 524288
    infilesize = 1059998
    
    # Header to check
    header = b"C64 CARTRIDGE   "
    
    # Check command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] in ['-h', '/?', '-?', '/h']:
            print("\nEither drop a file on the icon, name file easy.crt and double-click or")
            print("use syntax: crt2chip2.py inputfile.crt from command line.")
            print("Outputs are called: inputfile_U4.bin and inputfile_U3.bin.")
            print("Program will assume a .crt (or other 4 char) suffix that will be stripped.")
            print("Using -p after filename pads the output files to full 512kB chipsize.\n\n")
            return 0
        
        inputfilename = sys.argv[1]
        
        if len(sys.argv) > 2 and sys.argv[2].lower() in ['-p', '/p']:
            pad = True
    
    print("\n\n*******************************************************************************")
    print("*     EasyFlash crt to double 4Mbit binary files converter by e5frog 2020     *")
    print("*******************************************************************************")
    print("\n\n")
    
    # Get filename without extension
    base_name = os.path.splitext(inputfilename)[0]
    
    # Set output filenames
    U4name = f"{base_name}_U4.bin"
    U3name = f"{base_name}_U3.bin"
    
    # Display information
    print(f"Input filename:\n{inputfilename}\n")
    print(f"U4 output file:\n{U4name}\n")
    print(f"U3 output file:\n{U3name}\n")
    
    # Check if input file exists
    if not os.path.exists(inputfilename):
        print(f"\a\nInput file error:\n{inputfilename}\nProgram will exit\n")
        return 1
    
    # Get file size
    filesize = os.path.getsize(inputfilename)
    
    if filesize > infilesize:
        print(f"\a\nFile seems to be too large:\n{inputfilename}\nWill try anyway...\n")
    
    try:
        with open(inputfilename, 'rb') as filin:
            # Check 16 byte header 'C64 CARTRIDGE   '
            file_header = filin.read(16)
            if file_header != header:
                print("\a\nIndata is missing valid .crt file header: \"C64 CARTRIDGE   \".")
                print("\nProgram will exit.\n")
                return 4
            
            # Read up to byte 23 to get hardware type
            filin.read(6)  # Skip bytes 16-21
            hw_type_bytes = filin.read(2)  # Bytes 22-23
            romsize = (hw_type_bytes[0] << 8) | hw_type_bytes[1]
            
            if romsize not in [0x0020, 0x0021]:
                print("\a\nWARNING, EasyFlash cartridge hardware type is not set in .crt.\n")
            
            readbytes = 24
            
            # Initialize chip buffers with 0xFF
            U4chip = bytearray([0xFF] * chipsize)
            U3chip = bytearray([0xFF] * chipsize)
            
            writeU4 = 0
            writeU3 = 0
            U4 = False
            
            # Process the file
            while readbytes < filesize:
                U4 = not U4  # Toggle which chip to output data to
                
                # Find CHIP header
                headbuffer = list(filin.read(4))
                readbytes += 4
                
                while not (headbuffer[0] == ord('C') and headbuffer[1] == ord('H') and
                          headbuffer[2] == ord('I') and headbuffer[3] == ord('P')):
                    if readbytes >= filesize:
                        print("\a\nNo valid CHIP header found.\nProgram will exit\n")
                        print(f"\nRead bytes: {readbytes}")
                        return 8
                    
                    # Shift characters and check again
                    headbuffer[0] = headbuffer[1]
                    headbuffer[1] = headbuffer[2]
                    headbuffer[2] = headbuffer[3]
                    headbuffer[3] = filin.read(1)[0]
                    readbytes += 1
                
                # CHIP header found, parse it
                packet_size_bytes = filin.read(4)  # Bytes 04-07
                readbytes += 4
                
                chip_type = filin.read(2)  # Bytes 08-09
                readbytes += 2
                
                bank_bytes = filin.read(2)  # Bytes 0A-0B
                readbytes += 2
                bankno = bank_bytes[1]
                
                address_bytes = filin.read(2)  # Bytes 0C-0D
                readbytes += 2
                addresspos = address_bytes[0]
                
                # Determine which chip based on address
                if addresspos == 0x80 and not U4:
                    U4 = True
                if addresspos != 0x80 and U4:
                    U4 = False
                
                rom_size_bytes = filin.read(2)  # Bytes 0E-0F
                readbytes += 2
                romsize = (rom_size_bytes[0] << 8) | rom_size_bytes[1]
                
                # Read ROM data
                rom_data = filin.read(romsize)
                readbytes += romsize
                
                # Store data in appropriate buffer
                position = bankno * romsize
                for i, byte in enumerate(rom_data):
                    pos = position + i
                    if U4:
                        U4chip[pos] = byte
                        if writeU4 <= pos:
                            writeU4 = pos + 1
                    else:
                        U3chip[pos] = byte
                        if writeU3 <= pos:
                            writeU3 = pos + 1
        
        # Write output files
        if pad:
            writeU4 = chipsize
            writeU3 = chipsize
        
        with open(U4name, 'wb') as filout1:
            filout1.write(U4chip[:writeU4])
        
        with open(U3name, 'wb') as filout2:
            filout2.write(U3chip[:writeU3])
        
        print("\nAll done.\n")
        print("*******************************************************************************\n")
        
        return 0
        
    except Exception as e:
        print(f"\a\nError processing file: {e}\n")
        return 1


if __name__ == "__main__":
    sys.exit(main())
