# Changelog 42: Clean Disk Wiping (Windows 7 Partition Erasure), Standalone Rufus Recovery Kit, and TTY Console Recovery

### 1. Robust Terminal Console & Keyboard Recovery (Fixing Broken TTY on GUI Exit)
- Solved the unresponsive, blank TTY console when clicking `[X]`, pressing `Alt+F4`, or exiting Chromium / File Explorer.
- Integrated the official `kbd` package (`kbd_mode`) into the initramfs to reliably reset the console keyboard from RAW/Medium-RAW mode back to ASCII/UTF-8 mode (`kbd_mode -a -C /dev/tty1`).
- Added `restore_console` hooks across `bootos_explorer.py` (explicit `WM_DELETE_WINDOW` protocol handler + `os._exit(0)`), `explorer-launcher.sh`, `browser-launcher.sh`, and `bootos-menu.sh`.
- Handled terminal sanity restoration (`stty sane`, `stty echo icanon`, `\033c\033[?25h`) and clean VT switching back to `tty1` upon application close.

### 2. Clean Disk & Windows 7 Partition Overwrite (`wipe_disk_partitions`)
- Added automated and standalone disk wiping to cleanly destroy old Windows 7 NTFS partitions (`/dev/sda1` System Reserved, `/dev/sda2` RECOVERY, `/dev/sda3` OS):
  1. Forcibly unmounts all active partitions and turns off swap.
  2. Runs `wipefs -a -f` across all child partitions and the parent drive.
  3. Zeroes out the primary MBR and partition tables (first 64 MB) via `dd if=/dev/zero ... conv=fsync`.
  4. Zeroes out the backup secondary GPT table at the end of the disk (last 32 MB).
  5. Forces the kernel to rescan and drop all lingering partition nodes (`partprobe`, `blockdev --rereadpt`, `mdev -s`).
- Wired automatic partition wiping into `flash_image_to_drive` before writing any OS image.
- Added a dedicated Menu Option [8]: `Clean Wipe Disk (Erase Windows 7 NTFS /dev/sda1, sda2, sda3)`.

### 3. Native Hard Drive Installation & Standalone Rufus Kit
- Added Menu Option [7]: `Install BootOS to Internal Hard Drive / SSD (With Clean Rufus Kit)`:
  - Wipes existing partitions and sets up a dual-partition layout on the internal drive:
    - Partition 1 (`BOOTOS`): 4 GB bootable FAT32 partition with Syslinux MBR bootloader and UEFI fallback.
    - Partition 2 (`BOOTOS_DATA`): Formatted ext4 for persistent user storage and files.
  - Installs Syslinux MBR (`mbr.bin`) and COM32 modules (`menu.c32`, `ldlinux.c32`, `libutil.c32`).
  - Sets up `/boot/syslinux.cfg` and `/boot/vmlinuz` + `/boot/initramfs.gz` for standalone local booting without needing a USB drive.
- Installs a clean, standalone `/BootOS-Portable` directory separate from the OS:
  - Contains `bootos.iso` generated directly on-device using `xorriso`.
  - Bundles Windows flasher executables (`bootos-flasher-gui.exe`, `bootos-flasher.exe`, `flash-usb.bat`).
  - Includes `README-RUFUS.txt` with exact settings to burn BootOS with Rufus (MBR partition scheme, BIOS or UEFI, FAT32).
  - Preserves full build scripts (`build-iso.sh`) and source code for standalone recompilation.
