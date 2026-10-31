# Changelog 7: Transfer to i2qq/BootOS, Remove Hardcoded Defaults & Fix BusyBox DD Flashing

### Summary of Changes
1. **Removed Hardcoded Repository Defaults**:
   - Replaced all hardcoded defaults (such as `VicRoger27/BootOS`) with clean user input prompts without forcing default repository targets.
   - Updated repository references and examples to shorthand account `i2qq/BootOS` (`https://github.com/i2qq/BootOS`).

2. **Fixed HTTP Redirect HTML Header Error During ISO Download**:
   - Resolved issue where GitHub release downloads traverse 301/302 redirects containing HTML wrapper headers.
   - Updated content-type inspection to check the final redirect hop (`tail -n1`) and automatically bypass header inspection for explicit `.iso`/`.img`/`.raw` release download assets.

3. **Fixed BusyBox `dd` Incompatible Flags**:
   - Replaced unsupported GNU flags `status=progress` and `conv=fdatasync` with standard BusyBox `conv=fsync`.
   - Enabled native `curl -#` progress bar for streaming direct image writes straight into target block devices (e.g. `/dev/sda`).

4. **Automated Storage Device Selection**:
   - Integrated `select_target_drive` to automatically scan, filter, and enumerate candidate hard disks/SSDs (`/dev/sda`, `/dev/nvme*`) while ignoring read-only optical drives (`/dev/sr0`).
