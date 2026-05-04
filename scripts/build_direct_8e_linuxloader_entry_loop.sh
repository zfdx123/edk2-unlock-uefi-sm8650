#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-${ROOT_DIR}/out/artifacts/direct-8e-patch}"
ARTIFACT_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "${ARTIFACT_DIR}")"
TMP_DIR="$(mktemp -d /tmp/8e-linuxloader-loop.XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${ARTIFACT_DIR}"

LINUXLOADER_BODY_IN_ZIP='8e/kernel.dump/1 8C8CE578-8A3D-4F1C-9935-896185C32DD3/2 9E21FD93-9C72-4C15-8C4B-E77F1DB2D792/0 EE4E5898-3914-4259-9D6E-DC7BD79403CF/1 Volume image section/0 631008B0-B2D1-410A-8B49-2C5C4D8ECC7E/226 LinuxLoader/1 PE32 image section/body.bin'

7z x -y "-o${TMP_DIR}" "${ROOT_DIR}/imgs/8e.zip" "${LINUXLOADER_BODY_IN_ZIP}" >/dev/null

OEM_BODY="${TMP_DIR}/${LINUXLOADER_BODY_IN_ZIP}"
PATCHED_BODY="${TMP_DIR}/LinuxLoader.entry-loop.body.bin"

python3 "${ROOT_DIR}/scripts/patch_pe32_aarch64.py" \
  --input "${OEM_BODY}" \
  --mode loop \
  --output "${PATCHED_BODY}"

python3 "${ROOT_DIR}/scripts/repack_8e_oem_linuxloader.py" \
  --reference-zip "${ROOT_DIR}/imgs/8e.zip" \
  --template-boot "${ROOT_DIR}/imgs/8e.img" \
  --linuxloader-ffs "${ROOT_DIR}/out/Build/DEBUG_CLANG35/FV/Ffs/f536d559-459f-48fa-8bbc-43b554ecae8dLinuxLoader/f536d559-459f-48fa-8bbc-43b554ecae8d.ffs" \
  --patched-module-name LinuxLoader \
  --patched-module-body "${PATCHED_BODY}" \
  --output-prefix "${ARTIFACT_DIR}/pineapple-8e-oem-linuxloader-entry-loop"

echo "${ARTIFACT_DIR}/pineapple-8e-oem-linuxloader-entry-loop.boot.img"
