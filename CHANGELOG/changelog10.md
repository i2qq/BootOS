# Changelog 10: Fix Mouse Cursor Movement, Udev Device Auto-Discovery & Full Network Driver Support

### Summary of Changes

1. **Fixed Mouse Cursor & Pointer Input**:
   - **Integrated `eudev` Daemon**: Added `eudev` and `eudev-hwids` to BootOS and started `udevd` with `udevadm trigger` at boot. This allows `libinput` to dynamically discover mice, trackpads, and keyboards via netlink.
   - **Multi-Driver Input Stack**: Installed `xf86-input-libinput`, `xf86-input-evdev`, `xf86-input-vmmouse` (for seamless VirtualBox & VMware integration), and `xf86-input-synaptics`.
   - **Input Kernel Modules**: Added automatic modprobing for `psmouse`, `mousedev`, `evdev`, `i8042`, `usbhid`, `hid_generic`, and `vmmouse`.
   - **Configured Xorg Input Auto-Binding**: Added `/etc/X11/xorg.conf.d/10-input.conf` to automatically bind pointer devices with fallback to `evdev` and `vmmouse`.
   - **Rendered Cursor Theme**: Added `adwaita-icon-theme` and `xsetroot -cursor_name left_ptr` to ensure a crisp, visible pointer arrow.

2. **Full Ethernet & Physical Hardware Driver Support**:
   - **Realtek 2.5GbE Firmware**: Added `linux-firmware-rtl_nic` to package list and preserved `/lib/firmware/rtl_nic` so Realtek RTL8125/RTL8126 (found on modern motherboards like AMD Ryzen 9700X AM5 systems) loads firmware successfully.
   - **Modern NIC Drivers Probed**: Added driver probing for Intel 2.5G (`igc`), USB-C Ethernet adapters (`r8152`, `cdc_ether`, `ax88179_178a`, `asix`), Hyper-V (`hv_netvsc`), Aquantia (`atlantic`), Marvell (`sky2`), Qualcomm (`alx`), and Wi-Fi (`iwlwifi`, `mt7921e`, `rtw88`, `rtw89`).
   - **Carrier Negotiation Check**: Added a 3-second link carrier detection loop before running `udhcpc` to prevent DHCP requests from failing while PHY auto-negotiation is in progress.
   - **Multi-Tier Internet Verification**: Upgraded `check_internet` to test ICMP ping, HTTP connect (`curl`/`wget`), and DNS lookup (`nslookup`), preventing false "Disconnected" reports when network firewalls block ICMP ping.
   - **Network Diagnostics in Option 7**: Displays PCI hardware identification (`lspci -nn`), link carrier states, and IP assignments.

3. **Seamless Console Return**:
   - Added `chvt 1` after Xorg closes so the screen immediately switches back to the BootOS menu console upon closing Chromium or pressing Alt+F4.

4. **ISO Size Optimization**:
   - Total ISO footprint remains ultra-compact at **414 MB**, easily fitting onto any 2GB USB flash drive.
