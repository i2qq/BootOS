# Changelog 22: Rebuilt Windows GUI Flasher & Launch Priority

## Summary of Changes
- **Rebuilt `bootos-flasher-gui.exe`**:
  - Recompiled `src/bootos-flasher-gui.c` into a clean standalone Windows GUI binary (`bootos-flasher-gui.exe`).
  - Native multi-USB drive selector, real-time flashing progress bar, hybrid MBR writer, and 1-click FAT32 USB recovery tool.
- **1-Click GUI Compiler Script (`build-gui.bat`)**:
  - Added dedicated script to compile `src/bootos-flasher-gui.c` to `bootos-flasher-gui.exe` and `bootos-flasher.exe` on demand once Windows Defender exclusion is set.
- **Updated `flash-usb.bat` Launch Priority**:
  - Updated `flash-usb.bat` to detect and launch `bootos-flasher-gui.exe` first with administrative elevation.
  - Retained fallback chain to PowerShell direct flasher if binaries are absent or blocked.
- **Drive Protection**:
  - Internal system disks (`C:\`, `D:\`) remain strictly protected and cannot be written to or formatted.
