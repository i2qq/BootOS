# Changelog 40: Load Modular USB Host Controllers (EHCI/UHCI/OHCI/XHCI) and Fix Controlling Terminal Input

### 1. Root Cause: Dormant USB Host Controller Hardware
- On physical PCs (such as Dell OptiPlex 990 / 390 / 330), the motherboard's Intel 6-series USB controllers run under kernel modules (`ehci-pci`, `ehci-hcd`, `uhci-hcd`, and modern `xhci-pci`).
- These modules were not loaded in `/init`, leaving the physical USB host hardware uninitialized.
- Because the USB controllers were unpowered/uninitialized, connected USB keyboards never received power or HID enumeration, causing NumLock, CapsLock, and all keystrokes to remain completely dead.

### 2. Probed Modular USB Controllers & Input Stack
- Explicitly probe USB core and host controller drivers in `/init`:
  - `usbcore`
  - `xhci-pci`, `xhci-hcd` (USB 3.0 / 3.1 / 3.2 on modern boards)
  - `ehci-pci`, `ehci-hcd` (USB 2.0 on OptiPlex and vintage systems)
  - `uhci-hcd`, `ohci-pci`, `ohci-hcd` (USB 1.1 companion controllers)
- Probed input drivers:
  - `hid`, `hid-generic`, `usbhid`, `evdev`, `i8042`, `atkbd`, `psmouse`
- Ran `mdev -s` immediately after USB controller initialization to generate all `/dev/input/*` device nodes.

### 3. Controlling Terminal & Keystroke Echo
- Replaced detached `setsid` command with `openvt -c 1 -s -w` and `setsid -c -w`.
- Added `stty -F /dev/tty1 sane echo icanon` and `stty sane echo icanon` in `bootos-menu.sh` to ensure typed characters immediately echo and pass cleanly to the shell's `read -r choice`.
