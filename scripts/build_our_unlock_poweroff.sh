#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out/unlock-poweroff}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${OUT_DIR}/artifacts}"

find_ndk_llvm_bin() {
  local candidate
  local search_roots=()

  if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    search_roots+=("${ANDROID_NDK_HOME}")
  fi

  search_roots+=(
    "${HOME}/Android/Sdk/ndk"
    "/mnt/c/Users/${USER}/AppData/Local/Android/Sdk/ndk"
    "/mnt/c/Android/Sdk/ndk"
  )

  for root in "${search_roots[@]}"; do
    [[ -d "${root}" ]] || continue
    if [[ -x "${root}/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]]; then
      printf '%s\n' "${root}/toolchains/llvm/prebuilt/linux-x86_64/bin"
      return 0
    fi
    candidate="$(find "${root}" -maxdepth 3 -path '*/toolchains/llvm/prebuilt/linux-x86_64/bin/clang' -print 2>/dev/null | sort | tail -n 1)"
    if [[ -n "${candidate}" ]]; then
      dirname "${candidate}"
      return 0
    fi
  done

  return 1
}

ensure_host_tools() {
  local llvm_bin=""

  if [[ -z "${CLANG35_BIN:-}" ]]; then
    if command -v clang >/dev/null 2>&1; then
      CLANG35_BIN="$(dirname "$(command -v clang)")/"
    elif llvm_bin="$(find_ndk_llvm_bin)"; then
      CLANG35_BIN="${llvm_bin}/"
    fi
  fi

  if [[ -z "${FUSE_LD:-}" && -n "${CLANG35_BIN:-}" && -x "${CLANG35_BIN}ld.lld" ]]; then
    FUSE_LD="${CLANG35_BIN}ld.lld"
  fi

  if [[ -z "${MAKEPATH:-}" && -x /usr/bin/make ]]; then
    MAKEPATH="/usr/bin/"
  fi

  if [[ -z "${CLANG35_BIN:-}" || ! -x "${CLANG35_BIN}clang" ]]; then
    echo "error: clang not found. Set ANDROID_NDK_HOME or CLANG35_BIN before running this script." >&2
    exit 1
  fi

  if [[ ! -x "${CLANG35_BIN}llvm-objcopy" ]]; then
    echo "error: llvm-objcopy not found under ${CLANG35_BIN}. Install LLVM/NDK or set CLANG35_BIN explicitly." >&2
    exit 1
  fi

  if [[ -z "${MAKEPATH:-}" || ! -x "${MAKEPATH}make" ]]; then
    echo "error: make not found. Install build tools or set MAKEPATH explicitly." >&2
    exit 1
  fi
}

mkdir -p "${ARTIFACT_DIR}"

BOOT_IMAGE_MODE="${BOOT_IMAGE_MODE:-bootshim}"
BOOTSHIM_UEFI_BASE="${BOOTSHIM_UEFI_BASE:-0x80200000}"
BOOTSHIM_UEFI_SIZE="${BOOTSHIM_UEFI_SIZE:-0x0003D000}"
BOOTSHIM_PAYLOAD_SOURCE="${BOOTSHIM_PAYLOAD_SOURCE:-unsigned_abl}"

ensure_host_tools

FORCE_EL1_UNLOCK_AND_SHUTDOWN=1 \
BOOT_IMAGE_MODE="${BOOT_IMAGE_MODE}" \
BOOTSHIM_UEFI_BASE="${BOOTSHIM_UEFI_BASE}" \
BOOTSHIM_UEFI_SIZE="${BOOTSHIM_UEFI_SIZE}" \
BOOTSHIM_PAYLOAD_SOURCE="${BOOTSHIM_PAYLOAD_SOURCE}" \
CLANG35_BIN="${CLANG35_BIN}" \
FUSE_LD="${FUSE_LD:-}" \
MAKEPATH="${MAKEPATH}" \
OUT_DIR="${OUT_DIR}" \
ARTIFACT_DIR="${ARTIFACT_DIR}" \
"${ROOT_DIR}/scripts/build_pineapple_ci.sh"

cp -f "${ARTIFACT_DIR}/pineapple-dualstage-boot.img" \
  "${ARTIFACT_DIR}/pineapple-dualstage-unlock-poweroff-boot.img"

if [[ -f "${ARTIFACT_DIR}/pineapple-stage1-linuxloader.efi" ]]; then
  cp -f "${ARTIFACT_DIR}/pineapple-stage1-linuxloader.efi" \
    "${ARTIFACT_DIR}/pineapple-stage1-linuxloader-unlock-poweroff.efi"
fi

if [[ -f "${ARTIFACT_DIR}/manifest.txt" ]]; then
  cat >> "${ARTIFACT_DIR}/manifest.txt" <<'EOF'
wrapped_artifact=pineapple-dualstage-unlock-poweroff-boot.img
wrapped_stage1_efi=pineapple-stage1-linuxloader-unlock-poweroff.efi
EOF
  printf 'wrapped_boot_image_mode=%s\n' "${BOOT_IMAGE_MODE}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_bootshim_uefi_base=%s\n' "${BOOTSHIM_UEFI_BASE}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_bootshim_uefi_size=%s\n' "${BOOTSHIM_UEFI_SIZE}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_bootshim_payload_source=%s\n' "${BOOTSHIM_PAYLOAD_SOURCE}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_clang35_bin=%s\n' "${CLANG35_BIN}" >> "${ARTIFACT_DIR}/manifest.txt"
fi

cat > "${ARTIFACT_DIR}/unlock-poweroff.README.md" <<'EOF'
This variant enables FORCE_EL1_UNLOCK_AND_SHUTDOWN in the local LinuxLoader build.

Behavior when the image really reaches LinuxLoader after EL1:
- call SetDeviceUnlockValue(UNLOCK, TRUE)
- on success, call ShutdownDevice()

Primary artifact:
- pineapple-dualstage-unlock-poweroff-boot.img
EOF

cat >> "${ARTIFACT_DIR}/unlock-poweroff.README.md" <<EOF

Boot image packaging:
- BOOT_IMAGE_MODE=${BOOT_IMAGE_MODE}
- BOOTSHIM_UEFI_BASE=${BOOTSHIM_UEFI_BASE}
- BOOTSHIM_UEFI_SIZE=${BOOTSHIM_UEFI_SIZE}
- BOOTSHIM_PAYLOAD_SOURCE=${BOOTSHIM_PAYLOAD_SOURCE}
- CLANG35_BIN=${CLANG35_BIN}
EOF

echo "${ARTIFACT_DIR}/pineapple-dualstage-unlock-poweroff-boot.img"
