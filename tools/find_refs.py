#!/usr/bin/env python3
"""Find ADRP/ADD (and ADRP/LDR) references to target addresses in a dylib.

Pattern-based (no linear disassembly) so data islands cannot desync decoding.

Usage:
  py tools/find_refs.py --dylib <dylib> --segments <info -l> --symbols <info -n> \
      --targets 0x...[,0x...] [--conformance 0xADMc]
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
    parser.add_argument("--targets", default="")
    parser.add_argument("--conformance", default=None)
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    sorted_symbols = sorted(symbols.items())
    data = open(args.dylib, "rb").read()

    def offset_of(address):
        for file_off, vm_start, size, _ in segments:
            if vm_start <= address < vm_start + size:
                return file_off + (address - vm_start)
        return None

    targets = {int(item, 16) for item in filter(None, args.targets.split(","))}
    if args.conformance:
        conformance = int(args.conformance, 16)
        offset = offset_of(conformance)
        if offset is not None:
            delta = struct.unpack_from("<i", data, offset)[0]
            protocol = conformance + delta
            print(f"conformance {hex(conformance)} -> protocol descriptor {hex(protocol)}")
            targets.add(protocol)

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
        pages = {}  # reg -> (page, address)
        for offset in range(file_off, end - 3, 4):
            word = struct.unpack_from("<I", data, offset)[0]
            address = vm_start + (offset - file_off)
            if (word & 0x9F000000) == 0x90000000:  # adrp
                rd = word & 0x1F
                immhi = (word >> 5) & 0x7FFFF
                immlo = (word >> 29) & 0x3
                imm = sign_extend((immhi << 2) | immlo, 21) << 12
                pages[rd] = ((address & ~0xFFF) + imm, address)
                continue
            if (word & 0xFF000000) == 0x91000000:  # add xD, xN, #imm
                rd = word & 0x1F
                rn = (word >> 5) & 0x1F
                imm12 = (word >> 10) & 0xFFF
                shift = (word >> 22) & 0x1
                base = pages.get(rn)
                if base and address - base[1] <= 16:
                    value = base[0] + (imm12 << 12 if shift else imm12)
                    if value in targets:
                        hits.append((address, value))
                continue
            if (word & 0xFF000000) == 0xF9400000:  # ldr xD, [xN, #imm]
                rn = (word >> 5) & 0x1F
                imm12 = (word >> 10) & 0xFFF
                base = pages.get(rn)
                if base and address - base[1] <= 16:
                    value = base[0] + imm12 * 8
                    if value in targets:
                        hits.append((address, value))

    print(f"references: {len(hits)}")
    for address, value in hits:
        symbol = nearest_symbol(address)
        print(f"  {hex(address)} -> {hex(value)}  in {symbol[1] if symbol else '?'} "
              f"(+{address - symbol[0] if symbol else 0:#x})")


if __name__ == "__main__":
    main()
