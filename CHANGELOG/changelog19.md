# Changelog 19: Strict C:\ and D:\ Drive Protection Rule & Code Enforcements

## Summary of Changes
- **Permanent Agent Rule (`C:\Users\Victor\.gemini\config\rules\protected-drives.md`)**:
  - Created a persistent agent rule strictly shielding internal storage drives `C:\` (Windows OS / System Drive) and `D:\` (Personal Backups, Data, and Projects) from any disk writing, wiping, formatting, or partition manipulation.
- **Codebase Enforcements**:
  - **`src/bootos-flasher-gui.c`**:
    - Hardcoded exclusion of `C:` and `D:` drives, as well as non-USB devices, from the target dropdown list and flash execution handler.
  - **`src/bootos-flasher.c`**:
    - Added hard blocks preventing `C:` and `D:` selection.
  - **`scripts/restore-usb.ps1`**:
    - Strictly filters out disks associated with `C:` and `D:` partitions and non-USB bus types.
