#!/usr/bin/env python3
"""Find ADRP/ADD references (data or protocol-descriptor references) to a set of
addresses inside an extracted dylib.

Usage:
  py tools/find_refs.py --dylib <dylib> --segments <info -l> --symbols <info -n> \
      --targets 0x...,0x...

Also exposes --conformance <ADMc address> to resolve the protocol descriptor
referenced by a Swift conformance descriptor (first relative pointer).
"""
import argparse
import struct
import sys

import capstone

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from disass_swift import parse_segments, parse_symbols  # noqa: E402


def offset_of(segments, address):
    for file_off, vm_start, size, _ in segments:
        if vm_start <= address < vm_start + size:
            return file_off + (address - vm_start)
    return None


def nearest_symbol(sorted_symbols, address):
    best = None
    for addr, name in sorted_symbols:
        if addr <= address:
            best = (addr, name)
        else:
            break
    return best


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--targets", default="")
    parser.add_argument("--conformance", default=None,
                        help="address of a Swift conformance descriptor (ADMc); "
                             "resolves and prints the protocol descriptor")
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    sorted_symbols = sorted(symbols.items())
    data = open(args.dylib, "rb").read()

    targets = set()
    for item in filter(None, args.targets.split(",")):
        targets.add(int(item, 16))

    if args.conformance:
        conformance = int(args.conformance, 16)
        offset = offset_of(segments, conformance)
        if offset is None:
            print("conformance descriptor not mapped", file=sys.stderr)
            raise SystemExit(1)
        delta = struct.unpack_from("<i", data, offset)[0]
        protocol = conformance + delta
        print(f"conformance {hex(conformance)} -> protocol descriptor {hex(protocol)}")
        targets.add(protocol)

    disassembler = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    disassembler.detail = True

    hits = []
    for file_off, vm_start, size, name in segments:
        if name != "__TEXT":
            continue
        registers = {}
        code = data[file_off:file_off + size]
        for insn in disassembler.disasm(code, vm_start):
            ops = insn.operands
            if insn.mnemonic == "adrp":
                registers[insn.reg_name(ops[0].reg)] = ops[1].imm
            elif insn.mnemonic == "add" and len(ops) == 3 and ops[2].type == capstone.arm64.ARM64_OP_IMM:
                base = registers.get(insn.reg_name(ops[1].reg))
                if base is not None:
                    value = base + ops[2].imm
                    if value in targets:
                        hits.append((insn.address, value))

    print(f"references: {len(hits)}")
    for address, value in hits:
        symbol = nearest_symbol(sorted_symbols, address)
        print(f"  {hex(address)} -> {hex(value)}  in {symbol[1] if symbol else '?'} "
              f"(+{address - symbol[0] if symbol else 0:#x})")


if __name__ == "__main__":
    main()
