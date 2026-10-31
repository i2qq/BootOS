# Changelog 28: Dual Ubuntu 26.04 / 24.04 LTS Support & Kexec Lockdown Resolution

## 1. Dual Release Support (Ubuntu & Lubuntu 26.04 + 24.04 LTS)
- **Ubuntu 26.04 (Next-Gen Daily / Rolling Release)**:
  - Added option to download and boot Ubuntu 26.04 Daily Live Desktop ISO directly into RAM or flash directly to storage.
  - Added Ubuntu 26.04 minimal netboot installer option (~50 MB) in both the dedicated Ubuntu menu and the Online Netboot Installers menu.
- **Ubuntu 24.04.5 LTS (Noble Numbat)**:
  - Retained full Long-Term Support downloads for stable production environments.
- **Lubuntu Dual Releases**:
  - Added selector for Lubuntu 26.04 Daily Desktop alongside Lubuntu 24.04.5 LTS Desktop.
  - Three distinct execution modes provided:
    1. Direct Drive Flash (install target).
    2. Live ISO to DRAM (toram loopback).
    3. Fast Minimal Netboot (~45-50 MB).

## 2. Kexec `Operation not permitted` Resolution
- **Kernel Lockdown Bypass (`lockdown=none`)**:
  - Configured `lockdown=none` across all GRUB (`grub.cfg`) and ISOLINUX (`isolinux.cfg`) kernel boot command lines.
  - This eliminates `EPERM` / `Operation not permitted` errors triggered by kernel lockdown when loading new operating system kernels into RAM via `sys_kexec_load`.
- **Modern Syscall Ordering in `boot_kexec()`**:
  - Updated `boot_kexec()` to try `kexec -s -l` (`sys_kexec_file_load`) first, before falling back to `kexec -l` and `--reset-vga`.

## 3. Automated Binary Code-Signing Integration
- Updated `build.ps1` to automatically invoke `scripts/sign-binaries.ps1` on every build, ensuring all compiled flasher executables (`bootos-flasher-gui.exe`, `bootos-flasher.exe`, `bootos.exe`, `bootos-flasher-cli.exe`) are signed with the local `CN=BootOS Developer` code signing certificate.
