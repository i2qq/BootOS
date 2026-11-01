# Changelog 39: Eliminate Discrete GPU/Audio Timeouts and Fix Terminal Session Initialization in /init

### 1. Eliminated Discrete GPU Firmware Timeouts
- Discovered physical Dell OptiPlex 990 possesses an ATI/AMD Radeon discrete PCIe card (`0000:01:00.0` / `0000:01:00.1`).
- Removed `radeon`, `amdgpu`, and `nouveau` kernel module probing from `/init`.
- Because firmware blobs for discrete cards are intentionally omitted to keep the image under 600 MB, probing these modules triggered the kernel's 60-second fallback firmware request timeout.
- The standard kernel framebuffer (`efifb`/`vesafb`) provides instant, zero-firmware display support on all monitors.

### 2. Audio & RAPL Subsystem Deferral
- Removed `snd_hda_intel` and `snd_hda_codec_realtek` from early init.
- Prevented Azalia audio codec handshake and SKU detection delays (`ALC269VB: SKU not ready`) from delaying terminal startup.

### 3. Clean Controlling Terminal Attachment (TTY1)
- Replaced `< /dev/tty0 > /dev/tty0 2>&1` with `setsid /bin/sh -c 'exec /usr/local/bin/bootos <> /dev/tty1 >&0 2>&1'`.
- `/dev/tty0` acts as a multiplexer and cannot serve as an interactive controlling terminal (`ctty`), whereas `/dev/tty1` correctly receives keyboard keystrokes from the active console.

### 4. Background Device & Storage Probing
- Replaced heavy `udevd` daemon and `udevadm trigger` with lightweight BusyBox `mdev -s`, preventing device lock contention with disk drivers.
- Filtered out optical CD/DVD drives (`/dev/sr*`) during persistence partition scans to avoid spin-up timeouts.
- Set `echo 1 > /proc/sys/kernel/printk` to eliminate asynchronous kernel dmesg interleaving over user UI.
- Removed destructive `noapic` / `acpi=noirq` parameters from bootloader options, using clean `nomodeset` and `vga=normal` for legacy compatibility.
