#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out/qemu-linuxloader-force-unlock}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${OUT_DIR}/artifacts}"
QEMU_BUILD_DIR="${OUT_DIR}/ArmVirtQemu"
ESP_DIR="${ARTIFACT_DIR}/esp"
ESP_IMG="${ARTIFACT_DIR}/linuxloader-force-unlock-esp.img"
QEMU_FD="${ARTIFACT_DIR}/QEMU_EFI.fd"
LINUXLOADER_EFI="${ARTIFACT_DIR}/linuxloader-force-unlock.efi"
RUN_SCRIPT="${ARTIFACT_DIR}/run-qemu-linuxloader-force-unlock.sh"
README_PATH="${ARTIFACT_DIR}/README.md"
QEMU_EFI_SOURCE="${QEMU_EFI_SOURCE:-system}"

mkdir -p "${ARTIFACT_DIR}" "${ESP_DIR}"

BOARD_NAME="${BOARD_NAME:-autoghgvm}"
BUILD_TARGET="${BUILD_TARGET:-DEBUG}"
TOOL_CHAIN_TAG="${TOOL_CHAIN_TAG:-CLANG35}"
TARGET_ARCH="${TARGET_ARCH:-AARCH64}"

BOOT_IMAGE_MODE=legacy \
BOARD_NAME="${BOARD_NAME}" \
QEMU_FORCE_UNLOCK_TEST=1 \
OUT_DIR="${OUT_DIR}" \
ARTIFACT_DIR="${ARTIFACT_DIR}" \
"${ROOT_DIR}/scripts/build_pineapple_ci.sh"

cp -f "${ARTIFACT_DIR}/pineapple-stage1-linuxloader.efi" "${LINUXLOADER_EFI}"

find_system_qemu_efi() {
  local candidate
  for candidate in \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    /usr/share/qemu/QEMU_EFI.fd; do
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

SYSTEM_QEMU_EFI=""
if [[ "${QEMU_EFI_SOURCE}" == "system" || "${QEMU_EFI_SOURCE}" == "auto" ]]; then
  if SYSTEM_QEMU_EFI="$(find_system_qemu_efi)"; then
    cp -f "${SYSTEM_QEMU_EFI}" "${QEMU_FD}"
    QEMU_EFI_SOURCE="system:${SYSTEM_QEMU_EFI}"
  elif [[ "${QEMU_EFI_SOURCE}" == "system" ]]; then
    echo "error: system QEMU EFI firmware not found. Install qemu-efi-aarch64 or set QEMU_EFI_SOURCE=build." >&2
    exit 1
  fi
fi

if [[ ! -f "${QEMU_FD}" ]]; then
  pushd "${ROOT_DIR}" >/dev/null
  export WORKSPACE="${ROOT_DIR}"
  export PACKAGES_PATH="${ROOT_DIR}"
  export CONF_PATH="${ROOT_DIR}/Conf"
  export GCC5_AARCH64_PREFIX="${GCC5_AARCH64_PREFIX:-aarch64-linux-gnu-}"

  set +u
  . "${ROOT_DIR}/edksetup.sh"
  set -u
  make -C BaseTools

  build \
    -p "${ROOT_DIR}/ArmVirtPkg/ArmVirtQemu.dsc" \
    -a AARCH64 \
    -t GCC5 \
    -b DEBUG \
    -j "${OUT_DIR}/build_armvirt_qemu.log"
  popd >/dev/null

  cp -f "${ROOT_DIR}/Build/ArmVirtQemu-AARCH64/DEBUG_GCC5/FV/QEMU_EFI.fd" "${QEMU_FD}"
  QEMU_EFI_SOURCE="build:ArmVirtPkg/ArmVirtQemu.dsc"
fi

mkdir -p "${ESP_DIR}/EFI/BOOT"
cp -f "${LINUXLOADER_EFI}" "${ESP_DIR}/EFI/BOOT/BOOTAA64.EFI"
cat > "${ESP_DIR}/startup.nsh" <<'EOF'
fs0:\EFI\BOOT\BOOTAA64.EFI
EOF

rm -f "${ESP_IMG}"
dd if=/dev/zero of="${ESP_IMG}" bs=1M count=64 status=none
mkfs.vfat "${ESP_IMG}" >/dev/null
mmd -i "${ESP_IMG}" ::/EFI ::/EFI/BOOT
mcopy -i "${ESP_IMG}" "${ESP_DIR}/EFI/BOOT/BOOTAA64.EFI" ::/EFI/BOOT/BOOTAA64.EFI
mcopy -i "${ESP_IMG}" "${ESP_DIR}/startup.nsh" ::/startup.nsh

cat > "${RUN_SCRIPT}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec qemu-system-aarch64 \
  -machine virt,gic-version=3,virtualization=on \
  -cpu max \
  -m 4096 \
  -nographic \
  -serial mon:stdio \
  -bios "${DIR}/QEMU_EFI.fd" \
  -drive if=none,format=raw,file="${DIR}/linuxloader-force-unlock-esp.img",id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -net none \
  -no-reboot
EOF
chmod +x "${RUN_SCRIPT}"

cat > "${README_PATH}" <<EOF
QEMU LinuxLoader force-unlock artifact

Contents:
- QEMU_EFI.fd
- linuxloader-force-unlock.efi
- linuxloader-force-unlock-esp.img
- run-qemu-linuxloader-force-unlock.sh

Purpose:
- Boot LinuxLoader as a normal UEFI application under ArmVirt/QEMU
- Exercise the QEMU_FORCE_UNLOCK_TEST path
- Avoid depending on the phone boot chain while validating LinuxLoader logic

Build settings:
- BOARD_NAME=${BOARD_NAME}
- BUILD_TARGET=${BUILD_TARGET}
- TOOL_CHAIN_TAG=${TOOL_CHAIN_TAG}
- TARGET_ARCH=${TARGET_ARCH}
- QEMU_FORCE_UNLOCK_TEST=1
- BOOT_IMAGE_MODE=legacy
- QEMU_EFI_SOURCE=${QEMU_EFI_SOURCE}
EOF

echo "${ARTIFACT_DIR}"
