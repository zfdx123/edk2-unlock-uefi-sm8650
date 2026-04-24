#!/usr/bin/env python3
"""Patch an AArch64 PE32/PE32+ image at entrypoint or RVA with a tiny stub."""

from __future__ import annotations

import argparse
import pathlib
import struct
import subprocess
import tempfile


MODE_TO_ASM = {
    "loop": """
        .text
        .global _start
    _start:
    1:
        wfe
        b 1b
    """,
    "reset": """
        .text
        .global _start
    _start:
        movz x0, #0x0009
        movk x0, #0x8400, lsl #16
        smc #0
    1:
        wfe
        b 1b
    """,
    "success": """
        .text
        .global _start
    _start:
        mov x0, #0
        ret
    """,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Input PE image path")
    parser.add_argument("--mode", choices=sorted(MODE_TO_ASM), required=True, help="Patch behavior")
    parser.add_argument("--output", required=True, help="Patched PE output path")
    parser.add_argument("--rva", help="Optional RVA to patch; defaults to entrypoint")
    return parser.parse_args()


def build_stub(mode: str) -> bytes:
    with tempfile.TemporaryDirectory(prefix="pe32-a64-patch-", dir="/tmp") as tmp_dir_name:
        tmp_dir = pathlib.Path(tmp_dir_name)
        asm_path = tmp_dir / "stub.S"
        obj_path = tmp_dir / "stub.o"
        bin_path = tmp_dir / "stub.bin"
        asm_path.write_text(MODE_TO_ASM[mode])
        subprocess.run(["aarch64-linux-gnu-gcc", "-c", str(asm_path), "-o", str(obj_path)], check=True, cwd=tmp_dir)
        subprocess.run(["aarch64-linux-gnu-objcopy", "-O", "binary", str(obj_path), str(bin_path)], check=True, cwd=tmp_dir)
        return bin_path.read_bytes()


def parse_int(value: str) -> int:
    return int(value, 0)


def rva_to_file_offset(data: bytes, rva: int) -> int:
    if data[:2] != b"MZ":
        raise ValueError("not a DOS/PE image")
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_off:pe_off + 4] != b"PE\x00\x00":
        raise ValueError("missing PE signature")

    num_sections = struct.unpack_from("<H", data, pe_off + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe_off + 20)[0]
    opt_off = pe_off + 24
    magic = struct.unpack_from("<H", data, opt_off)[0]
    if magic not in (0x10B, 0x20B):
        raise ValueError("unsupported PE optional header")

    section_off = opt_off + optional_size
    for index in range(num_sections):
        off = section_off + index * 40
        virtual_size, virtual_address, raw_size, raw_pointer = struct.unpack_from("<IIII", data, off + 8)
        size = max(virtual_size, raw_size)
        if virtual_address <= rva < virtual_address + size:
            return raw_pointer + (rva - virtual_address)
    raise ValueError(f"RVA {hex(rva)} not found in section table")


def entry_rva(data: bytes) -> int:
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    opt_off = pe_off + 24
    return struct.unpack_from("<I", data, opt_off + 16)[0]


def main() -> int:
    args = parse_args()
    input_path = pathlib.Path(args.input)
    output_path = pathlib.Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    data = bytearray(input_path.read_bytes())
    rva = parse_int(args.rva) if args.rva else entry_rva(data)
    file_off = rva_to_file_offset(data, rva)
    stub = build_stub(args.mode)
    data[file_off:file_off + len(stub)] = stub
    output_path.write_bytes(data)
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
