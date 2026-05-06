#!/usr/bin/env python3
"""Build a BootShim-style kernel payload from a flat UEFI firmware image."""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bootshim", required=True, help="BootShim.bin path")
    parser.add_argument("--payload", required=True, help="Flat payload image path")
    parser.add_argument("--uefi-base", required=True, help="UEFI load address")
    parser.add_argument("--uefi-size", required=True, help="UEFI image size")
    parser.add_argument("--output-prefix", required=True, help="Output prefix without extension")
    return parser.parse_args()


def parse_int(value: str) -> int:
    return int(value, 0)


def main() -> int:
    args = parse_args()
    bootshim = pathlib.Path(args.bootshim).read_bytes()
    payload_path = pathlib.Path(args.payload)
    payload = payload_path.read_bytes()
    uefi_base = parse_int(args.uefi_base)
    uefi_size = parse_int(args.uefi_size)

    if uefi_size <= 0:
        raise ValueError("uefi size must be positive")
    if uefi_size % 16 != 0:
        raise ValueError("uefi size must be 16-byte aligned for BootShim copy loop")
    if len(payload) > uefi_size:
        raise ValueError(
            f"payload {payload_path} is too large ({len(payload)} bytes > configured {uefi_size} bytes)"
        )

    padded_payload = payload + (b"\0" * (uefi_size - len(payload)))
    raw = bootshim + padded_payload

    output_prefix = pathlib.Path(args.output_prefix)
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    raw_path = output_prefix.with_suffix(".raw.bin")
    gzip_path = output_prefix.with_suffix(".raw.bin.gz")
    layout_path = output_prefix.with_suffix(".layout.json")

    raw_path.write_bytes(raw)
    gzip_path.write_bytes(gzip.compress(raw, compresslevel=9, mtime=0))
    layout_path.write_text(
        json.dumps(
            {
                "bootshim": str(pathlib.Path(args.bootshim)),
                "payload": str(payload_path),
                "payload_input_size": len(payload),
                "payload_padded_size": len(padded_payload),
                "raw_size": len(raw),
                "gzip_size": gzip_path.stat().st_size,
                "uefi_base": hex(uefi_base),
                "uefi_size": hex(uefi_size),
                "raw": raw_path.name,
                "gzip": gzip_path.name,
            },
            indent=2,
        )
        + "\n"
    )
    print(gzip_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
