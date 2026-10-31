# Changelog 34 - Carrier Link Settle, Console Printk Silencing, and Terminal Compatibility

## Overview
1. **Network Carrier Settle & Dynamic Probe**:
   - Resolved the race condition where fast boot environments render the menu before the physical/virtual network card finishes autonegotiation (e.g. `e1000: eth0 NIC Link is Up` at 19s vs menu start at 17s).
   - Added a 2-second settle loop in `/init` and an on-demand carrier check in `get_net_info` that acquires DHCP leases automatically without requiring manual network configuration.
   - Corrected menu network prompt to `(Run Option 8)`.

2. **Console Log Spam Silencing**:
   - Added `echo 1 > /proc/sys/kernel/printk` in `/init` to prevent asynchronous kernel messages (`clocksource: Long readout interval`, `e1000: eth0 NIC Link is Up`) from breaking the user prompt.

3. **Terminal Compatibility**:
   - Set `export TERM=vt100` and `TERMINFO_DIRS` to eliminate the `'linux': unknown terminal type` warnings during terminal clear operations.
