# Changelog 38: Comprehensive Hardware Support for Dell OptiPlex (990, 390, 330), Vintage Laptops, and Modern NVMe Platforms

### 1. Dell OptiPlex 330, 390, and 990 Hardware Stack
- **Dell OptiPlex 330**:
  - Added Broadcom Tigon3 (`tg3`, `b44`) and `linux-firmware-tigon` / `linux-firmware-bnx2` for the BCM5754 Gigabit Ethernet NIC.
  - Added Intel ICH7 IDE/SATA storage drivers (`ata_piix`, `pata_acpi`, `ata_generic`, `ahci`).
  - Added Intel GMA 3100 graphics driver (`xf86-video-intel` and kernel `i915`).
- **Dell OptiPlex 390**:
  - Integrated Realtek RTL8111E-VL Gigabit NIC (`r8169`) and firmware `rtl_nic`.
  - Added Intel HD Graphics 2000 driver and SATA AHCI drivers.
- **Dell OptiPlex 990**:
  - Integrated Intel 82579LM Gigabit LAN (`e1000e`) and Intel HD Graphics 2000/3000 (`i915`).
  - Added Realtek ALC269 HD audio driver (`snd_hda_intel`, `snd_hda_codec_realtek`).

### 2. Vintage Laptops (No-Name Brands, 17"-19" Screens, SRS WOW DSP)
- **Networking**:
  - Added Marvell Yukon Gigabit Ethernet (`sky2`) commonly found on 17"-19" multimedia notebooks.
  - Added Atheros/Qualcomm Ethernet drivers (`alx`, `atl1`, `atl1c`, `atl1e`).
  - Added JMicron Ethernet driver (`jme`) and vintage Intel 10/100 (`e100`).
- **Audio & Media**:
  - Added `snd_hda_intel` and `snd_hda_codec_realtek` to properly initialize HD audio hardware paired with SRS WOW DSP without IRQ storms.
- **Display & Graphics**:
  - Added Xorg display drivers: `xf86-video-intel`, `xf86-video-ati`, `xf86-video-amdgpu`, `xf86-video-nouveau`, `xf86-video-vmware`, and `xf86-video-qxl`.
  - Added dedicated **Safe Graphics Mode (`nomodeset vga=791`)** to Syslinux and GRUB menus for non-standard widescreen panels (1440x900, 1680x1050) and older GPUs that fail early kernel KMS.
  - Added dedicated **Legacy Hardware Compatibility Mode (`nomodeset acpi=noirq noapic pci=nomsi vga=normal`)** for older BIOSes with buggy ACPI/IRQ tables.
- **Input & Peripherals**:
  - Added laptop PS/2 keyboard (`atkbd`, `i8042`) and touchpad (`psmouse`) drivers.
  - Added `usbcore.autosuspend=-1` to boot options to prevent USB keyboards and mice from dropping into sleep mode during boot.
  - Added SD card reader drivers (`sdhci`, `sdhci_pci`, `mmc_block`).

### 3. Modern Systems (2020-2026)
- Added NVMe storage stack (`nvme`, `nvme_core`) and USB 3.2 Attached SCSI (`uas`, `usb_storage`).
- Added Intel 2.5 GbE (`igc`), Realtek 2.5 GbE (`r8169`), and modern Realtek Wi-Fi (`rtw88`, `linux-firmware-rtw88`).
- Added USB tethering drivers (`cdc_ether`, `cdc_ncm`, `rndis_host`) for emergency network access via smartphone.
- Expanded disk enumeration fallback in `bootos-menu.sh` to include `/sys/block/hd*` and `/sys/block/mmcblk*`.
