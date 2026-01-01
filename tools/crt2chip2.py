"""
EasyFlash crt to double 4Mbit binary files converter
Converted from C++ to Python by GitHub Copilot. Touched by a human.
Original by e5frog 2020

To generate the driver binaries, download/clone the EasyFlash repository: hhttps://gitlab.com/easyflash/eapi
Go to directory eapi and type `make all` to generate the driver binaries.
Alternatively, download them from this Forum64 post: https://www.forum64.de/index.php?thread/153004-easyflash-1-eproms-mit-eprommer-brennen-t48-tl866/&postID=2304299#post2304299

Note on placement of the flash ICs:
The U3 flash IC will be placed in the lower socket of the EasyFlash cartridge PCB, closer to the edge connector.
The U4 flash IC will be placed in the upper socket of the EasyFlash cartridge PCB,
"""

import sys
import os
import argparse


def main():
    # Set up argument parser
    parser = argparse.ArgumentParser(
        description='EasyFlash crt to double 4Mbit binary files converter',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s inputfile.crt
  %(prog)s inputfile.crt -p
  %(prog)s inputfile.crt --pad
  %(prog)s inputfile.crt --pad --verbose

Output files are named: inputfile_U4.bin and inputfile_U3.bin
The program will strip the file extension from the input filename.
        """
    )
    
    parser.add_argument(
        'inputfile',
        nargs='?',
        default='inputfile.crt',
        help='Input CRT file (default: inputfile.crt)'
    )
    
    parser.add_argument(
        '-p', '--pad',
        action='store_true',
        help='Pad output files to full 512kB chip size'
    )

    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )

    parser.add_argument(
        '-d', '--driver',
        help='Update driver to given binary'
    )

    args = parser.parse_args()
    
    # Get parsed values
    inputfilename = args.inputfile
    driver_filename = args.driver
    pad = args.pad
    verbose = args.verbose
    chipsize = 524288
    infilesize = 1059998
    
    # Header to check
    header = b"C64 CARTRIDGE   "
    
    print("********************************************************************************")
    print("* EasyFlash crt to double 4Mbit binary files converter, based on e5frog's tool *")
    print("********************************************************************************")
    print("\n")
    
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

    # Check if driver file exists
    if not os.path.exists(driver_filename):
        print(f"\a\nDriver file error:\n{driver_filename}\nProgram will exit\n")
        return 1

    driver_file_size = os.path.getsize(driver_filename)
    if driver_file_size not in [768, 770]:
        print("\a\nDriver file size is incorrect. Expected 768 or 770 bytes.\nProgram will exit\n")
        return 1

    # Get file size
    filesize = os.path.getsize(inputfilename)
    
    if filesize > infilesize:
        print(f"\a\nFile seems to be too large:\n{inputfilename}\nWill try anyway...\n")
    
    if verbose:
        print(f"\nFile size is {hex(filesize)}\n")

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
            if verbose:
                print("Header OK")

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
                    if verbose:
                        print("Checking CHIP header")

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
                if verbose:
                    print("'CHIP' found, move forward")
                    print("CHIP header found")

                # CHIP header found, parse it
                packet_size_bytes = filin.read(4)  # Bytes 04-07
                readbytes += 4
                
                chip_type = filin.read(2)  # Bytes 08-09
                readbytes += 2
                
                bank_bytes = filin.read(2)  # Bytes 0A-0B
                readbytes += 2
                bankno = bank_bytes[1]
                if verbose:
                    print(f"Bank number: {bankno}")

                address_bytes = filin.read(2)  # Bytes 0C-0D
                readbytes += 2
                addresspos = address_bytes[0]
                
                if verbose:
                    print(f"Address of this packet: {hex(addresspos)}")

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
        
        if driver_filename: 
            with open(driver_filename, "rb") as driver_file:
                if driver_file_size == 770:
                    print("Driver file has start address prefix header, skipping first 2 bytes")
                    driver_file.seek(2)
                driver_data = driver_file.read(768)

                index = U3chip.find(b"eapi")
                if index == -1:
                    print("Could not find EAPI driver signature in U4 data, driver update failed")
                    return 1
                
                print (f"Found EAPI driver at index: {hex(index)} in U3 data, updating driver data")
                U3chip[index:index+768] = driver_data
          
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
