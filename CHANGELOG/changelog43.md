# Changelog 43: Fix TTY1 Console Attachment (Removed `openvt` Conflict)

### 1. Root Cause & Problem
- In Changelog 42, adding the `kbd` package provided `/usr/bin/openvt`.
- At boot, `/init` checked `if command -v openvt`, which evaluated to true, and invoked `openvt -c 1 -s -w -- /usr/local/bin/bootos`.
- Because VT 1 is already allocated and in use by the kernel as the primary video console, `openvt` aborted with the fatal error:
  `openvt: vt 1 is in use; command aborted; use 'openvt -f' to force.`
- This prevented the BootOS interactive terminal menu from launching.

### 2. Fix & Verification
- Removed `openvt` invocations from `/init`.
- Restored direct controlling terminal attachment via `setsid -c -w /usr/local/bin/bootos < /dev/tty1 > /dev/tty1 2>&1`.
- Retained full `kbd_mode -a -C /dev/tty1` and `stty sane` terminal discipline recovery for seamless GUI and text console transitions.
