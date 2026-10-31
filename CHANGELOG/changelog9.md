# Changelog 9: Baked-in Chromium Web Browser with Lightweight Xorg/Openbox GUI

### Summary of Changes
1. **Baked-in Chromium Web Browser**:
   - Added `chromium`, `openbox`, `xorg-server`, `xinit`, `font-noto`, `font-dejavu`, and `dbus` to the BootOS image packages.
   - Enables browsing the web directly from the live bootable USB environment on any old PC or VM.

2. **Dedicated Lightweight Browser Launcher (`/usr/local/bin/browser`)**:
   - Created `src/browser-launcher.sh` which initializes Openbox in kiosk mode, configures DBus machine-id, and launches Chromium with container/root-safe flags (`--no-sandbox`, `--disable-gpu-sandbox`, `--disable-dev-shm-usage`, `--start-maximized`).
   - Symlinked `/usr/local/bin/browser`, `/usr/local/bin/chromium-launch`, and `/usr/local/bin/chromium-browser`.
   - Exiting the browser cleanly returns control back to the BootOS terminal menu.

3. **Integrated into BootOS Main Menu (Option 4)**:
   - Added Option `[4] Launch Chromium Web Browser (GUI)` directly to the BootOS Main Menu.
   - Supports opening custom URLs or default (`https://google.com`), and automatically prompts to bring up networking if disconnected.
   - Also directly callable from the Root Terminal Shell via `browser [url]` or `chromium`.

4. **Added Graphics Driver Probing**:
   - Added automatic modprobing for DRM, KMS, `vboxvideo`, `virtio_gpu`, and generic framebuffer drivers at boot time.
