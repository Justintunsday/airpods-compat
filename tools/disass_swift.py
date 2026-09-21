#!/usr/bin/env python3
"""Disassemble a Swift function from an extracted dyld_shared_cache dylib.

Usage:
  py tools/disass_swift.py --dylib <dylib> --segments <info -l output> \
      --symbols <info -n output> --addr 0x2027139b0 [--count 200]
"""
import argparse
import re
import struct
import sys

try:
    import capstone
except ImportError:  # pragma: no cover
    print("capstone required: py -m pip install capstone", file=sys.stderr)
    raise


def read_text(path):
    raw = open(path, "rb").read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16", errors="replace")
    return raw.decode("utf-8", errors="replace")


def parse_segments(path):
    segments = []
    pattern = re.compile(
        r"off=0x([0-9a-f]+)-0x[0-9a-f]+\s+addr=0x([0-9a-f]+)-0x([0-9a-f]+).*?\s(\S+)\s*$"
    )
    for line in read_text(path).splitlines():
        match = pattern.search(line.strip())
        if match:
            segments.append((
                int(match.group(1), 16),
                int(match.group(2), 16),
                int(match.group(3), 16) - int(match.group(2), 16),
                match.group(4),
            ))
    return segments


def parse_symbols(path):
    symbols = {}
    pattern = re.compile(r"^0x([0-9a-f]+):.*?\t(.*)$")
    for line in read_text(path).splitlines():
        match = pattern.match(line.rstrip())
        if match:
            symbols[int(match.group(1), 16)] = match.group(2).strip()
    return symbols


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--addr", required=True)
    parser.add_argument("--count", type=int, default=200)
    parser.add_argument("--filter", default=None)
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

    address = int(args.addr, 16)
    offset = offset_of(address)
    if offset is None:
        print(f"address {hex(address)} not mapped in this dylib", file=sys.stderr)
        raise SystemExit(1)

    disassembler = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    disassembler.detail = True

    registers = {}
    printed = 0
    for insn in disassembler.disasm(data[offset:offset + args.count * 4], address):
        ops = insn.operands
        note = ""
        if insn.mnemonic == "adrp":
            registers[insn.reg_name(ops[0].reg)] = ops[1].imm
            target = name_of(ops[1].imm)
            note = f"  ; {target}" if target else f"  ; {ops[1].imm:#x}"
        elif insn.mnemonic == "add" and len(ops) == 3 and ops[2].type == capstone.arm64.ARM64_OP_IMM:
            base = registers.get(insn.reg_name(ops[1].reg))
            if base is not None:
                value = base + ops[2].imm
                registers[insn.reg_name(ops[0].reg)] = value
                target = name_of(value)
                note = f"  ; {target}" if target else f"  ; {value:#x}"
        elif insn.mnemonic in ("bl", "b") and ops and ops[0].type == capstone.arm64.ARM64_OP_IMM:
            target = name_of(ops[0].imm)
            note = f"  ; -> {target}" if target else f"  ; -> {hex(ops[0].imm)} (external)"
        line = f"{insn.address:#012x}  {insn.mnemonic:<10} {insn.op_str}{note}"
        if args.filter and args.filter.lower() not in line.lower():
            registers_note = line
        print(line)
        printed += 1
        if insn.mnemonic in ("ret", "retab") and printed > 5:
            break


if __name__ == "__main__":
    main()
