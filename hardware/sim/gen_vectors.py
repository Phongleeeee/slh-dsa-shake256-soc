"""Generate independent SHAKE256 expected bytes for the RTL regression."""
from hashlib import shake_256
from pathlib import Path


def message(case: int) -> bytes:
    lengths = [0, 3, 135, 136, 137, 272, 2208]
    size = lengths[case]
    if case == 1:
        return b"abc"
    return bytes(i % 256 for i in range(size))


dest = Path(__file__).with_name("vectors.mem")
with dest.open("w", encoding="ascii") as output:
    for case in range(7):
        for byte in shake_256(message(case)).digest(200):
            output.write(f"{byte:02x}\n")
print(f"Generated {dest} (7 cases x 200 bytes)")
