# Changelog 29: Fixed Alpine Linux `kexec_load_disabled` Kernel Lock

## Root Cause Analysis
- Alpine Linux kernels enable kernel lockdown / security hardening by default with `kernel.kexec_load_disabled = 1`.
- When set, any call to `kexec_load` returns `Operation not permitted` (`-EPERM`). Because `kexec_load_disabled` is a one-way security toggle once initialized, it must be explicitly unlocked at boot via kernel command line parameters.

## Changes Implemented
1. **Bootloader Command Line Updates**:
   - Appended `kexec_load_disabled=0` alongside `lockdown=none` across all GRUB (`bootloader/boot/grub/grub.cfg`) and ISOLINUX boot entries in `scripts/build-iso.sh`.
2. **Init & Sysctl Configuration**:
   - Configured `/etc/sysctl.d/99-kexec.conf` and `/etc/sysctl.conf` with `kernel.kexec_load_disabled = 0`.
   - Added early initialization check in `/init` right after mounting `/proc` to unlock `kexec_load_disabled`.
3. **Menu Kexec Resilience**:
   - Updated `boot_kexec()` in `src/bootos-menu.sh` to attempt unlocking `kexec_load_disabled`, tried standard `kexec -l` first (matching Alpine/Busybox conventions), added `--reset-vga` fallbacks, and added real-time diagnostic reporting for `/proc/sys/kernel/kexec_load_disabled`.
4. **Artifacts & ISO**:
   - Rebuilt `bootos.iso` (534 MB).
   - Re-signed all Windows binaries with `CN=BootOS Developer`.
