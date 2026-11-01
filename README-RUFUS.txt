==============================================================================
BootOS Portable Recovery & USB Flasher Kit
==============================================================================
This clean, standalone folder is completely separate from the main OS install.
It contains everything needed to recompile or burn BootOS to any USB flash
drive using Rufus, BootOS Flasher, or dd.

HOW TO FLASH WITH RUFUS (Windows):
1. Download or open Rufus (https://rufus.ie)
2. Insert your USB flash drive (any size >= 1 GB, e.g. 2GB, 4GB, 8GB).
3. Device: Select your USB drive.
4. Boot selection: Click 'SELECT' and choose 'bootos.iso'.
5. Partition scheme: MBR
6. Target system: BIOS (or UEFI)
7. File system: FAT32 (Default)
8. Click 'START'. If prompted, select 'Write in ISO Image mode (Recommended)'.
9. BootOS is ready! Plug the USB into any PC and boot.

HOW TO FLASH WITH BOOTOS FLASHER (Windows - No Rufus required):
- Double-click 'tools/bootos-flasher-gui.exe' (or 'tools/bootos-flasher.exe').

HOW TO RECOMPILE BOOTOS (Linux / WSL):
- Run: ./scripts/build-iso.sh
==============================================================================
