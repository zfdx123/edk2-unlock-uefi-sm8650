#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-${ROOT_DIR}/out/artifacts}"
PAYLOAD="${ROOT_DIR}/imgs/uefi.elf"
TEMPLATE_BOOT="${ROOT_DIR}/imgs/8e.img"

mkdir -p "${ARTIFACT_DIR}/entry-probes" "${ARTIFACT_DIR}/oem"

build_one() {
  local mode="$1"
  local payload_variant="${ARTIFACT_DIR}/entry-probes/uefi-entry-${mode}.elf"
  local shim_prefix="${ARTIFACT_DIR}/entry-probes/pineapple-uefi-entry-${mode}"
  python3 "${ROOT_DIR}/scripts/patch_elf_entry_probe.py" \
    --input "${PAYLOAD}" \
    --mode "${mode}" \
    --output "${payload_variant}"
  python3 "${ROOT_DIR}/scripts/build_probe_kernel_shim.py" \
    --payload-elf "${payload_variant}" \
    --mode jump-payload \
    --output-prefix "${shim_prefix}"
  python3 "${ROOT_DIR}/scripts/repack_8e_style_boot.py" \
    --template-8e "${TEMPLATE_BOOT}" \
    --kernel-gzip "${shim_prefix}.raw.bin.gz" \
    --output "${shim_prefix}.boot.img"
  python3 "${ROOT_DIR}/scripts/analyze_kernel_shim_layout.py" \
    --input "${shim_prefix}.boot.img" \
    --output-dir "${ARTIFACT_DIR}/oem"
  rm -f \
    "${ARTIFACT_DIR}/oem/$(basename "${shim_prefix}").boot.kernel.bin" \
    "${ARTIFACT_DIR}/oem/$(basename "${shim_prefix}").boot.kernel.unpacked.bin"
}

build_one "loop"
build_one "reset"
build_one "delay-reset"
