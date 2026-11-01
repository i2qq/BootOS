# Changelog 46: Install xmodmap/setxkbmap and Full UK Keyboard Scancode Remapping for Backslash and Pipe

### 1. Fix Missing Keyboard Packages in ISO Rootfs
- Added `xmodmap`, `setxkbmap`, and `kbd-bkeymaps` to `apk add` in `scripts/build-iso.sh`. Previously, `xmodmap` was called in launcher scripts but failed silently because the binary was missing from the Alpine image.
- Generated default `/root/.Xmodmap` and `/etc/X11/Xmodmap` with mappings for keycode 94 (`backslash bar backslash bar bar brokenbar`) and keysym grave (`bar asciitilde bar asciitilde`).

### 2. Physical UK Keyboard Scancode Remapping (Keycode 86 Console / 94 X11)
- On ISO UK keyboards (105-key layout), the physical key between Left Shift and Z is scancode `KEY_102ND` (Linux console keycode 86, X11 keycode 94). In default US layout, this key typed `>` unshifted and `<` shifted, preventing users from typing `\` or `|`.
- In `scripts/build-iso.sh` (`/init`), `src/bootos-menu.sh`, and `src/explorer-launcher.sh`, `src/browser-launcher.sh`, and `src/partition-manager-launcher.sh`:
  - Remapped Linux console keycode 86 to `backslash bar` via `loadkeys`.
  - Remapped X11 keycode 94 to `backslash bar backslash bar bar brokenbar` via `xmodmap`.
  - Remapped keycode 41 (console) and keysym grave (X11) to `bar asciitilde` so pressing `` ` `` types `|`.

### 3. Smart Terminal Pipeline Auto-Correction
- In `bootos_explorer.py`, updated `run_cmd` to auto-correct accidental `>` or `<` typed in place of pipe when piping to shell interpreters (e.g. `wget -qO- https://... > sudo bash` or `< sudo bash` automatically converts to `| sudo bash`).
