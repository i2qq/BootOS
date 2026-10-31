# Changelog 35 - Direct ANSI Screen Clearing and Terminfo-Independent Clean Render Loop

## Overview
1. **Direct ANSI Sequence Screen Clearing**:
   - Replaced dependency on external `clear` binary with direct ANSI escape codes (`printf "\033[2J\033[1;1H"`).
   - Eliminated the `'linux': unknown terminal type` error that previously caused `clear` to fail silently and scroll duplicate menus onto the screen.

2. **Universal `/usr/local/bin/clear` Wrapper**:
   - Installed `/usr/local/bin/clear` and `/usr/bin/clear` wrappers sending standard ANSI reset escapes, guaranteeing that any interactive command or script requesting a screen refresh works reliably without external terminfo databases.
