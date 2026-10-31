# Changelog 5: Fixed BootOS TTY Shell Handover, Dynamic Controlling Terminal, and Main Menu Input Parsing

### Highlights & Key Improvements
1. **Resolved Kernel Halt on Boot**:
   - Identified that `cttyhack` was missing in Alpine's minimal BusyBox compilation.
   - Refactored `/init` PID 1 startup logic to use dynamic controlling terminal handover (`setsid /bin/sh -c 'exec /usr/local/bin/bootos' <> /dev/tty1 >&0 2>&1`), falling back to `/dev/console`.
   - Wrapped the invocation in a persistent watchdog supervisor loop so PID 1 never exits or halts the kernel if a session ends.

2. **Fixed Main Menu Option Matching**:
   - Fixed a wildcard matching bug (`*`) in the menu parser case statement that was intercepting options 2 through 10 and routing them incorrectly.
   - Ensured clean routing for all 10 menu options.

3. **Interactive Root Shell (Option 8)**:
   - Configured fallback root shell with interactive flag and customized prompt `bootos:\w# ` for direct debugging.

4. **Footprint & Memory Optimization**:
   - Trimmed unnecessary firmware from the initramfs to reduce ISO size down to ~206 MB (well below the 1 GB constraint).
   - ISO completely loads into DRAM within seconds.
