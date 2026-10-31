# Changelog 12: Persistent Disk Storage & Auto-Save on System Reboot

## Summary of Changes
- **Option `[10]` - Save Persistent State to Storage Drive**:
  - Added dedicated option `[10]` in the BootOS Main Menu: `Save Persistent State to Storage Drive`.
  - Enables user to select any partition (or initialize an unpartitioned storage drive) to persist modifications, user configurations, `/root` directory, browser bookmarks/history (`/root/.config/chromium`), and system network settings across reboots.
  - Automatically records the active persistence partition in `/etc/bootos_persist_dev` and generates `/bootos-persist.tgz` with sync and clean unmount.
- **Option `[11]` - Auto-Save on System Reboot**:
  - Updated Reboot option `[11]` to `Reboot System (Auto-Saves to Disk)`.
  - Selecting `[11]` automatically triggers `save_persistent_state "auto"`. If a persistence partition is active, it seamlessly updates the on-disk state without interrupting the user and reboots. If no persistence drive is configured yet, it prompts the user before restarting.
- **Bootloader Auto-Restoration in `/init`**:
  - Updated `/init` in [`scripts/build-iso.sh`](file:///c:/Users/Victor/Antigravity%20Projects/Other/OSs/BootOS/scripts/build-iso.sh) to probe filesystem drivers (`ext4`, `vfat`, `fat`, `nls_*`) and scan all connected block devices (`/dev/sd*`, `/dev/nvme*`, `/dev/vd*`) on boot.
  - Automatically restores `bootos-persist.tgz` directly into the DRAM root filesystem if found, marking `Persist: Active (<device>)` in the header banner.
- **Packages & Utilities Added**:
  - Installed `e2fsprogs`, `dosfstools`, and `tar` into the Alpine root filesystem for complete ext4/FAT filesystem creation and archive management.
  - ISO size remains compact at **414 MB** (well under the 1 GB USB limit).
- **Verification via VDE-VLM in VirtualBox**:
  - Booted BootOS into RAM in `vmbootos1.7`.
  - Formatted and configured persistence on `/dev/sda1` using Option `[10]`.
  - Created test file `/root/persistent_proof.txt`.
  - Rebooted using Option `[11]` (Auto-Saves to Disk).
  - Verified on reboot that `/init` restored the archive into DRAM and `/root/persistent_proof.txt` was fully preserved.
