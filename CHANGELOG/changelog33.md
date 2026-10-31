# Changelog 33 - Fix Shebang CRLF Line Endings in BootOS Menu and Automated Rootfs LF Sanitization

## Overview
1. **CRLF Shebang Line Ending Fix**:
   - Fixed `/bin/sh: exec: line 0: /usr/local/bin/bootos: not found` loop occurring on VM boot.
   - When files were edited on Windows, CRLF line endings caused `/bin/sh` to seek the interpreter `#!/bin/sh\r`, which does not exist in Linux, causing the kernel to return `ENOENT` on execution.
   - Converted `src/bootos-menu.sh` to pure Unix LF format.

2. **Automated Rootfs Line Ending Sanitization**:
   - Added an automated `sed -i 's/\r$//'` sanitization pass in `scripts/build-iso.sh` for all files in `${ROOTFS_DIR}/usr/local/bin`, `${ROOTFS_DIR}/usr/local/sbin`, `${ROOTFS_DIR}/etc`, and `${ROOTFS_DIR}/init`.
   - Ensures that regardless of host OS CRLF checkout settings, all scripts inside the packed initramfs are 100% pure Unix LF.
