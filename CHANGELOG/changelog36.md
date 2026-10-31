# Changelog 36 - Eliminate Boot Hangs on Physical Hardware (OptiPlex 990 / Intel Core i5)

## Overview
1. **Removed Blocking Sequential Modalias Probe**:
   - Removed `find /sys -name modalias | xargs -n1 modprobe` from `/init`. On real hardware (OptiPlex 990), sequentially invoking hundreds of modprobe processes causes severe blocking and hangs when drivers wait for uninstalled firmware.
   - Hardware detection is now handled purely asynchronously via `eudev` (`udevd` + `udevadm trigger`).

2. **Removed Redundant Boot-Time Depmod**:
   - Removed `depmod -a` from `/init`. The kernel module index is already generated during ISO assembly, saving 30-45 seconds of disk/RAM re-indexing.

3. **Universal TTY0/Console Attachment & Progress Indicators**:
   - Added 4-stage boot progress indicators (`[1/4] Mounting filesystems`, `[2/4] Hardware & network`, `[3/4] Storage`, `[4/4] User interface`).
   - Replaced fragile `setsid ... <> /dev/tty1` redirection with direct attachment to `/dev/tty0` (the active physical monitor foreground console) and fallback to `tty1` / `console`.
