# Changelog 16: Rufus-Style File-Manager Bootable USB Preparation & Complete QEMU Removal

## Summary of Changes
- **Rufus-Style File-Manager Bootable USB Preparation (`Make USB Executable`)**:
  - Replaced forced raw sector disk burning with a Rufus-style filesystem preparation mode:
    - Automatically deploys the UEFI bootloader ([`bootloader/EFI/BOOT/BOOTX64.EFI`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/bootloader/EFI/BOOT/BOOTX64.EFI)) and GRUB loopback configuration ([`bootloader/boot/grub/grub.cfg`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/bootloader/boot/grub/grub.cfg)) onto the selected USB drive letter (`E:\`, `F:\`, etc.).
    - Leaves the USB drive as a standard, fully accessible Windows drive in File Explorer.
    - Configures GRUB with dual boot capabilities:
      1. Direct execution of RAM kernel/initramfs if extracted.
      2. Native loopback boot directly from `bootos.iso` placed in the root of the USB drive.
    - Users can now simply drag-and-drop or copy `bootos.iso` straight onto their USB drive through Windows File Manager anytime, and it will execute on boot.
    - Automatically opens the USB drive in Windows File Explorer (`explorer.exe`) when preparation completes.
  - Retained secondary `Raw Hybrid Flash` button for users who specifically need raw sector DD writes.
- **Complete Removal of QEMU**:
  - Eradicated all QEMU commands, checks, and mentions across the entire codebase ([`src/bootos-flasher-gui.c`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/src/bootos-flasher-gui.c), [`src/bootos-flasher.c`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/src/bootos-flasher.c), [`bootos-run.bat`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/bootos-run.bat), and [`README.md`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/README.md)).
  - All Windows live execution now exclusively uses Oracle VirtualBox (`VBoxManage` / `vde-vlm`).
- **Git Hygiene**:
  - Updated [`.gitignore`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/.gitignore) to exclude large initramfs binaries (`*.gz`, `/bootloader/boot/initramfs.gz`) to strictly respect GitHub's 100 MB file limit while preserving the 6 MB `BOOTX64.EFI` bootloader in the repository.
