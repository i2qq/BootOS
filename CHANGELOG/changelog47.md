# Changelog 47: Fix Mouse Motion Freeze by Restoring Pointer Mapping and Enabling Full udev/mousedev

### 1. Root Cause of Mouse Freeze
- When `xmodmap` modified the X11 keyboard modifiers in `.xinitrc`, the X server reset the core pointer mapping, disabling mouse movement and clicks.
- In addition, `mousedev` and `uinput` were missing from the boot initramfs driver probe loop, and `udevd` daemon was not guaranteed to start if `/sbin` was omitted from PATH in GUI launchers.

### 2. Mouse Pointer Restoration & Xorg Input Hardening
- **Pointer Restoration**: Added `pointer = default` to `/root/.Xmodmap` and executed `xmodmap -e "pointer = default"` in all desktop launchers (`explorer-launcher.sh`, `browser-launcher.sh`, `partition-manager-launcher.sh`) immediately following key mapping to guarantee mouse movement and buttons remain 100% active.
- **Safe Layout Switching**: Switched to `setxkbmap -layout "gb,us"` for native UK/US layout switching, which does not tamper with mouse pointer devices.
- **Dedicated Xorg Class Rules**: Created `/etc/X11/xorg.conf.d/50-mouse.conf` and `00-keyboard.conf` with both `libinput` and `evdev` fallbacks.
- **Driver & Daemon Coverage**:
  - Added `mousedev` and `uinput` to early boot probing in `/init` and desktop launchers.
  - Added explicit `/sbin/udevd` invocation and `mdev -s` coldplug sync.
  - Exported standard complete `PATH` across `/init`, `bootos-menu.sh`, and all desktop launchers.
