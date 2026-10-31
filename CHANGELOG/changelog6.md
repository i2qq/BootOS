# Changelog 6: Replace Netboot.xyz .lkrn with Direct RAM Netboot Installers for Debian, Alpine, and Ubuntu

### Summary of Changes
1. **Replaced Unsupported `.lkrn` Image with Native Kexec Installers**:
   - `netboot.xyz.lkrn` is a 16-bit real-mode iPXE BIOS binary that cannot be launched via 64-bit Linux `kexec` from userland (causing `kexec: Cannot determine the file type`).
   - Replaced Option 7 with an interactive **Online OS Netboot Installers** menu offering direct RAM-resident kernel & initrd boot for:
     - **Debian 12 Bookworm Netboot Installer** (~40 MB)
     - **Alpine Linux Live Netboot** (~15 MB)
     - **Ubuntu 24.04 LTS Minimal Netboot** (~65 MB)
   - Tested and verified that Debian and Alpine netboot kernels load into kexec segments without errors.

2. **Updated Main Menu UI**:
   - Updated Option 7 label to `Online OS Netboot Installers (Debian / Alpine / Ubuntu in DRAM)`.
