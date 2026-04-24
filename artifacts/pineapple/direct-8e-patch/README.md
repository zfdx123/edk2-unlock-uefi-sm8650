This directory contains artifacts produced by patching the source `imgs/8e.zip` path directly.

Current validation artifact:
- `pineapple-8e-oem-linuxloader-entry-loop.boot.img`
  patches the OEM `LinuxLoader` PE32 entrypoint to a loop, then repacks the source 8e image

Purpose:
- validate that direct OEM module patching works end-to-end
- avoid replacing the whole LinuxLoader module with our own build
