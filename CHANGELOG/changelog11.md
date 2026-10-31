# Changelog 11: Return to Terminal Homescreen on Kill or Minus Buttons in Chromium

## Summary of Changes
- **Window Management & Event Handling**:
  - Configured Openbox (`rc.xml`) mouse context bindings for both `Close` (`[X]` kill button) and `Iconify` (`[-]` minus button) to execute `sh -c "pkill -f chromium 2>/dev/null || openbox --exit"`.
  - Added dedicated Openbox keybindings: `Alt+F4`, `Ctrl+Q`, `Alt+Minus`, and `Super+D` to reliably close the graphical session and return to the BootOS homescreen.
  - Implemented an active X11 window state monitor in `/root/.xinitrc` using `xprop` and a quoted heredoc:
    - Waits for the Chromium client window to map and become active.
    - Continuously tracks window minimization (`_NET_WM_STATE_HIDDEN` or loss of active window `_NET_ACTIVE_WINDOW == 0x0`).
    - When minimized via the CSD minus button or native titlebar, triggers an immediate graceful termination (`pkill -TERM -f chromium`) with fallback process kill.
- **Console TTY Restoration**:
  - Explicitly added `chvt 1` upon exit of `xinit` in [browser-launcher.sh](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/src/browser-launcher.sh) to ensure instantaneous return of the VirtualBox screen to the main BootOS terminal menu (VT1).
  - Updated BootOS menu tip text for Option `[4]` to inform the user that clicking either the kill (`[X]`) or minus (`[-]`) buttons will immediately return to the BootOS terminal homescreen.
- **Verification via VDE-VLM**:
  - Verified live in VirtualBox VM `vmbootos1.7`.
  - Booted BootOS into RAM (414 MB total ISO size).
  - Launched Chromium GUI to `https://google.com`.
  - Tested clicking the minus button `[-]` at `(1200, 15)`: immediately terminated Chromium and restored the BootOS menu on screen.
  - Tested clicking the kill button `[X]` at `(1265, 15)`: immediately terminated Chromium and restored the BootOS menu on screen.
