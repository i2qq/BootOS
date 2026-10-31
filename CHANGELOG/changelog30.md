# Changelog 30 - Fix kexec Kernel Locking, Windows 11 Native Desktop Explorer, Python AI Libraries, and Flasher Antivirus Hardening

## Overview
Comprehensive resolution of three core issues reported by the user:
1. **kexec_load "Operation not permitted" Resolution**:
   - Fixed the bootloader kernel command line parameter ordering bug in both `isolinux.cfg` (Legacy BIOS) and `grub.cfg` (UEFI).
   - Removed the malformed `lockdown=none` parameter which was aborting early kernel parameter parsing.
   - Positioned `kexec_load_disabled=0` as the very first kernel option before `console=` and `init=/init` so the Alpine Linux LTS kernel's `__setup("kexec_load_disabled=", kexec_load_disabled_setup)` handler executes properly at early boot, unlocking `sys_kexec_load` into DRAM.
2. **Native Desktop File Explorer App (Windows 11 Dark Mode)**:
   - Fixed the `_tkinter.TclError` syntax bug in `src/bootos_explorer.py` (`geometry("1100, 680")` -> `geometry("1100x680")`).
   - Replaced web-based placeholder with a pure native desktop Tkinter application styled after Windows 11 Mica dark mode with multi-tab browsing, live drive meters, breadcrumbs, search, cut/copy/paste, and file operations.
   - Enhanced `src/explorer-launcher.sh` with full udev daemon initialization, coldplug event triggering, input driver probing (`vmmouse`, `evdev`, `psmouse`), and Xorg session binding.
3. **Pre-Installed Python 3 Libraries**:
   - Packaged Python 3 along with user-requested libraries: `Pillow`, `FastAPI`, `Gradio`, `Rich`, and built-in `abc`, alongside `uvicorn`, `starlette`, and `pydantic`.
   - Included `font-noto-emoji` for proper rendering of system icons and file indicators.
4. **Windows Defender Antivirus Hardening for USB Flasher**:
   - Replaced all insecure C-runtime `system(...)` shell calls with direct Win32 `CreateProcessA` and `ShellExecuteA` invocations to eliminate heuristic trojan detections ("executes commands from an attacker").
   - Added an embedded Windows Application Manifest (`src/bootos-flasher.manifest`) declaring Windows 10/11 compatibility and proper privilege levels.
   - Added Version Info resource table (`src/bootos-flasher.rc`) with legitimate Product and Company metadata.
   - Digitally re-signed all executables (`bootos-flasher-gui.exe`, `bootos-flasher-cli.exe`, `bootos-flasher.exe`, `bootos.exe`) with the user's `CN=BootOS Developer` code signing certificate (`F3F4A8E3978B6F5E7FB2A44178A1A3111F728EF0`).
