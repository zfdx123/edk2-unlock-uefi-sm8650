#!/bin/bash
# Usage:
#  build_boot_shim.sh -b base_address -s size

while getopts "b:s:" opt; do
    case ${opt} in
        b) BASE=${OPTARG};;
        s) SIZE=${OPTARG};;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

echo "Building bootshim:"

if [ -z "${BASE}" ] || [ -z "${SIZE}" ] ; then
    echo -e "\t\033[31;3;1mParameters not found!\033[0m"
    echo -e "Usage:"
    echo -e "\tbuild_boot_shim.sh -b base_address -s size"
    exit 1
fi

echo -e "\tUEFI BASE: ${BASE}"
echo -e "\tUEFI_SIZE: ${SIZE}"

cd BootShim
rm -f BootShim.elf BootShim.bin
make UEFI_BASE=${BASE} UEFI_SIZE=${SIZE}
cd ..
