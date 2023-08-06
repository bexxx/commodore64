import math

def build_sinetabe(maxValue, steps):
    numbers = []
    for step in range(0, steps):       
        numbers.append(math.ceil(math.sin((math.pi/(steps-1))*step) * maxValue))
    return numbers

def split(list_a, chunk_size):
  for i in range(0, len(list_a), chunk_size):
    yield list_a[i:i + chunk_size]

numbers = build_sinetabe(150, 150)
chunks = list(split(numbers, 16))
lineformat = "  .byte {0}"
for chunk in chunks:
    print("\t.byte " + ', '.join("$%02X" % c for c in chunk))
