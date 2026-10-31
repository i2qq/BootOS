# Changelog 3: Hardware Network Driver Auto-Loading & DHCP Resolution

- **Network Driver Auto-Loading**:
  - Added PCI modalias coldplug scanner (`mdev -s` and `/sys/bus/pci/.../modalias`) on initial RAM disk boot.
  - Added explicit kernel module probing for virtualization and physical network chips:
    - Intel PRO/1000 (`e1000`, `e1000e`, `igb`)
    - VirtIO (`virtio_net`)
    - VMware (`vmxnet3`)
    - Realtek (`r8169`, `8139too`, `8139cp`)
    - AMD PCnet (`pcnet32`)
    - Broadcom & others (`tg3`, `b44`, `forcedeth`)
- **DHCP & DNS Auto-Configuration**:
  - Implemented `/usr/share/udhcpc/default.script` to apply DHCP IP addresses, gateway routes, and nameservers.
  - Added fallback DNS (`1.1.1.1`, `8.8.8.8`) into `/etc/resolv.conf`.
  - Added background auto-DHCP negotiation at boot time so network is pre-connected before the terminal menu renders.
- **Menu Alignment & Fixes**:
  - Fixed typo in banner referencing option number.
  - Numbered options sequentially from 1 to 10 with aliases for quick access (e.g. `1` or `gh` for GitHub, `5` or `net` for Network).
