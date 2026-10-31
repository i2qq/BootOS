# Changelog 26: Fixed BootOS File Explorer Launch Subsystem & Option 11 Persistence

## Summary of Changes
- **Fixed File Explorer Launch Execution**:
  - Refactored `src/explorer-launcher.sh` to delegate to the proven GUI subsystem (`browser-launcher.sh`) in native `app` mode (`--app=http://127.0.0.1:54321/`).
  - Added support for `--app` kiosk mode in `src/browser-launcher.sh`, ensuring Chromium launches with required `dbus-run-session`, `--disable-dev-shm-usage`, and `--disable-gpu-sandbox` flags to prevent startup crashes.
  - Hides browser address bar/tabs so the File Explorer presents as a native desktop application with full mouse/keyboard input acceleration.
- **Branding as BootOS File Explorer**:
  - Rebranded application titles in `src/bootos-menu.sh`, `src/explorer-launcher.sh`, and `src/explorer/index.html` to **BootOS File Explorer**.
- **Corrected Persistence Banner Indicator**:
  - Corrected line 57 in `src/bootos-menu.sh` to display:
    `Ephemeral DRAM (Run Option 11 to save)` instead of Option 10.
- **ISO Rebuild**:
  - Rebuilt and validated `bootos.iso` (429 MB, 100% RAM resident).
  - All Windows binaries signed with `CN=BootOS Developer`.
