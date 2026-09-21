#!/usr/bin/env python3
"""Disassemble around one or more call sites with symbol / stub annotations.

Unlike tools/disass_swift.py (which starts at an arbitrary address), this tool
snaps to LC_FUNCTION_STARTS boundaries and resolves:
  - adrp/add pairs to the nearest defined symbol
  - ldr from a tracked adrp page to stub/GOT symbol names (tools/stub_map.py)
  - bl/b targets to stub symbol names or nearest defined symbol

Usage:
  py tools/disass_context.py --dylib <macho> --segments <info -l> --symbols <info -n> \
      --starts <info -f> [--stubs <stub_map output>] --addrs 0x1000d7358[,0x...] [--before 0x160]
"""
import argparse
import re
import sys

import capstone

sys.path.insert(0, __file__.rsplit("\\", 1)[0].rsplit("/", 1)[0])
from disass_swift import parse_segments, parse_symbols, read_text  # noqa: E402


def load_starts(path):
    starts = []
    for line in read_text(path).splitlines():
        match = re.match(r"^0x([0-9a-f]+)", line.strip())
        if match:
            starts.append(int(match.group(1), 16))
    return sorted(starts)


def load_stubs(path):
    stubs = {}
    for line in read_text(path).splitlines():
        match = re.match(r"\s*(0x[0-9a-f]+)\s+(\w+)\s+(\S+)", line)
        if match:
            stubs[int(match.group(1), 16)] = match.group(3)
    return stubs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--starts", required=True)
    parser.add_argument("--stubs", default=None)
    parser.add_argument("--addrs", required=True)
    parser.add_argument("--before", type=lambda v: int(v, 0), default=0x160)
    parser.add_argument("--after", type=lambda v: int(v, 0), default=0x100)
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    starts = load_starts(args.starts)
    stubs = load_stubs(args.stubs) if args.stubs else {}
    data = open(args.dylib, "rb").read()

    def offset_of(address):
        for file_off, vm_start, size, _ in segments:
            if vm_start <= address < vm_start + size:
                return file_off + (address - vm_start)
        return None

    def nearest_start(address):
        best = 0
        for start in starts:
            if start <= address:
                best = start
            else:
                break
        return best

    def nearest_symbol(address):
        best = (0, "?")
        for addr, name in sorted(symbols.items()):
            if addr <= address:
                best = (addr, name)
            else:
                break
        return best

    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    md.detail = True

    for item in args.addrs.split(","):
        addr = int(item, 16)
        start = max(nearest_start(addr), addr - args.before)
        offset = offset_of(start)
        sym_addr, sym_name = nearest_symbol(start)
        print(f"##### {addr:#x} in func {start:#x} ({sym_name} +{start - sym_addr:#x}) #####")
        regs = {}
        for insn in md.disasm(data[offset : offset + (addr - start + args.after)], start):
            ops = insn.operands
            note = ""
            if insn.mnemonic == "adrp":
                regs[insn.reg_name(ops[0].reg)] = ops[1].imm
                sa, sn = nearest_symbol(ops[1].imm)
                note = f"  ; {sn} +{ops[1].imm - sa:#x}" if sn != "?" else f"  ; {ops[1].imm:#x}"
            elif insn.mnemonic == "add" and len(ops) == 3 and ops[2].type == capstone.arm64.ARM64_OP_IMM:
                base = regs.get(insn.reg_name(ops[1].reg))
                if base is not None:
                    value = base + ops[2].imm
                    regs[insn.reg_name(ops[0].reg)] = value
                    note = f"  ; {value:#x}"
            elif insn.mnemonic == "ldr" and len(ops) == 2 and ops[1].type == capstone.arm64.ARM64_OP_MEM:
                base = regs.get(insn.reg_name(ops[1].mem.base))
                if base is not None:
                    value = base + ops[1].mem.disp
                    name = stubs.get(value)
                    note = f"  ; GOT {name}" if name else f"  ; {value:#x}"
            elif insn.mnemonic in ("bl", "b") and ops and ops[0].type == capstone.arm64.ARM64_OP_IMM:
                target = ops[0].imm
                name = stubs.get(target)
                if name is None:
                    sa, sn = nearest_symbol(target)
                    name = f"{sn} +{target - sa:#x}" if sn != "?" else None
                note = f"  ; -> {name}" if name else f"  ; -> {target:#x}"
            marker = "  <== CALL" if insn.address == addr else ""
            print(f"{insn.address:#014x}  {insn.mnemonic:<9} {insn.op_str}{note}{marker}")


if __name__ == "__main__":
    main()
