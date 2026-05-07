#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${1:-${ROOT_DIR}/out/artifacts}"
BOARD_NAME="${BOARD_NAME:-pineapple}"
BUILD_TARGET="${BUILD_TARGET:-DEBUG}"
TOOL_CHAIN_TAG="${TOOL_CHAIN_TAG:-CLANG35}"
TARGET_ARCH="${TARGET_ARCH:-AARCH64}"
TARGET_BUILD_VARIANT="${TARGET_BUILD_VARIANT:-userdebug}"

mkdir -p "${ARTIFACT_DIR}/uefi-probes" "${ARTIFACT_DIR}/oem"

export WORKSPACE="${ROOT_DIR}"
export PACKAGES_PATH="${ROOT_DIR}"
export CONF_PATH="${ROOT_DIR}/Conf"
export ROOT_DIR="${WORKSPACE}"
export BUILD_NATIVE_AARCH64=true
export TARGET_BUILD_VARIANT
export CLANG35_BIN="${CLANG35_BIN:-/usr/bin/}"
export CLANG35_AARCH64_PREFIX="${CLANG35_AARCH64_PREFIX:-/usr/bin/llvm-}"
export FUSE_LD="${FUSE_LD:-/usr/bin/ld.lld}"
export MAKEPATH="${MAKEPATH:-/usr/bin/}"
export ABL_SRC="."

mkdir -p "${CONF_PATH}"

set +u
. "${ROOT_DIR}/edksetup.sh" BaseTools
set -u
make -C "${ROOT_DIR}/BaseTools"

set +u
. "${ROOT_DIR}/QcomModulePkg/build.config.msm.${BOARD_NAME}"
set -u

INIT_BIN_VALUE="${INIT_BIN_LE:-/init}"
TARGET_AUDIO_FRAMEWORK_VALUE="${TARGET_AUDIO_FRAMEWORK:-unknown}"
BASE_ADDRESS_VALUE="${BASE_ADDRESS:-0xA8000000}"

append_define() {
  local -n ref="$1"
  local name="$2"
  local value="${3-}"
  if [[ -n "${value}" ]]; then
    ref+=(-D "${name}=${value}")
  fi
}

build_one() {
  local probe_id="$1"
  local probe_name="$2"
  local build_output_dir="${ROOT_DIR}/out/probe-build/${probe_name}/Build"
  local log_file="${ROOT_DIR}/out/probe-build/${probe_name}/build.log"
  mkdir -p "$(dirname "${log_file}")" "${build_output_dir}"
  local build_args=(
    build
    -p "${ROOT_DIR}/QcomModulePkg/QcomModulePkg.dsc"
    -a "${TARGET_ARCH}"
    -t "${TOOL_CHAIN_TAG}"
    -b "${BUILD_TARGET}"
    -j "${log_file}"
    -D "ABL_OUT_DIR=${build_output_dir}"
    -D "BOARD_BOOTLOADER_PRODUCT_NAME=${BOARD_NAME}"
    -D "PROBE_REBOOT_STAGE_ID=${probe_id}"
  )

  append_define build_args VERIFIED_BOOT_LE "${VERIFIED_BOOT_LE-}"
  append_define build_args VERIFIED_BOOT_ENABLED "${VERIFIED_BOOT_ENABLED-}"
  append_define build_args ROOT_PARTLABEL_SUPPORT "${ROOT_PARTLABEL_SUPPORT-}"
  append_define build_args USE_DUMMY_BCC "${USE_DUMMY_BCC-}"
  append_define build_args EARLY_ETH_ENABLED "${EARLY_ETH_ENABLED-}"
  append_define build_args AUTO_LVGVM_ABL "${AUTO_LVGVM_ABL-}"
  append_define build_args HIBERNATION_SUPPORT_NO_AES "${HIBERNATION_SUPPORT_NO_AES-}"
  append_define build_args HIBERNATION_SUPPORT_AES "${HIBERNATION_SUPPORT_AES-}"
  append_define build_args HIBERNATION_TZ_ENCRYPTION "${HIBERNATION_TZ_ENCRYPTION-}"
  append_define build_args APPEND_RAM_PARTITIONS_TO_MEM_NODE "${APPEND_RAM_PARTITIONS_TO_MEM_NODE-}"
  append_define build_args EARLY_ETH_AS_DLKM "${EARLY_ETH_AS_DLKM-}"
  append_define build_args BOOTIMAGE_LOAD_VERIFY_IN_PARALLEL "${BOOTIMAGE_LOAD_VERIFY_IN_PARALLEL-}"
  append_define build_args AB_RETRYCOUNT_DISABLE "${AB_RETRYCOUNT_DISABLE-}"
  append_define build_args TARGET_BOARD_TYPE_AUTO "${TARGET_BOARD_TYPE_AUTO-}"
  append_define build_args VERITY_LE "${VERITY_LE-}"
  append_define build_args USER_BUILD_VARIANT "${USER_BUILD_VARIANT-}"
  append_define build_args DISABLE_PARALLEL_DOWNLOAD_FLASH "${DISABLE_PARALLEL_DOWNLOAD_FLASH-}"
  append_define build_args ENABLE_LE_VARIANT "${ENABLE_LE_VARIANT-}"
  append_define build_args WEAR_OS "${WEAR_OS-}"
  append_define build_args ENABLE_LV_ATOMIC_AB "${ENABLE_LV_ATOMIC_AB-}"
  append_define build_args BUILD_USES_RECOVERY_AS_BOOT "${BUILD_USES_RECOVERY_AS_BOOT-}"
  append_define build_args INIT_BIN "${INIT_BIN_VALUE}"
  append_define build_args UBSAN_UEFI_GCC_FLAG_UNDEFINED "${UBSAN_UEFI_GCC_FLAG_UNDEFINED-}"
  append_define build_args UBSAN_UEFI_GCC_FLAG_ALIGNMENT "${UBSAN_UEFI_GCC_FLAG_ALIGNMENT-}"
  append_define build_args NAND_SQUASHFS_SUPPORT "${NAND_SQUASHFS_SUPPORT-}"
  append_define build_args BASE_ADDRESS "${BASE_ADDRESS_VALUE}"
  append_define build_args LINUX_BOOT_CPU_SELECTION_ENABLED "${LINUX_BOOT_CPU_SELECTION_ENABLED-}"
  append_define build_args TARGET_LINUX_BOOT_CPU_ID "${TARGET_LINUX_BOOT_CPU_ID-}"
  append_define build_args HIBERNATION_SWAP_PARTITION_NAME "${HIBERNATION_SWAP_PARTITION_NAME-}"
  append_define build_args DISABLE_DTBO_PARTITION "${DISABLE_DTBO_PARTITION-}"
  append_define build_args SUPPORT_AB_BOOT_LXC "${SUPPORT_AB_BOOT_LXC-}"
  append_define build_args TARGET_SUPPORTS_EARLY_USB_INIT "${TARGET_SUPPORTS_EARLY_USB_INIT-}"
  append_define build_args TARGET_AUDIO_FRAEMEWORK "${TARGET_AUDIO_FRAMEWORK_VALUE}"
  append_define build_args ENABLE_EARLY_SERVICES "${ENABLE_EARLY_SERVICES-}"
  append_define build_args KERNEL_LOAD_ADDRESS "${KERNEL_LOAD_ADDRESS-}"
  append_define build_args KERNEL_SIZE_RESERVED "${KERNEL_SIZE_RESERVED-}"
  append_define build_args DISABLE_KERNEL_PROTOCOL "${DISABLE_KERNEL_PROTOCOL-}"
  append_define build_args NAND_UBI_VOLUME_FLASHING_ENABLED "${NAND_UBI_VOLUME_FLASHING_ENABLED-}"
  append_define build_args REMOVE_CARVEOUT_REGION "${REMOVE_CARVEOUT_REGION-}"
  append_define build_args QSPA_BOOTCONFIG_ENABLE "${QSPA_BOOTCONFIG_ENABLE-}"
  append_define build_args AUTO_VIRT_ABL "${AUTO_VIRT_ABL-}"
  append_define build_args DDR_SUPPORTS_SCT_CONFIG "${DDR_SUPPORTS_SCT_CONFIG-}"

  "${build_args[@]}"

  local build_root="${build_output_dir}/${BUILD_TARGET}_${TOOL_CHAIN_TAG}"
  local fv_image="${build_root}/FV/FVMAIN_COMPACT.Fv"
  local stage1_efi="${build_root}/${TARGET_ARCH}/QcomModulePkg/Application/LinuxLoader/LinuxLoader/${BUILD_TARGET}/LinuxLoader.efi"
  local stage2_efi="${build_root}/${TARGET_ARCH}/QcomModulePkg/Application/DualStageLoader/DualStageLoader/${BUILD_TARGET}/DualStageLoader.efi"
  local unsigned_abl="${ROOT_DIR}/out/probe-build/${probe_name}/unsigned_abl.elf"
  local out_prefix="${ARTIFACT_DIR}/uefi-probes/${probe_name}"

  python3 "${ROOT_DIR}/QcomModulePkg/Tools/image_header.py" \
    "${fv_image}" \
    "${unsigned_abl}" \
    0x9FA00000 \
    elf \
    32 \
    nohash

  python3 "${ROOT_DIR}/scripts/build_kernel_shim_payload.py" \
    --fv "${fv_image}" \
    --stage1-efi "${stage1_efi}" \
    --stage2-efi "${stage2_efi}" \
    --unsigned-abl "${unsigned_abl}" \
    --output-prefix "${out_prefix}"

  python3 "${ROOT_DIR}/scripts/repack_8e_style_boot.py" \
    --template-8e "${ROOT_DIR}/imgs/8e.img" \
    --kernel-gzip "${out_prefix}.raw.bin.gz" \
    --output "${out_prefix}.boot.img"

  python3 "${ROOT_DIR}/scripts/analyze_kernel_shim_layout.py" \
    --input "${out_prefix}.boot.img" \
    --output-dir "${ARTIFACT_DIR}/oem"

  rm -f \
    "${ARTIFACT_DIR}/oem/${probe_name}.boot.kernel.bin" \
    "${ARTIFACT_DIR}/oem/${probe_name}.boot.kernel.unpacked.bin"
}

should_build_probe() {
  local probe_name="$1"
  local filter="${PROBE_FILTER:-}"
  if [[ -z "${filter}" ]]; then
    return 0
  fi

  local item
  IFS=',' read -r -a _probe_filter_items <<< "${filter}"
  for item in "${_probe_filter_items[@]}"; do
    if [[ "${item}" == "${probe_name}" ]]; then
      return 0
    fi
  done
  return 1
}

declare -a PROBES=(
  "1:pineapple-linuxloader-entry"
  "2:pineapple-linuxloader-after-boardinit"
  "3:pineapple-linuxloader-before-stage2"
  "11:pineapple-dualstage-entry"
  "12:pineapple-dualstage-after-boardinit"
  "13:pineapple-dualstage-before-loadimage"
)

for probe in "${PROBES[@]}"; do
  probe_id="${probe%%:*}"
  probe_name="${probe#*:}"
  if should_build_probe "${probe_name}"; then
    build_one "${probe_id}" "${probe_name}"
  fi
done
