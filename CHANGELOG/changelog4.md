# Changelog 4: ISO Extraction Engine, Loop Device Support & Terminal Shell Fixes

- **ISO Extraction Engine (`7z` + Loop Mount)**:
  - Added native `7zip` package (`/usr/bin/7z`) to the BootOS image, allowing instant kernel and initramfs extraction from downloaded ISOs (including BootOS, Ubuntu, Lubuntu, Debian) without loop device errors.
  - Added automatic module loading for `loop`, `isofs`, and `squashfs` on boot.
  - Initialized `/dev/loop0` through `/dev/loop7` and `/dev/loop-control` device nodes.
  - Added smart boot parameter auto-detection (Ubuntu `casper`, BootOS/Alpine `init=/init`, generic `root=/dev/ram0`).
- **Interactive Terminal Shell (Option 8)**:
  - Fixed premature EOF on `/bin/sh` by binding console execution to `setsid cttyhack`.
  - Option 8 now opens a fully interactive root terminal shell with command line editing and diagnostics tools (`curl`, `wget`, `7z`, `kexec`, `fdisk`, `parted`).
- **iPXE / Netboot.xyz (Option 7)**:
  - Added UEFI vs BIOS runtime detection.
  - Automatically fetches `netboot.xyz.efi` on UEFI systems and `netboot.xyz.lkrn` on Legacy BIOS.
  - Added error display and interactive pause instead of immediate screen clear.
