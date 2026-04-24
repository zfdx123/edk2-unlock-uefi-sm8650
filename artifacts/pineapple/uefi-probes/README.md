`uefi-probes/` contains fixed reboot probes for key UEFI checkpoints.

Files:
- `pineapple-linuxloader-entry.boot.img`: reboot at `LinuxLoaderEntry`
- `pineapple-linuxloader-after-boardinit.boot.img`: reboot after `BoardInit()` in `LinuxLoader`
- `pineapple-linuxloader-before-stage2.boot.img`: reboot before launching the embedded second stage from `LinuxLoader`
- `pineapple-dualstage-entry.boot.img`: reboot at `DualStageLoaderEntry`
- `pineapple-dualstage-after-boardinit.boot.img`: reboot after `BoardInit()` in `DualStageLoader`
- `pineapple-dualstage-before-loadimage.boot.img`: reboot right before `LoadImageAndAuth()` in `DualStageLoader`

Each image also has:
- `.raw.bin`: uncompressed 8e-style shim payload
- `.raw.bin.gz`: compressed kernel payload embedded into the boot image
- `.layout.json`: inner shim layout summary

Matching outer boot layout reports are under `../oem/` as `*.boot.layout.json`.
