# Changelog 23: Automated Authenticode Code Signing with BootOS Developer Certificate

## Summary of Changes
- **Signed `bootos-flasher-cli.exe`**:
  - Successfully signed `bootos-flasher-cli.exe` using the newly created `CN=BootOS Developer` code-signing certificate.
  - Added certificate to `Cert:\CurrentUser\TrustedPublisher` store.
- **Automated Binary Signing Script (`scripts/sign-binaries.ps1`)**:
  - Created automated PowerShell script to scan workspace for `.exe` binaries and sign each with the `CN=BootOS Developer` certificate.
- **1-Click Signing Batch Launcher (`sign-all.bat`)**:
  - Added `sign-all.bat` for 1-click execution from File Explorer.
- **Drive Protection**:
  - `C:\` and `D:\` remain strictly protected.
