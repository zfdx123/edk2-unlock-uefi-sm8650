#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/out/artifacts/extracted-oem}"
OUT_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "${OUT_DIR}")"

mkdir -p "${OUT_DIR}"

extract_zip() {
  local zip_path="$1"
  local name="$2"
  local target="${OUT_DIR}/${name}"
  rm -rf "${target}"
  mkdir -p "${target}"
  7z x -y "-o${target}" "${zip_path}" >/dev/null
}

extract_zip "${ROOT_DIR}/imgs/8e.zip" "8e"
extract_zip "${ROOT_DIR}/imgs/8gen3.zip" "8gen3"

python3 "${ROOT_DIR}/scripts/analyze_qcom_elf_fv.py" \
  --input "${ROOT_DIR}/imgs/uefi.elf" \
  --output-dir "${OUT_DIR}"

python3 "${ROOT_DIR}/scripts/analyze_qcom_elf_fv.py" \
  --input "${ROOT_DIR}/imgs/abl.elf" \
  --output-dir "${OUT_DIR}"

echo "${OUT_DIR}"
