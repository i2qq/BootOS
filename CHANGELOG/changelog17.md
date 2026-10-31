# Changelog 17: Legacy BIOS MBR Support & Old PC Booting Optimization

## Summary of Changes
- **Legacy BIOS MBR Optimization for Old PCs (Windows 7 Era)**:
  - Addressed why older Windows 7-era hardware ignores standard file-copy USBs:
    - Legacy BIOS motherboards do not read `.EFI` files or modern GPT partitions; they strictly execute the **446-byte Master Boot Record (MBR)** at physical Sector 0 and require an **Active boot flag (`0x80`)**.
  - **Flasher GUI Updates (`bootos-flasher-gui.exe` / `bootos-flasher.exe` / `bootos.exe`)**:
    - Re-ordered the primary action button to **`⚡ Flash USB (Legacy BIOS + UEFI)`**: writes the full `isohdpfx.bin` Syslinux hybrid MBR, partition table, and active `0x80` boot flag to the USB physical drive.
    - Guaranteed to boot on older Legacy BIOS PCs (e.g. Windows 7 laptops and desktops) while simultaneously retaining modern UEFI El Torito boot capability.
    - Added an old-PC boot guide alert upon completion detailing the necessary Boot Menu keys (**F12**, **F9**, **Esc**, **F8**) required to override Windows 7 from booting automatically off the internal drive.
