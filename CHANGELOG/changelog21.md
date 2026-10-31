# Changelog 21: One-Click Drive E Recovery Script (`fix-drive-e.bat`)

## Summary of Changes
- **Dedicated One-Click Drive E: Recovery Script (`fix-drive-e.bat`)**:
  - Created a single-purpose batch script that targets only the detected 2GB USB flash drive (`Disk 2`) and prompts for Windows UAC elevation.
  - Automatically executes `diskpart` to clean unreadable Linux partition headers, convert to standard MBR, create an active primary partition, format as clean FAT32, and assign drive letter `E:`.
  - Fixes the Windows *"You need to format the disk in drive E: before you can use it"* prompt.
  - Opens `E:\` in File Explorer upon completion with zero errors.
- **Drive Protection**:
  - Strictly targets USB `Disk 2` (2 GB), completely shielding `Disk 0` (`D:\`) and `Disk 1` (`C:\`).
