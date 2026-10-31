# Changelog 32 - Hardware Forced Reboot Handlers, Disk Capacity Pre-Flight Validation, and Multi-Path Bootloader Sync

## Overview
1. **Forced Hardware Reboot & Poweroff Handlers**:
   - Resolved the issue where `sudo reboot` or `reboot` from the shell/menu failed to reboot the system because PID 1 (`/init`) is a minimal shell script without standard SysVinit signal trapping.
   - Installed native wrapper scripts (`/usr/local/bin/reboot`, `/usr/local/sbin/reboot`, `/usr/local/bin/poweroff`, `/usr/local/sbin/poweroff`, `shutdown`, `halt`) directly executing `busybox reboot -f` or triggering the kernel reboot syscall via `/proc/sysrq-trigger`.
   - Added signal traps in `/init` (`trap 'sync; echo 1 > /proc/sys/kernel/sysrq; busybox reboot -f || echo b > /proc/sysrq-trigger' TERM INT QUIT`).
   - Updated menu options [12] ("Reboot System") and [13] ("Power Off") to execute forced hardware reboot and poweroff.

2. **Disk Capacity Pre-Flight & Pipefail Check**:
   - Enhanced `flash_image_to_drive` to query target drive capacity via `blockdev` or `/sys/class/block/*/size` before attempting to write.
   - Added explicit pre-flight validation preventing flashing when the target disk is smaller than the OS image (e.g. attempting to flash a 3.8 GB Lubuntu ISO onto a 1 GB virtual disk).
   - Added `pipefail` error checking on `curl | dd` streaming pipelines to catch out-of-disk-space errors immediately and report actionable errors rather than falsely reporting success.

3. **Multi-Path Syslinux Bootloader Configuration**:
   - Replicated the unlocked `kexec_load_disabled=0` configuration across all possible search paths (`/isolinux.cfg`, `/syslinux.cfg`, `/isolinux/isolinux.cfg`, `/isolinux/syslinux.cfg`, `/syslinux/syslinux.cfg`, `/boot/syslinux/syslinux.cfg`).
