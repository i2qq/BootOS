# Changelog 18: USB Restore & Recovery Tool (`restore-usb.bat`)

## Summary of Changes
- **USB Recovery & Restore Tool (`restore-usb.bat` / `scripts/restore-usb.ps1`)**:
  - Added a dedicated 1-click USB recovery utility to instantly restore any USB flash drive that has had raw Linux hybrid/ISO9660 partitions written to it back to a clean, standard Windows FAT32 drive.
  - Automatically shields Windows system drives (`C:` drive) while targeting removable USB drives.
  - Executes automated `diskpart` cleaning, MBR conversion, primary partition recreation, and FAT32 formatting with drive letter assignment.
  - Restores full visibility in Windows File Explorer immediately.
