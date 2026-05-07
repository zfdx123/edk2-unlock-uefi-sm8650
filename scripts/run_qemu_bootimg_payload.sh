#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <boot.img> [output-dir]" >&2
  exit 2
fi

BOOT_IMG="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${2:-$(dirname "${BOOT_IMG}")/qemu-bootimg-payload}"
PYTHON="${PYTHON:-python3}"
QEMU_BIN="${QEMU_BIN:-qemu-system-aarch64}"
QEMU_MEMORY="${QEMU_MEMORY:-4096}"
QEMU_TRACE="${QEMU_TRACE:-in_asm,guest_errors,unimp}"
QEMU_TIMEOUT="${QEMU_TIMEOUT:-30s}"
QEMU_LOG="${QEMU_LOG:-${OUT_DIR}/qemu.log}"
ANALYZE_SCRIPT="${ANALYZE_SCRIPT:-${SCRIPT_DIR}/analyze_kernel_shim_layout.py}"

if [[ ! -f "${BOOT_IMG}" ]]; then
  echo "error: boot image not found: ${BOOT_IMG}" >&2
  exit 1
fi

if [[ ! -f "${ANALYZE_SCRIPT}" ]]; then
  echo "error: analyze script not found: ${ANALYZE_SCRIPT}" >&2
  exit 1
fi

if ! command -v "${QEMU_BIN}" >/dev/null 2>&1; then
  echo "error: ${QEMU_BIN} not found in PATH" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

LAYOUT_PATH="$("${PYTHON}" "${ANALYZE_SCRIPT}" \
  --input "${BOOT_IMG}" \
  --output-dir "${OUT_DIR}")"

KERNEL_PAYLOAD="$("${PYTHON}" - "${LAYOUT_PATH}" "${OUT_DIR}" <<'PY'
import json
import pathlib
import sys

layout = json.loads(pathlib.Path(sys.argv[1]).read_text())
out_dir = pathlib.Path(sys.argv[2])
unpacked = layout.get("gzip_unpacked")
if unpacked:
    print(out_dir / unpacked["path"])
else:
    print(out_dir / layout["kernel_blob"])
PY
)"

echo "boot_img=${BOOT_IMG}"
echo "layout=${LAYOUT_PATH}"
echo "kernel_payload=${KERNEL_PAYLOAD}"
echo "qemu_log=${QEMU_LOG}"

EXTRA_ARGS=()
if [[ -n "${QEMU_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARGS=(${QEMU_EXTRA_ARGS})
fi

TIMEOUT_CMD=()
if [[ -n "${QEMU_TIMEOUT}" && "${QEMU_TIMEOUT}" != "0" ]]; then
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD=(timeout "${QEMU_TIMEOUT}")
  else
    echo "warning: timeout command not found; QEMU will run until it exits" >&2
  fi
fi

set +e
"${TIMEOUT_CMD[@]}" "${QEMU_BIN}" \
  -machine virt,gic-version=3,virtualization=on \
  -cpu max \
  -m "${QEMU_MEMORY}" \
  -nographic \
  -serial mon:stdio \
  -kernel "${KERNEL_PAYLOAD}" \
  -no-reboot \
  -d "${QEMU_TRACE}" \
  -D "${QEMU_LOG}" \
  "${EXTRA_ARGS[@]}"
STATUS=$?
set -e

echo "qemu_exit_status=${STATUS}"
exit "${STATUS}"
