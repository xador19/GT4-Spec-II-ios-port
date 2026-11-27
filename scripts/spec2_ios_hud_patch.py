#!/usr/bin/env python
"""Spec II race HUD for any screen ratio, iOS port: TASK-166's two rows (scripts/spec2_aspect_patch.py) plus the edge offsets
and the monitor width, so the HUD reaches the screen edges on screens taller than 16:9.

The race HUD keeps some of its layout in immediates (`lui at,imm`, `addiu rt,zero,imm`). Statically recompiled code
turns them into C++ constants, and the HUD helpers are reached by direct jal, so no runtime hook can reach them. Each
one is patched, ahead of translation, into a load from the host-filled HUD parameter block (native/display_aspect.hpp,
kHudParameterBlock = 0x7F00). The host writes the original constants into the block at 16:9, so the patched code then
computes exactly what the original did; at another ratio it writes the values for that ratio.

Every row keeps the instruction count and touches no branch, so the translator's analysis (functions, entries,
labels) is unchanged and the Spec II entry seeds apply as they are. Addresses were located in the Spec II derived ELF
by the same code shapes as the v2.00 table (scripts/aspect_elf_patch.py) and the wide-flag readers listed in
docs/ULTRAWIDE-NATIVE-STUDY.md section 1.2; every one reads the published wide word at 0x6655A0.

Usage:
  python scripts/spec2_ios_hud_patch.py --elf private/slice272-spec2-elf/SCUS_974.36 \\
      --output private/spec2-aspect-elf --json docs/inputs/spec2-aspect-elf.json
"""

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DERIVED_PIN = ROOT / "docs/inputs/spec2-elf.json"
PARAMETER_BLOCK = 0x00007F00  # native/display_aspect.hpp kHudParameterBlock

# (first address, old words, new words, block offset, purpose)
PATCHES = (
    (0x001C519C, (0x3C013F40,), (0x8C017F00,), 0x00,
     "RaceDisplay::render (0x1C5040): race HUD font x scale in wide mode, lui at,0x3F40 (0.75) -> lw at,0x7F00(zero); "
     "block value (4/3)/R"),
    (0x001EB65C, (0x24080280,), (0x8C087F04,), 0x04,
     "rear-view mirror placement: horizontal divisor addiu t0,zero,640 -> lw t0,0x7F04(zero); "
     "block value round(640 x R / (16/9))"),
    (0x001D8400, (0x3C0142C0,), (0x8C017F08,), 0x08,
     "RaceDisplayUtil::wideOffset (float, 0x1D83E8): edge shift lui at,0x42C0 (96.0) -> lw at,0x7F08(zero); "
     "block value 96 + 240 x (R - 16/9) below 16:9, 96 otherwise"),
    (0x001D84BC, (0x3C0142C0,), (0x8C017F08,), 0x08,
     "RaceDisplayUtil edge offset (float, 0x1D84A8): lui at,0x42C0 (96.0) -> lw at,0x7F08(zero); same block word"),
    (0x001D8468,
     (0x24E20060, 0x24E4FFA0, 0x30C30008, 0x0040382D, 0x0083380A),
     (0x8C027F0C, 0x30C30008, 0x00022023, 0x0083100A, 0x00E23821), 0x0C,
     "RaceDisplayUtil::fillRectangle edge shift (integer, 0x1D8448), a3 = (a2 & 8) ? a3 + 96 : a3 - 96: "
     "addiu v0,a3,96; addiu a0,a3,-96; andi v1,a2,8; move a3,v0; movz a3,a0,v1 -> "
     "lw v0,0x7F0C(zero); andi v1,a2,8; subu a0,zero,v0; movz v0,a0,v1; addu a3,a3,v0 "
     "(same result; v0 and a0 are dead after it, the first word stays in the branch delay slot)"),
    (0x001F142C, (0x24050356,), (0x8C057F10,), 0x10,
     "race monitor (mini-map) canvas width in wide mode: addiu a1,zero,854 -> lw a1,0x7F10(zero); "
     "block value round(480 x R) below 16:9, 854 otherwise"),
)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def file_offset(data, address):
    phoff, = struct.unpack_from("<I", data, 28)
    phentsize, phnum = struct.unpack_from("<HH", data, 42)
    for index in range(phnum):
        p_type, p_offset, p_vaddr, _paddr, p_filesz = struct.unpack_from("<5I", data, phoff + index * phentsize)
        if p_type == 1 and p_vaddr <= address < p_vaddr + p_filesz:
            return p_offset + address - p_vaddr
    raise ValueError(f"0x{address:08X} is not in a loaded segment")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--elf", required=True, help="the Spec II derived ELF (docs/inputs/spec2-elf.json)")
    parser.add_argument("--output", required=True, help="fresh directory for the patched SCUS_974.36")
    parser.add_argument("--json", help="write the receipt (pin) here")
    args = parser.parse_args()

    data = bytearray(Path(args.elf).read_bytes())
    expected = json.loads(DERIVED_PIN.read_text())["derived"]["sha256"]
    if sha256(data) != expected:
        sys.exit(f"{args.elf} is not the pinned Spec II derived ELF ({expected})")

    rows = []
    for address, old_words, new_words, block_offset, purpose in PATCHES:
        assert len(old_words) == len(new_words)
        for index, (old, new) in enumerate(zip(old_words, new_words)):
            offset = file_offset(data, address + 4 * index)
            word, = struct.unpack_from("<I", data, offset)
            if word != old:
                sys.exit(f"0x{address + 4 * index:08X}: found 0x{word:08X}, expected 0x{old:08X}; nothing written")
            struct.pack_into("<I", data, offset, new)
        rows.append({"address": f"0x{address:08X}", "old": [f"0x{w:08X}" for w in old_words],
                     "new": [f"0x{w:08X}" for w in new_words], "block": f"0x{PARAMETER_BLOCK + block_offset:04X}",
                     "purpose": purpose})

    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=False)
    (output / "SCUS_974.36").write_bytes(data)
    receipt = {"schema": 1, "source": {"sha256": expected}, "aspect": {"sha256": sha256(data)}, "patches": rows}
    if args.json:
        Path(args.json).write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"wrote {output / 'SCUS_974.36'} ({sha256(data)}), {len(rows)} patches")


if __name__ == "__main__":
    main()
