# Changelog 37 - Unify Console Output to TTY0 and Use Non-Blocking Blkid for Storage Probe

## Overview
1. **Unified Active Console (TTY0)**:
   - Removed secondary `console=tty1` parameter from ISOLINUX and GRUB kernel command lines.
   - Using single `console=tty0` guarantees that kernel initialization messages and the interactive BootOS menu are bound to the exact same physical display output, eliminating the black screen / invisible TTY1 mismatch.

2. **Non-Blocking Blkid Storage Probing**:
   - Replaced raw disk traversal with `blkid -o device -t TYPE=vfat -t TYPE=ext4`.
   - Prevents synchronous `mount` calls from hanging the boot sequence when unpartitioned SATA hard drives, sleeping disks, or optical drives are connected to the motherboard.
