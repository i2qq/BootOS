# Changelog 44: Native Partition Wizard & Volume Manager GUI, GParted, and Xterm Terminal Integration

### 1. BootOS Partition Wizard & Volume Manager (`bootos_partition_manager.py`)
- Created a modern graphical Disk & Volume Manager matching the BootOS dark theme.
- **Visual Disk Block Map**: Proportional canvas rendering of all partitions across selected drives with color-coded filesystem blocks (NTFS Blue, FAT32 Amber, ext4 Green, Swap Purple, Unallocated Gray) and interactive click-to-select.
- **Physical Drive Inspector**: Lists all physical drives (`/dev/sda` Seagate 500GB HDD, `/dev/sdb` USB flash) with models, total capacities, and block details.
- **Automated Partition Setup Wizards (1-Click Presets)**:
  1. *Clean Wipe Windows 7 Partitions*: Erases all NTFS partitions (`/dev/sda1`, `/dev/sda2`, `/dev/sda3`), zeroing MBR/GPT tables.
  2. *BootOS RAM-Resident Standalone Setup*: Creates a 4GB bootable FAT32 partition (Syslinux MBR) + ext4 user data partition.
  3. *Linux Ready Drive*: 1GB EFI System Partition (FAT32) + remaining ext4 root volume.
  4. *Single Full Volume*: 100% capacity single volume (ext4 or FAT32).
- **Partition Operations**:
  - Create new partition with custom size (MB/GB) and filesystem type.
  - Delete selected partition.
  - Format volume (ext4, FAT32, NTFS, exFAT) with custom label.
  - Mount/unmount volumes.
  - 1-click launch to open the partition directly inside BootOS File Explorer.
- Added Menu Option **[3]**: `Launch Partition Wizard & Volume Manager (GUI)` in `bootos-menu.sh`.
- Added `🪄 Partitions` button directly on the top toolbar of `bootos_explorer.py`.

### 2. GParted & NTFS-3G Integration
- Integrated `gparted` (v1.6.0) into the rootfs for advanced graphical partition resizing, moving, and checking.
- Integrated `ntfs-3g` for full read/write, format, and volume management of NTFS filesystems.

### 3. Xterm & Embedded Terminal Fix
- Resolved `[Errno 2] No such file or directory: 'xterm'` error.
- Integrated official `xterm` package into the rootfs.
- Added multi-terminal fallback (`xterm`, `rxvt`, `urxvt`) and an embedded Tkinter terminal window fallback in `bootos_explorer.py`.
