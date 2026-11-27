"""Generate the VU1 and VU0 AOT tables for the Spec II target on macOS (or iOS) from the derived SCUS_974.36.

VU1: Spec II uploads the same encrypted blob as v2.00 (docs/inputs/spec2-vu.json, `identical_to_v200`), so the
decrypted image plus the slice155 tail must equal the v2.00 image, and the generated table must equal the slice157
pin byte for byte.

VU0: Spec II has its own 0x920-byte upload at VA 0x731180. The v2.00 table never matches it (the generated programs
are keyed by the live code image), so upstream's Spec II build runs VU0 on the interpreter. This script instead emits
a table from the Spec II image itself, for the VCALLMS start addresses found in the Spec II code. Entries the game never
calls are harmless; any program whose image or entry is not in the table still falls back to the interpreter. This
table has no upstream pin: its hashes are written to the output's summary.json.

Usage (from the repository root, after scripts/spec2_elf_patch.py):
  private/tooling-venv/bin/python -E -s ports/macos/spec2_vu_generate.py private/slice272-spec2-elf/SCUS_974.36 \
      private/<fresh output>
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))

import vu1_image  # noqa: E402
import vu0_image  # noqa: E402

PYTHON = [sys.executable, '-E', '-s']
SPEC2_VU1_VADDR = 0x69B110
SPEC2_VU0_VADDR = 0x731180
SPEC2_VU0_BYTES = 0x920


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run(arguments):
    subprocess.run([str(argument) for argument in arguments], check=True, cwd=ROOT)


def read_virtual(elf_bytes, vaddr, size):
    """Bytes at a guest address, read through the ELF's PT_LOAD headers (the derived ELF splits the data segment)."""
    phoff, = struct.unpack_from('<I', elf_bytes, 0x1C)
    phentsize, phnum = struct.unpack_from('<HH', elf_bytes, 0x2A)
    for index in range(phnum):
        p_type, p_offset, p_vaddr, _, p_filesz = struct.unpack_from('<5I', elf_bytes, phoff + index * phentsize)
        if p_type == 1 and p_vaddr <= vaddr and vaddr + size <= p_vaddr + p_filesz:
            start = p_offset + vaddr - p_vaddr
            return elf_bytes[start:start + size]
    raise ValueError(f'no PT_LOAD segment holds 0x{vaddr:08X}+0x{size:X}')


def vcallms_targets(elf_bytes):
    """The VU0 start addresses of every VCALLMS immediate in the executable segments (the Spec II code has no
    VCALLMSR). The v2.00 list (vu0_image.VCALLMS_ENTRIES) does not apply: only 4 of its 14 entries are called here."""
    phoff, = struct.unpack_from('<I', elf_bytes, 0x1C)
    phentsize, phnum = struct.unpack_from('<HH', elf_bytes, 0x2A)
    targets = set()
    for index in range(phnum):
        p_type, p_offset, _, _, p_filesz, _, p_flags = struct.unpack_from('<7I', elf_bytes, phoff + index * phentsize)
        if p_type != 1 or not p_flags & 1:
            continue
        for offset in range(p_offset, p_offset + p_filesz - 3, 4):
            word, = struct.unpack_from('<I', elf_bytes, offset)
            if word & 0xFFE0003F == 0x4A000038:  # VCALLMS imm15: start at imm15 * 8
                targets.add(((word >> 6) & 0x7FFF) * 8)
            elif word == 0x4A000039:
                raise ValueError('VCALLMSR found: its start address is not static')
    if not targets or max(targets) >= SPEC2_VU0_BYTES:
        raise ValueError(f'unexpected VCALLMS targets {sorted(targets)}')
    return sorted(targets)


def generate(elf, output):
    output = output.resolve()
    if output.exists():
        raise ValueError('Output already exists; choose a fresh directory')
    elf_pin = json.loads((ROOT / 'docs/inputs/spec2-elf.json').read_text(encoding='utf-8'))
    vu_pin = json.loads((ROOT / 'docs/inputs/spec2-vu.json').read_text(encoding='utf-8'))
    vu1_pin = json.loads((ROOT / 'docs/inputs/slice155-vu1-image.json').read_text(encoding='utf-8'))
    vu1_table_pin = json.loads((ROOT / 'docs/inputs/slice157-vu1-all.json').read_text(encoding='utf-8'))['vu1_aot']
    elf_bytes = elf.read_bytes()
    if sha256(elf_bytes) != elf_pin['derived']['sha256']:
        raise ValueError('ELF is not the pinned derived SCUS_974.36')
    output.mkdir(parents=True)

    # VU1: the v2.00 image, recovered from the Spec II blob.
    encrypted = read_virtual(elf_bytes, SPEC2_VU1_VADDR, vu1_image.BLOB_BYTES)
    if sha256(encrypted) != vu_pin['vu1']['encrypted_sha256']:
        raise ValueError('Spec II VU1 blob differs from spec2-vu.json')
    blob = vu1_image.decrypt_blob(encrypted)
    if sha256(blob) != vu1_pin['blob_sha256']:
        raise ValueError('Decrypted Spec II VU1 blob differs from the v2.00 pin')
    vu1_dir = output / 'vu1-image'
    vu1_dir.mkdir()
    image = vu1_dir / 'vu1_image.bin'
    image.write_bytes(blob + bytes.fromhex(vu1_pin['tail_hex']))
    run(PYTHON + ['scripts/vu1_image.py', 'check', '--image', image])
    vu1_entries = vu1_dir / 'entries-all.txt'
    run(PYTHON + ['scripts/vu1_image.py', 'entries', '--image', image, '--policy', 'all', '--out', vu1_entries])
    if sha256(vu1_entries.read_bytes()) != vu1_table_pin['entry_list_sha256']:
        raise ValueError('VU1 entry list differs from its pin')

    # VU0: the Spec II upload padded to the 4 KiB code memory, and its in-range VCALLMS entries.
    upload = read_virtual(elf_bytes, SPEC2_VU0_VADDR, SPEC2_VU0_BYTES)
    if sha256(upload) != vu_pin['vu0']['sha256']:
        raise ValueError('Spec II VU0 upload differs from spec2-vu.json')
    vu0_dir = output / 'vu0-image'
    vu0_dir.mkdir()
    vu0_bin = vu0_dir / 'vu0_image.bin'
    vu0_bin.write_bytes(upload + bytes(vu0_image.IMAGE_BYTES - len(upload)))
    entries = vcallms_targets(elf_bytes)
    vu0_entries = output / 'entries-vcallms.txt'
    vu0_entries.write_text(''.join(f'{entry:04X}\n' for entry in entries), encoding='ascii', newline='\n')

    donor = ROOT / 'private/references/ps2-web-recomp'
    emitter = output / 'gt4_vu_recomp'
    source = ROOT / 'tools/vu_recomp/src'
    run(['clang++', '-std=c++20', '-O2', '-I', source, '-I', donor / 'runtime/include', '-I', donor / 'runtime/src',
         '-o', emitter, source / 'vurecomp_main.cpp', source / 'vurecomp.cpp', source / 'sha256.cpp'])
    vu1_generated = output / 'vu1-gen'
    run([emitter, '--programs-per-file', '16', '--entry-policy', 'all', '--image', image, '--entries', vu1_entries,
         vu1_generated])
    if sha256((vu1_generated / 'vu1_generated.cpp').read_bytes()) != vu1_table_pin['generated_source_sha256']:
        raise ValueError('VU1 table differs from the slice157 pin')
    vu0_generated = output / 'vu0-gen'
    run([emitter, '--unit', '0', '--namespace', 'gt4::vugen::vu0', '--entry-policy', 'vcallms',
         '--image', vu0_bin, '--entries', vu0_entries, vu0_generated])
    summary = {'vu1_table_sha256': vu1_table_pin['generated_source_sha256'],
               'vu0_image_sha256': sha256(vu0_bin.read_bytes()), 'vu0_entries': [f'0x{e:03X}' for e in entries],
               'vu0_table_sha256': sha256((vu0_generated / 'vu0_generated.cpp').read_bytes()),
               'note': 'VU0 table emitted from the Spec II image; no upstream pin'}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    return summary


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('elf', type=Path, help='derived SCUS_974.36 (scripts/spec2_elf_patch.py)')
    parser.add_argument('output', type=Path, help='fresh output directory')
    arguments = parser.parse_args(argv)
    print(json.dumps(generate(arguments.elf, arguments.output), indent=2))


if __name__ == '__main__':
    main()
