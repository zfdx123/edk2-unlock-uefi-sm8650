#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-${ROOT_DIR}/out/artifacts/repacked-8e}"
ARTIFACT_DIR="$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())' "${ARTIFACT_DIR}")"

mkdir -p "${ARTIFACT_DIR}"

LINUXLOADER_FFS="${ROOT_DIR}/out/Build/DEBUG_CLANG35/FV/Ffs/f536d559-459f-48fa-8bbc-43b554ecae8dLinuxLoader/f536d559-459f-48fa-8bbc-43b554ecae8d.ffs"
DUALSTAGE_FFS="${ROOT_DIR}/out/Build/DEBUG_CLANG35/FV/Ffs/a1168d25-1f58-4d2b-ae2e-f2f193b8897cDualStageLoader/a1168d25-1f58-4d2b-ae2e-f2f193b8897c.ffs"

if [[ ! -f "${LINUXLOADER_FFS}" ]]; then
  echo "missing LinuxLoader FFS: ${LINUXLOADER_FFS}" >&2
  exit 1
fi

python3 "${ROOT_DIR}/scripts/repack_8e_oem_linuxloader.py" \
  --reference-zip "${ROOT_DIR}/imgs/8e.zip" \
  --template-boot "${ROOT_DIR}/imgs/8e.img" \
  --linuxloader-ffs "${LINUXLOADER_FFS}" \
  --dualstage-ffs "${DUALSTAGE_FFS}" \
  --output-prefix "${ARTIFACT_DIR}/pineapple-8e-oem-linuxloader"

cat > "${ARTIFACT_DIR}/README.md" <<'EOF'
This directory contains a conservative extraction/repack experiment:

- OEM 8e UEFI/DXE/runtime are preserved from `imgs/8e.zip`
- `LinuxLoader` is replaced with the locally built 8gen3/open-source LinuxLoader FFS
- `DualStageLoader` is injected as an extra FFS from the local build
- The final image is repacked back into an 8e-style Android `boot.img`

Primary artifact:
- `pineapple-8e-oem-linuxloader.boot.img`
EOF

echo "${ARTIFACT_DIR}/pineapple-8e-oem-linuxloader.boot.img"
