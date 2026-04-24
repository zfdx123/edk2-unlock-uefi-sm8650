#!/usr/bin/env python3
"""Build an 8e-style kernel-shaped shim payload with embedded stage2 artifacts."""

from __future__ import annotations

import argparse
import json
import pathlib
import struct
import gzip

ARM64_IMAGE_MAGIC = b"ARMd"
QCOM_FS_GUID = bytes.fromhex("78e58c8c3d8a1c4f9935896185c32dd3")
QSHM_MAGIC = b"QSHM"
HEADER_SIZE = 0x40
STUB_SIZE = 0x30
FVH_TARGET_OFFSET = 0x98
STAGE1_TARGET_OFFSET = 0x41000
PAGE_SIZE = 0x1000


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fv", required=True, help="Firmware volume to embed")
    parser.add_argument("--stage1-efi", required=True, help="Primary EFI payload")
    parser.add_argument("--stage2-efi", required=True, help="Secondary EFI payload")
    parser.add_argument("--unsigned-abl", required=True, help="Unsigned ABL artifact")
    parser.add_argument("--output-prefix", required=True, help="Output prefix without extension")
    return parser.parse_args()


def align(value: int, alignment: int) -> int:
    return (value + alignment - 1) // alignment * alignment


def make_linux_header(image_size: int) -> bytes:
    code0 = 0x14000010
    code1 = 0xD503201F
    text_offset = 0
    flags = 0
    res2 = 0
    res3 = 0
    res4 = 0
    res5 = 0
    return struct.pack(
        "<IIQQQQQQ4sI",
        code0,
        code1,
        text_offset,
        image_size,
        flags,
        res2,
        res3,
        res4,
        ARM64_IMAGE_MAGIC,
        res5,
    )


def make_stub() -> bytes:
    nop = struct.pack("<I", 0xD503201F)
    loop = struct.pack("<I", 0x14000000)
    return nop * 11 + loop


def make_qcom_fv_payload(fv: bytes) -> bytes:
    prefix = bytearray(0x28)
    prefix[0x10:0x20] = QCOM_FS_GUID
    struct.pack_into("<Q", prefix, 0x20, len(prefix) + len(fv))
    return bytes(prefix) + fv


def make_manifest(entries: list[dict[str, int | str]]) -> bytes:
    encoded = json.dumps({"entries": entries}, indent=2).encode("utf-8")
    header = struct.pack("<4sIII", QSHM_MAGIC, 1, len(entries), len(encoded))
    return header + encoded


def main() -> int:
    args = parse_args()
    fv = pathlib.Path(args.fv).read_bytes()
    stage1 = pathlib.Path(args.stage1_efi).read_bytes()
    stage2 = pathlib.Path(args.stage2_efi).read_bytes()
    unsigned_abl = pathlib.Path(args.unsigned_abl).read_bytes()

    qcom_fv = make_qcom_fv_payload(fv)
    if HEADER_SIZE + STUB_SIZE + 0x28 != FVH_TARGET_OFFSET:
        raise ValueError("configured shim offsets no longer place _FVH at target offset")

    stage1_offset = align(max(STAGE1_TARGET_OFFSET, HEADER_SIZE + STUB_SIZE + len(qcom_fv)), PAGE_SIZE)
    stage2_offset = align(stage1_offset + len(stage1), PAGE_SIZE)
    abl_offset = align(stage2_offset + len(stage2), PAGE_SIZE)

    image_size = align(abl_offset + len(unsigned_abl) + PAGE_SIZE, PAGE_SIZE)
    image = bytearray(image_size)
    image[:HEADER_SIZE] = make_linux_header(image_size)
    image[HEADER_SIZE:HEADER_SIZE + STUB_SIZE] = make_stub()
    image[HEADER_SIZE + STUB_SIZE:HEADER_SIZE + STUB_SIZE + len(qcom_fv)] = qcom_fv
    image[stage1_offset:stage1_offset + len(stage1)] = stage1
    image[stage2_offset:stage2_offset + len(stage2)] = stage2
    image[abl_offset:abl_offset + len(unsigned_abl)] = unsigned_abl

    entries = [
        {"name": "qcom_fv", "offset": HEADER_SIZE + STUB_SIZE, "size": len(qcom_fv)},
        {"name": "stage1_efi", "offset": stage1_offset, "size": len(stage1)},
        {"name": "stage2_efi", "offset": stage2_offset, "size": len(stage2)},
        {"name": "unsigned_abl", "offset": abl_offset, "size": len(unsigned_abl)},
    ]

    manifest = make_manifest(entries)
    manifest_offset = align(abl_offset + len(unsigned_abl), PAGE_SIZE)
    if manifest_offset + len(manifest) > len(image):
        image.extend(b"\0" * align(len(manifest), PAGE_SIZE))
        image_size = len(image)
        image[:HEADER_SIZE] = make_linux_header(image_size)
    image[manifest_offset:manifest_offset + len(manifest)] = manifest

    output_prefix = pathlib.Path(args.output_prefix)
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    raw_path = output_prefix.with_suffix(".raw.bin")
    gzip_path = output_prefix.with_suffix(".raw.bin.gz")
    layout_path = output_prefix.with_suffix(".layout.json")

    raw_path.write_bytes(bytes(image))
    gzip_path.write_bytes(gzip.compress(bytes(image), compresslevel=9, mtime=0))
    layout_path.write_text(
        json.dumps(
            {
                "image_size": len(image),
                "fvh_offset": FVH_TARGET_OFFSET,
                "mz_offset": stage1_offset,
                "manifest_offset": manifest_offset,
                "entries": entries,
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
