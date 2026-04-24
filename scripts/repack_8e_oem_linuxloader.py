#!/usr/bin/env python3
"""Rebuild an 8e-style OEM boot payload while swapping LinuxLoader/DualStageLoader FFS files."""

from __future__ import annotations

import argparse
import gzip
import json
import pathlib
import re
import shutil
import subprocess
import tempfile


EE4E_GUID = "EE4E5898-3914-4259-9D6E-DC7BD79403CF"
FV_IMAGE_GUID = "9E21FD93-9C72-4C15-8C4B-E77F1DB2D792"
FV_FILETYPE_FV_IMAGE = "EFI_FV_FILETYPE_FIRMWARE_VOLUME_IMAGE"
ALIGNMENT = 8


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference-zip", required=True, help="Extracted UEFI tree zip from the successful 8e image")
    parser.add_argument("--template-boot", required=True, help="Reference 8e Android boot image")
    parser.add_argument("--linuxloader-ffs", required=True, help="Replacement LinuxLoader .ffs")
    parser.add_argument("--dualstage-ffs", help="Optional DualStageLoader .ffs to inject")
    parser.add_argument("--output-prefix", required=True, help="Output prefix without extension")
    return parser.parse_args()


def run(cmd: list[str], cwd: pathlib.Path | None = None) -> None:
    tool = shutil.which(cmd[0])
    if tool is None:
        candidate = pathlib.Path(__file__).resolve().parent.parent / "BaseTools" / "BinWrappers" / "PosixLike" / cmd[0]
        if candidate.exists():
            cmd = [str(candidate), *cmd[1:]]
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)


def align(value: int, alignment: int = ALIGNMENT) -> int:
    return (value + alignment - 1) // alignment * alignment


def read_fv_header_info(header: bytes) -> tuple[int, int, int]:
    if len(header) < 0x40:
        raise ValueError("FV header too small")
    fv_length = int.from_bytes(header[0x20:0x28], "little")
    header_length = int.from_bytes(header[0x30:0x32], "little")
    block_size = int.from_bytes(header[0x38:0x3C], "little")
    return fv_length, header_length, block_size


def update_fv_header(header: bytearray, full_size: int) -> bytearray:
    _, header_length, block_size = read_fv_header_info(header)
    if block_size == 0:
        block_size = 0x1000
    num_blocks = align(full_size, block_size) // block_size
    full_size = num_blocks * block_size

    header[0x20:0x28] = full_size.to_bytes(8, "little")
    header[0x3C:0x40] = num_blocks.to_bytes(4, "little")
    header[0x32:0x34] = b"\x00\x00"

    checksum = 0
    for offset in range(0, header_length, 2):
        checksum = (checksum + int.from_bytes(header[offset:offset + 2], "little")) & 0xFFFF
    checksum = (-checksum) & 0xFFFF
    header[0x32:0x34] = checksum.to_bytes(2, "little")
    return header


def numeric_prefix(path: pathlib.Path) -> int:
    match = re.match(r"(\d+)\s", path.name)
    if not match:
        raise ValueError(f"missing numeric prefix in {path}")
    return int(match.group(1))


def find_first(root: pathlib.Path, pattern: str) -> pathlib.Path:
    matches = sorted(root.glob(pattern))
    if not matches:
        raise FileNotFoundError(pattern)
    return matches[0]


def reconstruct_fv(volume_dir: pathlib.Path, replacements: dict[str, bytes], injected_entries: list[tuple[str, bytes]] | None = None) -> bytes:
    header = bytearray((volume_dir / "header.bin").read_bytes())
    full_size, header_length, block_size = read_fv_header_info(header)

    children = [path for path in volume_dir.iterdir() if path.is_dir()]
    file_entries = sorted(
        [path for path in children if "Volume free space" not in path.name],
        key=numeric_prefix,
    )

    file_blobs: list[tuple[str, bytes]] = []
    for entry in file_entries:
        key = entry.name.split(" ", 1)[1]
        data = replacements.get(key)
        if data is None:
            data = (entry / "header.bin").read_bytes() + (entry / "body.bin").read_bytes()
        file_blobs.append((entry.name, data))
    for name, data in injected_entries or []:
        file_blobs.append((name, data))

    cursor = align(header_length)
    for _, data in file_blobs:
        cursor = align(cursor)
        cursor += len(data)
    required_size = cursor
    if required_size > full_size:
        if block_size == 0:
            block_size = 0x1000
        full_size = align(required_size, block_size)
        header = update_fv_header(header, full_size)

    image = bytearray(b"\xff" * full_size)
    image[: len(header)] = header
    cursor = align(header_length)

    for entry_name, data in file_blobs:
        cursor = align(cursor)
        if cursor + len(data) > full_size:
            raise ValueError(f"{entry_name} does not fit in {volume_dir}")
        image[cursor : cursor + len(data)] = data
        cursor += len(data)
    return bytes(image)


def build_guided_fv_file(tmp_dir: pathlib.Path, fv_bytes: bytes) -> bytes:
    fv_path = tmp_dir / "fv.bin"
    fv_sec = tmp_dir / "fv.sec"
    fv_dummy = tmp_dir / "fv.guided.dummy"
    fv_tmp = tmp_dir / "fv.tmp"
    fv_guided = tmp_dir / "fv.guided"
    fv_ffs = tmp_dir / "fv.ffs"

    fv_path.write_bytes(fv_bytes)

    run(["GenSec", "-s", "EFI_SECTION_FIRMWARE_VOLUME_IMAGE", "-o", str(fv_sec), str(fv_path)])
    run(["GenSec", "--sectionalign", "8", "-o", str(fv_dummy), str(fv_sec)])
    run(["LzmaCompress", "-e", "-o", str(fv_tmp), str(fv_dummy)])
    run([
        "GenSec",
        "-s", "EFI_SECTION_GUID_DEFINED",
        "-g", EE4E_GUID,
        "-r", "PROCESSING_REQUIRED",
        "-o", str(fv_guided),
        str(fv_tmp),
    ])
    run([
        "GenFfs",
        "-t", FV_FILETYPE_FV_IMAGE,
        "-g", FV_IMAGE_GUID,
        "-o", str(fv_ffs),
        "-i", str(fv_guided),
    ])
    return fv_ffs.read_bytes()


def main() -> int:
    args = parse_args()
    reference_zip = pathlib.Path(args.reference_zip).resolve()
    template_boot = pathlib.Path(args.template_boot).resolve()
    linuxloader_ffs = pathlib.Path(args.linuxloader_ffs).resolve()
    dualstage_ffs = pathlib.Path(args.dualstage_ffs).resolve() if args.dualstage_ffs else None
    output_prefix = pathlib.Path(args.output_prefix).resolve()
    output_prefix.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="repack-8e-", dir="/tmp") as tmp_dir_name:
        tmp_dir = pathlib.Path(tmp_dir_name)
        extracted_dir = tmp_dir / "ref"
        extracted_dir.mkdir(parents=True, exist_ok=True)
        run(["7z", "x", "-y", f"-o{extracted_dir}", str(reference_zip)])

        dump_root = extracted_dir / "8e" / "kernel.dump"
        padding_path = dump_root / "0 Padding" / "body.bin"
        outer_fv_dir = find_first(dump_root, "1 *")
        inner_fv_file_dir = find_first(outer_fv_dir, "2 9E21*")
        volume_image_dir = find_first(inner_fv_file_dir, "0 */1 Volume image section/0 *")

        replacement_files: dict[str, bytes] = {
            "LinuxLoader": linuxloader_ffs.read_bytes(),
        }
        injected_files: list[tuple[str, bytes]] = []
        if dualstage_ffs is not None:
            injected_files.append(("DualStageLoader", dualstage_ffs.read_bytes()))

        rebuilt_inner_fv = reconstruct_fv(volume_image_dir, replacement_files, injected_files)
        rebuilt_fv_file = build_guided_fv_file(tmp_dir, rebuilt_inner_fv)

        rebuilt_outer_fv = reconstruct_fv(
            outer_fv_dir,
            {
                inner_fv_file_dir.name.split(" ", 1)[1]: rebuilt_fv_file,
            },
        )

        kernel_unpacked = (padding_path.read_bytes() + rebuilt_outer_fv)
        kernel_raw = output_prefix.with_suffix(".raw.bin")
        kernel_gzip = output_prefix.with_suffix(".raw.bin.gz")
        boot_img = output_prefix.with_suffix(".boot.img")
        layout_json = output_prefix.with_suffix(".layout.json")

        kernel_raw.write_bytes(kernel_unpacked)
        kernel_gzip.write_bytes(gzip.compress(kernel_unpacked, compresslevel=9, mtime=0))

        run([
            "python3", str(pathlib.Path(__file__).with_name("repack_8e_style_boot.py")),
            "--template-8e", str(template_boot),
            "--kernel-gzip", str(kernel_gzip),
            "--output", str(boot_img),
        ])

        layout_json.write_text(
            json.dumps(
                {
                    "reference_zip": str(reference_zip),
                    "template_boot": str(template_boot),
                    "linuxloader_ffs": str(linuxloader_ffs),
                    "dualstage_ffs": str(dualstage_ffs) if dualstage_ffs else None,
                    "outer_volume": outer_fv_dir.name,
                    "inner_volume": volume_image_dir.name,
                    "kernel_unpacked_size": len(kernel_unpacked),
                    "kernel_gzip_size": len(kernel_gzip.read_bytes()),
                    "boot_img": boot_img.name,
                },
                indent=2,
            )
            + "\n"
        )
        print(boot_img)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
