# Changelog 1: Initial Release of BootOS

- **Architecture**: Designed ultra-lightweight RAM-resident operating system (< 200MB ISO, well under the 1GB limit).
- **100% DRAM Mode**: Boots entire root filesystem into memory (`tmpfs` / ramdisk), completely freeing the physical USB drive (safely unplug after boot).
- **Target OS Booting (`kexec`)**:
  - Added Lubuntu fast netboot & live ISO kexec loader.
  - Added Ubuntu 24.04 LTS fast netboot & desktop live kexec loader.
  - Added Custom OS URL downloader for direct kernel/initrd boot.
  - Added direct disk flashing utility to stream and write ISO images directly to internal hard drives/SSDs (`/dev/sda`).
  - Added iPXE / Netboot.xyz chainloader for on-demand network installation.
- **Hardware Compatibility**:
  - Legacy BIOS MBR boot via ISOLINUX (specifically optimized for older PCs).
  - UEFI x86_64 boot via GRUB standalone EFI image.
  - Hybrid ISO configuration supporting raw USB flashing via Rufus, BalenaEtcher, or Ventoy.
- **Tooling**:
  - Added `src/bootos-menu.sh` ANSI terminal interface.
  - Added `scripts/build-iso.sh` builder script.
  - Added `build.ps1` one-click Windows rebuild helper.
  - Added `README.md` with step-by-step flashing instructions for 2GB USB drives.
