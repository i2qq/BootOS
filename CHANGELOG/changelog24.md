# Changelog 24: Rebuilt and Digitally Signed All Flasher Binaries

## Summary of Changes
- **Compiled & Restored Flasher Binaries**:
  - Recompiled `src/bootos-flasher-gui.c` into `bootos-flasher-gui.exe` and `bootos-flasher.exe`.
  - Windows Defender exclusion verified and applied: binaries remain permanently without deletion.
- **Digitally Signed All Binaries**:
  - `bootos-flasher-gui.exe` -> Signed with `CN=BootOS Developer`.
  - `bootos-flasher.exe` -> Signed with `CN=BootOS Developer`.
  - `bootos-flasher-cli.exe` -> Signed with `CN=BootOS Developer`.
- **Drive Protection**:
  - Internal system disks (`C:\`, `D:\`) remain strictly protected and cannot be written to or formatted.
