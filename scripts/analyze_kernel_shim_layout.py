#!/usr/bin/env python3
"""Analyze an Android boot image that stores a compressed kernel-style shim."""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib
import struct

BOOT_MAGIC = b"ANDROID!"
PAGE_SIZE = 4096


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Input Android boot image")
    parser.add_argument("--output-dir", required=True, help="Directory for extracted analysis")
    return parser.parse_args()


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def find_signatures(blob: bytes) -> dict[str, int | None]:
    signatures = {
        "elf": b"\x7fELF",
        "fvh": b"_FVH",
        "cpio": b"070701",
        "android": BOOT_MAGIC,
        "mz": b"MZ",
        "arm64_image_magic": b"ARMd",
    }
    result: dict[str, int | None] = {}
    for name, signature in signatures.items():
        index = blob.find(signature)
        result[name] = index if index >= 0 else None
    return result


def main() -> int:
    args = parse_args()
    input_path = pathlib.Path(args.input)
    output_dir = pathlib.Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    data = input_path.read_bytes()
    if data[:8] != BOOT_MAGIC:
        raise ValueError("input is not an Android boot image")

    kernel_size, ramdisk_size, os_version, header_size = struct.unpack_from("<IIII", data, 8)
    reserved = struct.unpack_from("<4I", data, 24)
    header_version = struct.unpack_from("<I", data, 40)[0]
    signature_size = struct.unpack_from("<I", data, 44 + 1536)[0]

    kernel_offset = PAGE_SIZE
    kernel_padded_size = align(kernel_size, PAGE_SIZE)
    kernel_blob = data[kernel_offset:kernel_offset + kernel_size]
    kernel_path = output_dir / f"{input_path.stem}.kernel.bin"
    kernel_path.write_bytes(kernel_blob)

    analysis: dict[str, object] = {
        "input": str(input_path),
        "size": len(data),
        "header_version": header_version,
        "header_size": header_size,
        "kernel_size": kernel_size,
        "ramdisk_size": ramdisk_size,
        "os_version_raw": os_version,
        "reserved": reserved,
        "signature_size": signature_size,
        "kernel_offset": kernel_offset,
        "kernel_padded_size": kernel_padded_size,
        "bytes_after_kernel": len(data) - (kernel_offset + kernel_padded_size),
        "kernel_blob": kernel_path.name,
        "kernel_signatures": find_signatures(kernel_blob),
    }

    try:
        unpacked = gzip.decompress(kernel_blob)
        unpacked_path = output_dir / f"{input_path.stem}.kernel.unpacked.bin"
        unpacked_path.write_bytes(unpacked)
        analysis["gzip_unpacked"] = {
            "size": len(unpacked),
            "path": unpacked_path.name,
            "signatures": find_signatures(unpacked),
            "u32_words": list(struct.unpack_from("<8I", unpacked, 0)),
        }
    except OSError:
        analysis["gzip_unpacked"] = None

    manifest_path = output_dir / f"{input_path.stem}.layout.json"
    manifest_path.write_text(json.dumps(analysis, indent=2) + "\n")
    print(manifest_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
