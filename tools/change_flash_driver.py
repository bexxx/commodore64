import argparse


def update_binary(input_file_hi_path: str, driver_file_path: str):   
    with open(input_file_hi_path, "r+b") as input_file:
        content = input_file.read()
        index = content.find("EAPI")
        if index != -1:
            print (f"Found EAPI driver at index: {index:#x}")
            input_file.seek(index)

            with open(driver_file_path, "rb") as driver_file:
                driver_file.seek(0, 2)  # Seek to end
                file_size = driver_file.tell()
                if file_size == 770:
                    print("Driver file has start address header, skipping first 2 bytes")
                    driver_file.seek(2)
                elif file_size == 768:
                    driver_file.seek(0)
                else:
                    raise ValueError("Driver file size is incorrect. Expected 768 or 770 bytes.")
                driver_data = driver_file.read(768)
                input_file.write(driver_data)
            print(f"File {input_file_hi_path} successfully updated")
        else:
            print(f"Input file {input_file_hi_path} not found.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Update binary file with flash driver')
    parser.add_argument('--driver_file', required=True, help='Flash driver file to update')
    parser.add_argument('--input_file_hi', required=True, help='High input file')
    
    args = parser.parse_args()
    
    update_binary(args.input_file_hi, args.driver_file)