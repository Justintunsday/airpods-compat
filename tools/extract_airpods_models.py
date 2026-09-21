#!/usr/bin/env python3
"""Extract the full AirPods model table from a CoreUARP dyld_shared_cache dylib.

Usage:
  py tools/extract_airpods_models.py \
      --dylib path/to/CoreUARP \
      --segments path/to/macho_info_l.txt \
      --objc path/to/macho_info_o.txt \
      --symbols path/to/macho_info_n.txt \
      --out-json models/airpods.json \
      --out-plist "tweak/layout/Library/Application Support/AirPodsCompat/AirPodsCompatModels.plist" \
      --out-app-json app/Resources/Models.json
"""
import argparse
import json
import re
import struct
import sys

try:
    import capstone
except ImportError:  # pragma: no cover
    print("capstone is required: py -m pip install capstone", file=sys.stderr)
    raise

# Apple KB109525 - model number -> (display name, family hint)
KB_MODELS = {
    "A3531": ("AirPods 5", "bud"),
    "A3532": ("AirPods 5", "bud"),
    "A3533": ("AirPods 5", "bud"),
    "A3439": ("AirPods 5 (Wireless Charging)", "bud"),
    "A3440": ("AirPods 5 (Wireless Charging)", "bud"),
    "A3441": ("AirPods 5 (Wireless Charging)", "bud"),
    "A3529": ("AirPods 5 (Charging Case)", "case"),
    "A3530": ("AirPods 5 (Wireless Charging Case)", "caseUSB"),
    "A3053": ("AirPods 4", "bud"),
    "A3050": ("AirPods 4", "bud"),
    "A3054": ("AirPods 4", "bud"),
    "A3056": ("AirPods 4 (ANC)", "bud"),
    "A3055": ("AirPods 4 (ANC)", "bud"),
    "A3057": ("AirPods 4 (ANC)", "bud"),
    "A3058": ("AirPods 4 (Charging Case)", "case"),
    "A3059": ("AirPods 4 (Wireless Charging Case)", "case"),
    "A3063": ("AirPods Pro 3", "bud"),
    "A3064": ("AirPods Pro 3", "bud"),
    "A3065": ("AirPods Pro 3", "bud"),
    "A3122": ("AirPods Pro 3 (MagSafe Charging Case)", "case"),
    "A3047": ("AirPods Pro 2 (USB-C)", "bud"),
    "A3048": ("AirPods Pro 2 (USB-C)", "bud"),
    "A3049": ("AirPods Pro 2 (USB-C)", "bud"),
    "A2968": ("AirPods Pro 2 (USB-C Case)", "case"),
    "A2931": ("AirPods Pro 2", "bud"),
    "A2699": ("AirPods Pro 2", "bud"),
    "A2698": ("AirPods Pro 2", "bud"),
    "A2700": ("AirPods Pro 2 (Charging Case)", "case"),
    "A2565": ("AirPods 3", "bud"),
    "A2564": ("AirPods 3", "bud"),
    "A2566": ("AirPods 3 (Charging Case)", "case"),
    "A2897": ("AirPods 3 (Lightning Case)", "case"),
    "A3454": ("AirPods Max 2", "bud"),
    "A3184": ("AirPods Max (USB-C)", "bud"),
    "A2096": ("AirPods Max", "bud"),
    "A2084": ("AirPods Pro", "bud"),
    "A2083": ("AirPods Pro", "bud"),
    "A2190": ("AirPods Pro (Charging Case)", "case"),
    "A2032": ("AirPods 2", "bud"),
    "A2031": ("AirPods 2", "bud"),
    "A1523": ("AirPods 1", "bud"),
    "A1722": ("AirPods 1", "bud"),
    "A1602": ("AirPods (Lightning Case)", "case"),
    "A1938": ("AirPods (Wireless Case)", "case"),
}

BASE_CLASS_HINTS = {
    "bud": [
        "UARPSupportedAccessoryA3064",
        "UARPSupportedAccessoryA3048",
        "UARPSupportedAccessoryA3053",
        "UARPSupportedAccessoryA2699",
        "UARPSupportedAccessoryAirPodsBud",
    ],
    "case": [
        "UARPSupportedAccessoryA3122",
        "UARPSupportedAccessoryA3059",
        "UARPSupportedAccessoryA2968",
        "UARPSupportedAccessoryA2617",
        "UARPSupportedAccessoryAirPodsCase",
    ],
    "caseUSB": [
        "UARPSupportedAccessoryA3122USB",
        "UARPSupportedAccessoryA3059USB",
        "UARPSupportedAccessoryA2968USB",
        "UARPSupportedAccessoryA2617USB",
        "UARPSupportedAccessoryAirPodsCaseUSB",
    ],
    "max": [
        "UARPSupportedAccessoryA3454",
        "UARPSupportedAccessoryBeatsBluetooth",
    ],
}


def read_text(path):
    """Read text with BOM auto-detection (PowerShell redirects emit UTF-16)."""
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
            file_off = int(match.group(1), 16)
            vm_start = int(match.group(2), 16)
            vm_end = int(match.group(3), 16)
            name = match.group(4)
            segments.append((file_off, vm_start, vm_end - vm_start, name))
    return segments


def parse_symbols(path):
    symbols = {}
    pattern = re.compile(r"^0x([0-9a-f]+):.*?(?:private|external|non-external[^\t]*)?\t(.*)$")
    for line in read_text(path).splitlines():
        match = pattern.match(line.rstrip())
        if match:
            symbols[match.group(2).strip()] = int(match.group(1), 16)
    return symbols


def parse_interfaces(path):
    interfaces = {}
    pattern = re.compile(r"@interface\s+(UARPSupportedAccessory\w+)\s*:\s*(\w+)")
    for line in read_text(path).splitlines():
        match = pattern.search(line)
        if match:
            interfaces[match.group(1)] = match.group(2)
    return interfaces


class Dylib:
    def __init__(self, path, segments):
        self.data = open(path, "rb").read()
        self.segments = segments

    def offset_of(self, address):
        for file_off, vm_start, size, _ in self.segments:
            if vm_start <= address < vm_start + size:
                return file_off + (address - vm_start)
        return None

    def read_pointer(self, address):
        offset = self.offset_of(address)
        if offset is None:
            return None
        return struct.unpack_from("<Q", self.data, offset)[0]

    def cstring(self, address):
        offset = self.offset_of(address)
        if offset is None:
            return None
        end = self.data.find(b"\0", offset)
        if end < 0:
            return None
        return self.data[offset:end].decode("utf-8", "replace")

    def cfstring(self, address):
        offset = self.offset_of(address)
        if offset is None:
            return None
        try:
            _, _, length, data_ptr = struct.unpack_from("<QIIQ", self.data, offset)
        except struct.error:
            return None
        value = self.cstring(data_ptr)
        if value:
            return value
        inline = self.data[offset + 8:offset + 8 + min(length, 32)]
        return inline.decode("utf-8", "replace") if length and length <= 32 else None


def decode_constants(dylib, symbols, disassembler):
    """Decode +productID / +appleModelNumber / +alternativeAppleModelNumbers."""
    values = {}
    for symbol, address in symbols.items():
        match = re.match(r"\+\[(UARPSupportedAccessory\w+) (productID|appleModelNumber|alternativeAppleModelNumbers)\]", symbol)
        if not match:
            continue
        cls, method = match.group(1), match.group(2)
        offset = dylib.offset_of(address)
        if offset is None:
            continue
        code = dylib.data[offset:offset + 160]
        registers = {}
        result = None
        for ins in disassembler.disasm(code, address):
            ops = ins.operands
            if ins.mnemonic == "adrp":
                # capstone already reports the absolute target page address
                registers[ins.reg_name(ops[0].reg)] = ops[1].imm
            elif ins.mnemonic == "add" and len(ops) == 3 and ops[2].type == capstone.arm64.ARM64_OP_IMM:
                base = registers.get(ins.reg_name(ops[1].reg))
                if base is not None:
                    registers[ins.reg_name(ops[0].reg)] = base + ops[2].imm
            elif ins.mnemonic in ("ldr", "ldur") and len(ops) == 2 and ops[1].type == capstone.arm64.ARM64_OP_MEM:
                base = registers.get(ins.reg_name(ops[1].mem.base))
                if base is not None:
                    slot = base + ops[1].mem.disp
                    pointer = dylib.read_pointer(slot)
                    if pointer:
                        registers[ins.reg_name(ops[0].reg)] = pointer
            elif ins.mnemonic == "mov" and len(ops) == 2 and ops[0].type == capstone.arm64.ARM64_OP_REG \
                    and ops[1].type == capstone.arm64.ARM64_OP_IMM:
                registers[ins.reg_name(ops[0].reg)] = ops[1].imm
            if method == "productID":
                if ins.mnemonic in ("ret", "retab") and "w0" in registers:
                    result = int(registers["w0"])
                elif ins.mnemonic == "mov" and ins.op_str.startswith("w0, #"):
                    result = int(ins.op_str.split("#")[1], 0)
            elif method == "appleModelNumber":
                if ins.mnemonic in ("ret", "retab"):
                    target = registers.get("x0")
                    if target is not None:
                        result = dylib.cfstring(target) or dylib.cstring(target)
            else:  # alternativeAppleModelNumbers
                if ins.mnemonic == "bl":
                    target = registers.get("x2")
                    if target is not None:
                        value = dylib.cfstring(target)
                        if value:
                            result = [value]
            if ins.mnemonic in ("ret", "retab"):
                break
        if result is not None:
            values.setdefault(cls, {})[method] = result
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dylib", required=True)
    parser.add_argument("--segments", required=True)
    parser.add_argument("--objc", required=True)
    parser.add_argument("--symbols", required=True)
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-plist", required=True)
    parser.add_argument("--out-app-json", required=True)
    args = parser.parse_args()

    segments = parse_segments(args.segments)
    symbols = parse_symbols(args.symbols)
    interfaces = parse_interfaces(args.objc)
    dylib = Dylib(args.dylib, segments)

    disassembler = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
    disassembler.detail = True
    constants = decode_constants(dylib, symbols, disassembler)

    entries = []
    for cls, values in sorted(constants.items()):
        pid = values.get("productID")
        if pid is None:
            continue
        suffix = cls.replace("UARPSupportedAccessory", "")
        model = values.get("appleModelNumber") or suffix
        # guard against mis-decoded constants
        if not re.fullmatch(r"A[0-9]{4}(USB)?", model or ""):
            model = suffix

        base = interfaces.get(cls, "")
        if "AirPodsBud" in base:
            family = "bud"
        elif "AirPodsCaseUSB" in base:
            family = "caseUSB"
        elif "AirPodsCase" in base:
            family = "case"
        elif "BeatsBluetooth" in base:
            family = "max"
        else:
            continue  # not an AirPods/Beats wearable (USB-PD, HID, ...)

        alt = values.get("alternativeAppleModelNumbers") or []
        display = None
        for candidate in [model] + list(alt):
            if candidate in KB_MODELS:
                display = KB_MODELS[candidate][0]
                break
        if display is None:
            display = KB_MODELS.get(model, (model, family))[0]

        entry = {
            "nativeClass": cls,
            "model": suffix,
            "appleModelNumber": model,
            "productID": pid,
            "display": display,
            "family": family,
            "baseClasses": BASE_CLASS_HINTS[family],
        }
        if alt:
            entry["alt"] = alt
        entries.append(entry)

    display_names = {}
    for entry in entries:
        display_names[str(entry["productID"])] = entry["display"]

    by_model = sorted(entries, key=lambda e: (e["model"], e["nativeClass"]))
    payload = {"models": by_model, "displayNames": display_names}
    for path, data in ((args.out_json, json.dumps(payload, indent=2)),
                       (args.out_app_json, json.dumps(payload, indent=2))):
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(data)

    def plist_escape(value):
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        '<dict>',
        '\t<key>Version</key>',
        '\t<integer>4</integer>',
        '\t<key>UARP</key>',
        '\t<array>',
    ]
    for entry in by_model:
        lines.append("\t\t<dict>")
        lines.append(f"\t\t\t<key>model</key><string>{plist_escape(entry['model'])}</string>")
        lines.append(f"\t\t\t<key>appleModelNumber</key><string>{plist_escape(entry['appleModelNumber'])}</string>")
        if entry.get("alt"):
            lines.append("\t\t\t<key>alternativeAppleModelNumbers</key><array>")
            for alt in entry["alt"]:
                lines.append(f"\t\t\t\t<string>{plist_escape(alt)}</string>")
            lines.append("\t\t\t</array>")
        lines.append(f"\t\t\t<key>productID</key><integer>{entry['productID']}</integer>")
        lines.append(f"\t\t\t<key>displayName</key><string>{plist_escape(entry['display'])}</string>")
        lines.append("\t\t\t<key>baseClasses</key><array>")
        for base in entry["baseClasses"]:
            lines.append(f"\t\t\t\t<string>{plist_escape(base)}</string>")
        lines.append("\t\t\t</array>")
        lines.append("\t\t</dict>")
    lines.append("\t</array>")
    lines.append("\t<key>DisplayNames</key>")
    lines.append("\t<dict>")
    for pid, name in sorted(display_names.items(), key=lambda kv: int(kv[0])):
        lines.append(f"\t\t<key>{pid}</key><string>{plist_escape(name)}</string>")
    lines.append("\t</dict>")
    lines.append("</dict>")
    lines.append("</plist>")
    with open(args.out_plist, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines) + "\n")

    print(f"extracted {len(by_model)} AirPods-family classes")
    for entry in by_model:
        print(f"  {entry['model']:<10} pid=0x{entry['productID']:04x} "
              f"{entry['display']:<38} alt={entry.get('alt', [])}")


if __name__ == "__main__":
    main()
