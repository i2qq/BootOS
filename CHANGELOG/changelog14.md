# Changelog 14: Standalone Executable Flasher & Direct Windows Runner (`bootos-flasher.exe` / `bootos.exe`)

## Summary of Changes
- **Standalone Windows Executable Flasher (`src/bootos-flasher.c` -> `bootos-flasher.exe` / `bootos.exe`)**:
  - Implemented a native, lightweight (~104 KB) Win32 executable written in C with zero external runtime dependencies.
  - Replaces third-party flashing utilities (like Rufus or BalenaEtcher) by writing raw hybrid ISO sectors directly to USB physical drives (`\\.\PhysicalDriveN`).
  - **Drive Detection & System Protection**:
    - Automatically maps connected storage devices and logical drive letters (`D:`, `E:`, etc.).
    - Distinguishes USB removable media from internal fixed drives.
    - Strictly blocks and shields Windows internal system drives (`C:` / system disk) to eliminate any risk of accidental overwrite.
  - **Raw Hybrid Flashing with Progress**:
    - Unmounts and locks the target USB volumes (`FSCTL_LOCK_VOLUME`, `FSCTL_DISMOUNT_VOLUME`).
    - Streams `bootos.iso` in 1 MB blocks directly to the physical drive, showing an animated progress bar, percentage, written/total megabytes, and real-time write speed (MB/s).
    - Flushes disk buffers (`FlushFileBuffers`) and signals Windows to refresh partition tables (`IOCTL_DISK_UPDATE_PROPERTIES`).
    - Produces a 100% bootable USB drive compatible with both Legacy BIOS and modern UEFI.
- **Direct Windows Runner (`bootos-run.bat` & Option `[2]`)**:
  - Added direct executable execution mode allowing BootOS to run live on Windows inside a virtualized sandbox (Oracle VirtualBox or QEMU) with 1 click without needing a USB drive or rebooting the host machine.
- **One-Click Batch & PowerShell Companion Scripts**:
  - Added `flash-usb.bat`: Prompts for Administrator elevation via UAC and runs the flasher.
  - Added `scripts/flash-usb.ps1`: Pure PowerShell implementation using .NET FileStreams for automated or CLI environments.
  - Added `bootos-run.bat`: 1-click launcher for the live virtual sandbox.
- **Build Integration**:
  - Updated `build.ps1` to automatically compile `bootos-flasher.exe` and `bootos.exe` upon every build.
  - Updated `README.md` with step-by-step instructions for 1-click USB flashing and Windows direct execution.
