#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-${ROOT_DIR}/out/artifacts}"
ARTIFACT_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "${ARTIFACT_DIR}")"
PAYLOAD="${ROOT_DIR}/imgs/uefi.elf"
TEMPLATE_BOOT="${ROOT_DIR}/imgs/8e.img"

mkdir -p "${ARTIFACT_DIR}/clean-oem-uefi" "${ARTIFACT_DIR}/oem"

# Use the proven InstallConfigurationTable bypass, then stop in a late EL1 stage
# before the deeper handoff/load chain continues.
PATCHED_ELF="${ARTIFACT_DIR}/clean-oem-uefi/pineapple-oem-uefi-pre-handoff-loop.elf"
BASE_ELF="${ARTIFACT_DIR}/clean-oem-uefi/pineapple-oem-uefi-pre-handoff-loop-base.elf"
PREFIX="${ARTIFACT_DIR}/clean-oem-uefi/pineapple-oem-uefi-pre-handoff-loop"

python3 "${ROOT_DIR}/scripts/patch_elf_address_probe.py" \
  --input "${PAYLOAD}" \
  --address "0xa700e810" \
  --mode success \
  --output "${BASE_ELF}"

python3 "${ROOT_DIR}/scripts/patch_elf_address_probe.py" \
  --input "${BASE_ELF}" \
  --address "0xa700f590" \
  --mode loop \
  --output "${PATCHED_ELF}"

python3 "${ROOT_DIR}/scripts/build_probe_kernel_shim.py" \
  --payload-elf "${PATCHED_ELF}" \
  --mode jump-payload \
  --output-prefix "${PREFIX}"

python3 "${ROOT_DIR}/scripts/repack_8e_style_boot.py" \
  --template-8e "${TEMPLATE_BOOT}" \
  --kernel-gzip "${PREFIX}.raw.bin.gz" \
  --output "${PREFIX}.boot.img"

python3 "${ROOT_DIR}/scripts/analyze_kernel_shim_layout.py" \
  --input "${PREFIX}.boot.img" \
  --output-dir "${ARTIFACT_DIR}/oem"

rm -f \
  "${ARTIFACT_DIR}/oem/pineapple-oem-uefi-pre-handoff-loop.boot.kernel.bin" \
  "${ARTIFACT_DIR}/oem/pineapple-oem-uefi-pre-handoff-loop.boot.kernel.unpacked.bin"
