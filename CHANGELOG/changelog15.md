# Changelog 15: Native Windows GUI USB Flasher with Multi-USB Drive Selection

## Summary of Changes
- **Native Win32 GUI Flasher (`src/bootos-flasher-gui.c` -> `bootos-flasher-gui.exe` / `bootos-flasher.exe` / `bootos.exe`)**:
  - Built a standalone native Win32 GUI application (~116 KB) with zero external runtime dependencies.
  - **Multi-USB Drive Dropdown Selection**:
    - Enumerates all connected physical disks and maps logical drive letters (e.g., `[Drive E:]`, `[Drive F:]`).
    - Specifically formats each connected USB device with its volume letter, brand/model name, capacity in GB, and physical drive identifier (`\\.\PhysicalDriveN`).
    - Supports users with multiple USB flash drives inserted simultaneously, allowing instant selection via a dropdown ComboBox.
    - Added an interactive **Refresh** button to immediately rescan drives if a new USB drive is inserted while the application is open.
  - **System Drive Shielding**:
    - System disks (`C:` drive / Windows boot drive) are strictly excluded from the target list to prevent accidental overwrites.
  - **Interactive Controls & Threaded Write Engine**:
    - ISO Image picker with a "Browse..." dialog defaulting to `bootos.iso` in the workspace.
    - Background worker thread (`CreateThread`) for raw sector streaming (`1 MB` buffer) to keep the GUI fluid and responsive without freezing.
    - Real-time smooth progress bar with percentage, transferred/total MB, and transfer speed in MB/s.
    - Confirmation alert dialog before writing to ensure user intent.
    - Automatic partition refresh upon write completion.
  - **VM Sandbox Runner Button**:
    - Added a `▶ Run in VM / Sandbox` button to launch BootOS directly in Oracle VirtualBox or QEMU without needing a USB drive.
- **Build & Script Integration**:
  - Updated [`build.ps1`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/build.ps1) to compile `src/bootos-flasher-gui.c` with `-mwindows -lcomctl32 -lcomdlg32` upon each build.
  - Updated [`flash-usb.bat`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/flash-usb.bat) to launch the GUI flasher directly with administrator privilege elevation.
  - Updated [`README.md`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/README.md) with visual instructions for the GUI flasher.
