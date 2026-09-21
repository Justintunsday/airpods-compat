#!/usr/bin/env python3
"""Find direct callers (b/bl) of a target address inside an extracted dylib.

Uses raw instruction-encoding pattern matching (no linear disassembly) so the
result is immune to data islands / desynced decoding inside __TEXT.

Usage:
  py tools/find_callers.py --dylib <dylib> --segments <info -l> --symbols <info -n> \
      --target 0x202727b50
"""
import argparse
import struct
import sys

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from disass_swift import parse_segments, parse_symbols  # noqa: E402


def sign_extend(value, bits):
    if value & (1 << (bits - 1)):
        value -= 1 << bits
    return value


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--target", required=True)
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    sorted_symbols = sorted(symbols.items())
    data = open(args.dylib, "rb").read()
    target = int(args.target, 16)

    def nearest_symbol(address):
        best = None
        for addr, name in sorted_symbols:
            if addr <= address:
                best = (addr, name)
            else:
                break
        return best

    hits = []
    for file_off, vm_start, size, name in segments:
        if not name.startswith("__TEXT"):
            continue
        end = min(file_off + size, len(data))
        for offset in range(file_off, end - 3, 4):
            word = struct.unpack_from("<I", data, offset)[0]
            opcode = word & 0xFC000000
            if opcode not in (0x94000000, 0x14000000):  # bl / b
                continue
            immediate = sign_extend(word & 0x03FFFFFF, 26) << 2
            address = vm_start + (offset - file_off)
            if address + immediate == target:
                hits.append(address)

    print(f"callers of {hex(target)}: {len(hits)}")
    for address in hits:
        symbol = nearest_symbol(address)
        print(f"  {hex(address)}  in {symbol[1] if symbol else '?'} "
              f"(+{address - symbol[0] if symbol else 0:#x})")


if __name__ == "__main__":
    main()
