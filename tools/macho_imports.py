#!/usr/bin/env python3
"""List imported/undefined symbols of a Mach-O (dylib) and optionally filter.

Usage:
  py tools/macho_imports.py --macho <file> [--filter FeatureContent]
"""
import argparse
import struct
import sys


def parse(path):
    data = open(path, "rb").read()
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        raise SystemExit(f"not a 64-bit little-endian Mach-O: {hex(magic)}")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    offset = 32
    symtab = None
    dysymtab = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == 0x2:  # LC_SYMTAB
            symoff, nsyms, stroff, strsize = struct.unpack_from("<IIII", data, offset + 8)
            symtab = (symoff, nsyms, stroff, strsize)
        elif cmd == 0xB:  # LC_DYSYMTAB
            fields = struct.unpack_from("<18I", data, offset + 8)
            dysymtab = fields
        offset += cmdsize

    if not symtab:
        return [], []

    symoff, nsyms, stroff, strsize = symtab
    strings = data[stroff:stroff + strsize]

    def name_at(index):
        end = strings.find(b"\0", index)
        return strings[index:end].decode("utf-8", "replace") if index < len(strings) else "?"

    symbols = []
    for i in range(nsyms):
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from(
            "<IBBHQ", data, symoff + i * 16)
        symbols.append((i, n_type, n_value, name_at(n_strx)))

    undefined = [(name, value) for _, n_type, value, name in symbols if (n_type & 0x0E) == 0x00]
    defined = [(name, value) for _, n_type, value, name in symbols if (n_type & 0x0E) != 0x00]

    indirect_names = []
    if dysymtab:
        indirect_off, indirect_count = dysymtab[13], dysymtab[14]
        for i in range(indirect_count):
            index = struct.unpack_from("<I", data, indirect_off + i * 4)[0]
            if index != 0x80000000 and index < len(symbols):
                indirect_names.append(symbols[index][3])

    return undefined, defined, indirect_names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--macho", required=True)
    parser.add_argument("--filter", default=None)
    parser.add_argument("--indirect", action="store_true")
    args = parser.parse_args()

    undefined, defined, indirect = parse(args.macho)
    pool = indirect if args.indirect else [name for name, _ in undefined]
    label = "indirect" if args.indirect else "undefined"
    print(f"{label} symbols: {len(pool)}")
    for name in sorted(set(pool)):
        if args.filter and args.filter.lower() not in name.lower():
            continue
        print("   ", name)


if __name__ == "__main__":
    main()
