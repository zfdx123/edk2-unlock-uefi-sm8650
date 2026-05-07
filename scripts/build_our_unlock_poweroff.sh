#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/out/unlock-poweroff}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${OUT_DIR}/artifacts}"
QEMU_TOOLS_DIR="${ARTIFACT_DIR}/qemu-tools"
QEMU_BOOT_RUNNER="${ARTIFACT_DIR}/run-qemu-phone-boot-payload.sh"

mkdir -p "${ARTIFACT_DIR}" "${QEMU_TOOLS_DIR}"

BOOT_IMAGE_MODE="${BOOT_IMAGE_MODE:-bootshim}"
BOOTSHIM_UEFI_BASE="${BOOTSHIM_UEFI_BASE:-0xA7000000}"
BOOTSHIM_UEFI_SIZE="${BOOTSHIM_UEFI_SIZE:-0x002C3000}"
BOOTSHIM_PAYLOAD_SOURCE="${BOOTSHIM_PAYLOAD_SOURCE:-unsigned_abl}"
BOOTSHIM_STAGE0_MODE="${BOOTSHIM_STAGE0_MODE:-reset}"
QEMU_FORCE_UNLOCK_TEST="${QEMU_FORCE_UNLOCK_TEST:-0}"

TARGET_ENVIRONMENT="experimental"
TARGET_DESCRIPTION="Experimental payload source; validate carefully before using on hardware."
if [[ "${BOOTSHIM_PAYLOAD_SOURCE}" == "unsigned_abl" && "${QEMU_FORCE_UNLOCK_TEST}" == "0" ]]; then
  TARGET_ENVIRONMENT="phone"
  TARGET_DESCRIPTION="Real-device candidate: BootShim -> unsigned_abl path with real unlock-and-shutdown logic."
elif [[ "${BOOTSHIM_PAYLOAD_SOURCE}" == "stage0_probe" ]]; then
  TARGET_ENVIRONMENT="qemu"
  TARGET_DESCRIPTION="QEMU smoke-test only: BootShim -> executable stage0 probe."
elif [[ "${QEMU_FORCE_UNLOCK_TEST}" != "0" ]]; then
  TARGET_ENVIRONMENT="qemu"
  TARGET_DESCRIPTION="QEMU-oriented LinuxLoader test path with fake VerifiedBoot protocol."
fi

FORCE_EL1_UNLOCK_AND_SHUTDOWN=1 \
BOOT_IMAGE_MODE="${BOOT_IMAGE_MODE}" \
BOOTSHIM_UEFI_BASE="${BOOTSHIM_UEFI_BASE}" \
BOOTSHIM_UEFI_SIZE="${BOOTSHIM_UEFI_SIZE}" \
BOOTSHIM_PAYLOAD_SOURCE="${BOOTSHIM_PAYLOAD_SOURCE}" \
BOOTSHIM_STAGE0_MODE="${BOOTSHIM_STAGE0_MODE}" \
QEMU_FORCE_UNLOCK_TEST="${QEMU_FORCE_UNLOCK_TEST}" \
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
  printf 'wrapped_bootshim_stage0_mode=%s\n' "${BOOTSHIM_STAGE0_MODE}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_qemu_force_unlock_test=%s\n' "${QEMU_FORCE_UNLOCK_TEST}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_target_environment=%s\n' "${TARGET_ENVIRONMENT}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'wrapped_target_description=%s\n' "${TARGET_DESCRIPTION}" >> "${ARTIFACT_DIR}/manifest.txt"
  printf 'qemu_phone_boot_runner=%s\n' "$(basename "${QEMU_BOOT_RUNNER}")" >> "${ARTIFACT_DIR}/manifest.txt"
fi

cp -f "${ROOT_DIR}/scripts/analyze_kernel_shim_layout.py" \
  "${QEMU_TOOLS_DIR}/analyze_kernel_shim_layout.py"
cp -f "${ROOT_DIR}/scripts/run_qemu_bootimg_payload.sh" \
  "${QEMU_TOOLS_DIR}/run_qemu_bootimg_payload.sh"
chmod +x "${QEMU_TOOLS_DIR}/run_qemu_bootimg_payload.sh"

cat > "${QEMU_BOOT_RUNNER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${DIR}/qemu-tools/run_qemu_bootimg_payload.sh" \
  "${DIR}/pineapple-dualstage-unlock-poweroff-boot.img" \
  "${DIR}/qemu-phone-boot"
EOF
chmod +x "${QEMU_BOOT_RUNNER}"

cat > "${ARTIFACT_DIR}/unlock-poweroff.README.md" <<'EOF'
This variant enables FORCE_EL1_UNLOCK_AND_SHUTDOWN in the local LinuxLoader build.

Behavior when the image really reaches LinuxLoader after EL1:
- call SetDeviceUnlockValue(UNLOCK, TRUE)
- on success, call ShutdownDevice()

Primary artifact:
- pineapple-dualstage-unlock-poweroff-boot.img

QEMU outer-chain smoke test:
- run-qemu-phone-boot-payload.sh
- This extracts the Android boot image kernel payload and runs it with QEMU.
- It does not emulate Qualcomm XBL/ABL, AVB, storage, SMC, or phone hardware.
EOF

cat >> "${ARTIFACT_DIR}/unlock-poweroff.README.md" <<EOF

Target environment:
- ${TARGET_ENVIRONMENT}
- ${TARGET_DESCRIPTION}

Boot image packaging:
- BOOT_IMAGE_MODE=${BOOT_IMAGE_MODE}
- BOOTSHIM_UEFI_BASE=${BOOTSHIM_UEFI_BASE}
- BOOTSHIM_UEFI_SIZE=${BOOTSHIM_UEFI_SIZE}
- BOOTSHIM_PAYLOAD_SOURCE=${BOOTSHIM_PAYLOAD_SOURCE}
- BOOTSHIM_STAGE0_MODE=${BOOTSHIM_STAGE0_MODE}
- QEMU_FORCE_UNLOCK_TEST=${QEMU_FORCE_UNLOCK_TEST}
EOF

echo "${ARTIFACT_DIR}/pineapple-dualstage-unlock-poweroff-boot.img"
