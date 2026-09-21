#!/usr/bin/env python3
"""Find direct callers (bl) of a target address inside an extracted dylib.

Usage:
  py tools/find_callers.py --dylib <dylib> --segments <info -l> --symbols <info -n> \
      --target 0x1dcbbfdcc
"""
import argparse
import sys

import capstone

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from disass_swift import parse_segments, parse_symbols  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--target", required=True)
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    data = open(args.dylib, "rb").read()
    target = int(args.target, 16)

    sorted_symbols = sorted(symbols.items())
    def nearest_symbol(address):
        best = None
        for addr, name in sorted_symbols:
            if addr <= address:
                best = (addr, name)
            else:
                break
        return best

    disassembler = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    hits = []
    for file_off, vm_start, size, name in segments:
        if name != "__TEXT" or file_off >= len(data):
            continue
        code = data[file_off:file_off + size]
        for insn in disassembler.disasm(code, vm_start):
            if insn.mnemonic not in ("bl", "b") or not insn.operands:
                continue
            if insn.operands[0].type != capstone.arm64.ARM64_OP_IMM:
                continue
            if insn.operands[0].imm == target:
                hits.append(insn.address)

    print(f"callers of {hex(target)}: {len(hits)}")
    for address in hits:
        symbol = nearest_symbol(address)
        print(f"  {hex(address)}  in {symbol[1] if symbol else '?'} (+{address - symbol[0] if symbol else 0:#x})")


if __name__ == "__main__":
    main()
