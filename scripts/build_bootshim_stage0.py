#!/usr/bin/env python3
"""Build a tiny executable stage0 ELF for BootShim validation."""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import tempfile


ASM_TEMPLATE = r"""
    .section .text
    .global _start
    .type _start, %function
_start:
{body}
1:
    wfe
    b 1b
"""


BODY_MAP = {
    "loop": "",
    "reset": """    movz x0, #0x0009
    movk x0, #0x8400, lsl #16
    smc #0
""",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="Output ELF path")
    parser.add_argument("--link-address", required=True, help="Stage0 load/entry address")
    parser.add_argument(
        "--mode",
        choices=sorted(BODY_MAP),
        default="reset",
        help="Validation behavior once stage0 executes",
    )
    parser.add_argument("--clang-bin", default="", help="Directory containing clang/ld.lld/llvm-objcopy")
    return parser.parse_args()


def parse_int(value: str) -> int:
    return int(value, 0)


def tool_path(bin_dir: str, name: str) -> str:
    if not bin_dir:
        return name
    return str(pathlib.Path(bin_dir) / name)


def run(cmd: list[str], cwd: pathlib.Path) -> None:
    subprocess.run(cmd, cwd=str(cwd), check=True)


def main() -> int:
    args = parse_args()
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    link_address = parse_int(args.link_address)
    clang_bin = args.clang_bin.rstrip("/\\")

    clang = tool_path(clang_bin, "clang")
    ld_lld = tool_path(clang_bin, "ld.lld")

    asm_text = ASM_TEMPLATE.format(body=BODY_MAP[args.mode])

    with tempfile.TemporaryDirectory(prefix="bootshim-stage0-") as tmp_name:
        tmp = pathlib.Path(tmp_name)
        asm_path = tmp / "stage0.S"
        obj_path = tmp / "stage0.o"

        asm_path.write_text(asm_text, encoding="ascii")
        run([clang, "--target=aarch64-linux-gnu", "-c", str(asm_path), "-o", str(obj_path)], tmp)
        run(
            [
                ld_lld,
                "-o",
                str(output),
                "-e",
                "_start",
                "-Ttext",
                hex(link_address),
                str(obj_path),
            ],
            tmp,
        )

    manifest = {
        "mode": args.mode,
        "link_address": hex(link_address),
        "output": str(output),
    }
    output.with_suffix(".json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
