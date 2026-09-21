#!/usr/bin/env python3
"""Read raw bytes from a split dyld_shared_cache by VM address.

Each subcache file carries its own dyld_cache_header with a mapping table, so
we can map any VM address to (file, file offset) without ipsw.

Usage:
  py tools/dsc_read.py --dsc-dir <com.apple.dyld dir> --addr 0x27090e3f8 [--count 4]
"""
import argparse
import glob
import os
import struct


def load_subcaches(directory):
    entries = []
    for path in glob.glob(os.path.join(directory, "dyld_shared_cache_arm64e*")):
        if path.endswith((".symbols", ".atlas")):
            continue
        try:
            with open(path, "rb") as handle:
                header = handle.read(0x400)
        except OSError:
            continue
        if len(header) < 0x30 or not header.startswith(b"dyld_v1"):
            continue
        mapping_offset, mapping_count = struct.unpack_from("<II", header, 0x10)
        for index in range(mapping_count):
            base = mapping_offset + index * 32
            if base + 32 > len(header):
                continue
            address, size, file_offset = struct.unpack_from("<QQQ", header, base)
            if size:
                entries.append((address, size, path, file_offset))
    entries.sort()
    return entries


def find(entries, address):
    for start, size, path, file_offset in entries:
        if start <= address < start + size:
            return start, path, file_offset
    return None


def read_bytes(entries, address, length):
    hit = find(entries, address)
    if not hit:
        return None
    start, path, file_offset = hit
    offset = file_offset + (address - start)
    with open(path, "rb") as handle:
        handle.seek(offset)
        return handle.read(length)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dsc-dir", required=True)
    parser.add_argument("--addr", required=True)
    parser.add_argument("--count", type=int, default=8)
    args = parser.parse_args()

    entries = load_subcaches(args.dsc_dir)
    address = int(args.addr, 16)
    print(f"subcaches: {len(entries)}")
    hit = find(entries, address)
    if not hit:
        print("address not mapped")
        return
    start, path, file_offset = hit
    print(f"{hex(address)} -> {os.path.basename(path)} (base {hex(start)}, fileOff {hex(file_offset)})")
    raw = read_bytes(entries, address, args.count * 8)
    values = struct.unpack(f"<{args.count}Q", raw)
    for index, value in enumerate(values):
        print(f"  [{index}] {hex(address + index * 8)} = {hex(value)}")


if __name__ == "__main__":
    main()
