#!/usr/bin/env python3
"""Dump the per-model closures of HeadphoneDevice.allFeatureContents.

Usage:
  py tools/dump_feature_closures.py --dylib <dylib> --segments <l> --symbols <n> \
      --version 27.0
"""
import argparse
import re
import sys

import capstone

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from disass_swift import parse_segments, parse_symbols, read_text  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--version", default="?")
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    data = open(args.dylib, "rb").read()

    def offset_of(address):
        for file_off, vm_start, size, _ in segments:
            if vm_start <= address < vm_start + size:
                return file_off + (address - vm_start)
        return None

    def name_of(address):
        return symbols.get(address)

    disassembler = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    disassembler.detail = True

    closures = {}
    for address, symbol in symbols.items():
        match = re.search(r"allFeatureContents.*FZ(AHyXEfU\d?_?)$", symbol)
        if match:
            closures[match.group(1) or "U_"] = address

    print(f"=== iOS {args.version}: {len(closures)} feature closures")
    for label in sorted(closures, key=lambda k: closures[k]):
        address = closures[label]
        offset = offset_of(address)
        print(f"\n-- {label or 'U_'} @ {hex(address)}")
        if offset is None:
            continue
        for insn in disassembler.disasm(data[offset:offset + 400], address):
            ops = insn.operands
            annotation = ""
            if insn.mnemonic in ("bl", "b") and ops and ops[0].type == capstone.arm64.ARM64_OP_IMM:
                annotation = name_of(ops[0].imm) or f"{ops[0].imm:#x} (external)"
            elif insn.mnemonic == "adrp" and ops:
                annotation = name_of(ops[1].imm) or ""
            if insn.mnemonic in ("cmp", "mov", "movz", "movk", "bl", "ret", "retab", "cbz", "cbnz", "ccmp", "b.eq", "b.ne"):
                print(f"   {insn.mnemonic:<6} {insn.op_str:<28} {annotation}")
            if insn.mnemonic in ("ret", "retab"):
                break


if __name__ == "__main__":
    main()
