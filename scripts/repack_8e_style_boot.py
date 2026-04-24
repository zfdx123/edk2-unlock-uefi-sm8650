#!/usr/bin/env python3
"""Repack an Android boot image using an 8e-like v3 header template."""

from __future__ import annotations

import argparse
import pathlib
import struct

BOOT_MAGIC = b"ANDROID!"
PAGE_SIZE = 4096


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template-8e", required=True, help="Reference 8e boot image")
    parser.add_argument("--kernel-gzip", required=True, help="Compressed kernel-shaped payload")
    parser.add_argument("--output", required=True, help="Output boot image path")
    return parser.parse_args()


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def main() -> int:
    args = parse_args()
    template = pathlib.Path(args.template_8e).read_bytes()
    kernel = pathlib.Path(args.kernel_gzip).read_bytes()
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    if template[:8] != BOOT_MAGIC:
        raise ValueError("8e reference image is not an Android boot image")

    header = bytearray(template[:PAGE_SIZE])
    struct.pack_into("<I", header, 8, len(kernel))
    struct.pack_into("<I", header, 12, 0)
    image = bytearray(header)
    image.extend(kernel)
    image.extend(b"\0" * (align(len(kernel), PAGE_SIZE) - len(kernel)))
    output.write_bytes(bytes(image))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
