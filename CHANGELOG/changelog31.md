# Changelog 31 - Unified Syslinux APPEND Syntax and Multi-Config Fallbacks

## Overview
- Fixed ISOLINUX/SYSLINUX bootloader parameter transmission in `scripts/build-iso.sh`:
  - Replaced ambiguous separate `INITRD` and `APPEND` directives with standard single-line `APPEND initrd=/boot/initramfs.gz kexec_load_disabled=0 console=tty0 console=tty1 init=/init` under `KERNEL /boot/vmlinuz`.
  - Replicated bootloader configuration across `isolinux/isolinux.cfg`, `isolinux/syslinux.cfg`, `syslinux/syslinux.cfg`, and `boot/syslinux/syslinux.cfg` to ensure Legacy BIOS boots always parse the `kexec_load_disabled=0` kernel setup handler regardless of path resolution.
- Rebuilt `bootos.iso` and verified synchronization to `C:\Users\Victor\ISO\Other\bootos.iso`.
