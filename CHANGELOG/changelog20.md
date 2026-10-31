# Changelog 20: 1-Click Restore FAT32 Button in GUI & Enhanced USB Recovery

## Summary of Changes
- **1-Click "Restore FAT32" Button in GUI (`bootos-flasher-gui.exe`)**:
  - Added a dedicated **`[Restore FAT32]`** button right next to the USB Drive selection dropdown.
  - Automatically wipes raw Linux partition tables on the selected USB drive and formats it back to standard MBR + FAT32 with full capacity and automatic drive letter assignment.
  - Fixes the Windows *"Windows was unable to complete the format"* error when Windows File Explorer sees raw Linux hybrid partitions with "Unknown capacity".
- **Strict Drive Protection**:
  - Hardcoded guards ensure internal storage drives `C:` and `D:` are completely immune from any format, wipe, or partition operation.
- **CLI/Script Usability (`scripts/restore-usb.ps1`)**:
  - Updated restore script to auto-detect a single USB drive and allow the user to restore immediately by pressing <kbd>Enter</kbd> with zero typing required.
