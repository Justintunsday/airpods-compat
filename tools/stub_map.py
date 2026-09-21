#!/usr/bin/env python3
"""Map stub / GOT slot addresses back to their imported symbol names.

Works on regular Mach-O files (apps, dylibs) with an intact LC_DYSYMTAB
indirect symbol table - unlike dyld_shared_cache extracted images, which
have this metadata stripped.

Usage:
  py tools/stub_map.py --macho <file> [--filter <substr>] [--all]
"""
import argparse
import struct
import sys

SECTION_TYPE_MASK = 0xFF
S_NON_LAZY_SYMBOL_POINTERS = 0x6
S_LAZY_SYMBOL_POINTERS = 0x7
S_SYMBOL_STUBS = 0x8


def read_cstr(data, index):
    end = data.find(b"\0", index)
    return data[index:end].decode("utf-8", "replace")


def parse(path):
    data = open(path, "rb").read()
    magic = struct.unpack_from("<I", data, 0)[0]
    if magic != 0xFEEDFACF:
        raise SystemExit(f"not a 64-bit little-endian Mach-O: {magic:#x}")
    ncmds = struct.unpack_from("<I", data, 16)[0]

    sections = []
    symtab = None
    dysymtab = None
    offset = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == 0x2:
            symtab = struct.unpack_from("<IIII", data, offset + 8)
        elif cmd == 0xB:
            dysymtab = struct.unpack_from("<18I", data, offset + 8)
        elif cmd == 0x19:
            nsects = struct.unpack_from("<I", data, offset + 64)[0]
            sect_off = offset + 72
            for _ in range(nsects):
                sectname = read_cstr(data, sect_off)
                addr, size = struct.unpack_from("<QQ", data, sect_off + 32)
                flags, reserved1, reserved2 = struct.unpack_from("<III", data, sect_off + 64)
                sections.append((sectname, addr, size, flags, reserved1, reserved2))
                sect_off += 80
        offset += cmdsize

    if not symtab or not dysymtab:
        raise SystemExit("missing LC_SYMTAB/LC_DYSYMTAB")

    symoff, nsyms, stroff, strsize = symtab
    strings = data[stroff : stroff + strsize]

    def sym_name(index):
        n_strx = struct.unpack_from("<I", data, symoff + index * 16)[0]
        if n_strx >= len(strings):
            return None
        return read_cstr(strings, n_strx)

    indirect_off, indirect_count = dysymtab[12], dysymtab[13]
    indirect = [struct.unpack_from("<I", data, indirect_off + i * 4)[0] for i in range(indirect_count)]

    def indirect_name(index):
        if index >= len(indirect):
            return None
        sym_index = indirect[index]
        if sym_index == 0x80000000 or sym_index >= nsyms:
            return None
        return sym_name(sym_index)

    mappings = []
    for sectname, addr, size, flags, reserved1, reserved2 in sections:
        stype = flags & SECTION_TYPE_MASK
        if stype == S_SYMBOL_STUBS and reserved2:
            count = size // reserved2
            for i in range(count):
                name = indirect_name(reserved1 + i)
                if name:
                    mappings.append((addr + i * reserved2, "stub", name))
        elif stype in (S_NON_LAZY_SYMBOL_POINTERS, S_LAZY_SYMBOL_POINTERS):
            count = size // 8
            for i in range(count):
                name = indirect_name(reserved1 + i)
                if name:
                    mappings.append((addr + i * 8, "got", name))
    return mappings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--macho", required=True)
    parser.add_argument("--filter", default=None)
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()

    mappings = parse(args.macho)
    print(f"mappings: {len(mappings)}")
    for addr, kind, name in sorted(mappings):
        if args.filter and args.filter.lower() not in name.lower():
            continue
        print(f"  {addr:#x}  {kind:4}  {name}")


if __name__ == "__main__":
    main()
