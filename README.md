<<<<<<< HEAD
# BootOS
=======
# BootOS - 100% RAM-Resident OS Downloader & Bootloader

**BootOS** is an ultra-compact (~150MB), terminal-style operating system designed to run **100% in DRAM**. Once booted, it frees up your USB drive completely and lets you download and boot directly into another operating system (such as **Lubuntu**, **Ubuntu**, **Debian**, or custom Linux distributions) using `kexec` or by flashing to an internal hard drive.

---

## 🌟 Key Features

- **Ultra Compact**: Under **200 MB** total ISO size (fits easily on any **2 GB USB drive** or smaller).
- **100% Loaded into DRAM**: The entire Linux root filesystem is loaded into RAM upon boot. The USB stick is immediately freed and can be safely unplugged!
- **Dual Boot Support**: Fully bootable on **Legacy BIOS** (old PCs) and modern **UEFI** systems.
- **Direct OS Booting (`kexec`)**: Uses the Linux `kexec` subsystem to jump directly from BootOS into a newly downloaded OS without restarting the PC hardware or BIOS.
- **Curated OS Library**:
  - **Lubuntu** (Super-lightweight desktop, ideal for old PCs with limited RAM/CPU)
  - **Ubuntu 24.04 LTS** (Desktop or Server)
  - **Debian 12 Bookworm** (Netboot installer)
  - **Custom OS URL** (Enter any kernel + initrd direct link)
  - **Netboot.xyz / iPXE** (Chain-loads hundreds of OS installers on-demand)
- **Drive Installer**: Direct disk flashing utility to stream an ISO straight to an internal hard drive or SSD (`/dev/sda`).

---

## 🚀 How to Flash `bootos.iso` to Your 2GB USB Drive (Windows)

You can flash `bootos.iso` onto your 2GB USB flash drive using any standard USB burning tool on Windows:

### Method 1: Using Rufus (Recommended for Old PCs)
1. Download [Rufus](https://rufus.ie) (portable version is fine).
2. Insert your 2GB USB drive.
3. In Rufus:
   - **Device**: Select your 2GB USB flash drive.
   - **Boot selection**: Click **SELECT** and choose `bootos.iso`.
   - **Partition scheme**: Choose **MBR** (for maximum compatibility with old PCs).
   - **Target system**: **BIOS (or UEFI-CSM)**.
4. Click **START**. (If prompted for ISO mode vs DD mode, ISO mode is default, but both work).

### Method 2: Using BalenaEtcher
1. Open [BalenaEtcher](https://etcher.balena.io/).
2. Click **Flash from file** and select `bootos.iso`.
3. Select your 2GB USB drive.
4. Click **Flash!**.

### Method 3: Using Ventoy
If your USB already has [Ventoy](https://www.ventoy.net/) installed, simply copy `bootos.iso` directly onto the USB drive.

---

## 🖥️ Booting Your Old PC

1. Insert the prepared USB drive into your old PC.
2. Turn on the PC and tap the boot menu key:
   - **F12** (Dell, Lenovo)
   - **F9** or **Esc** (HP)
   - **F11** or **F8** (ASUS, MSI, ASRock)
3. Select your USB drive from the boot device list.
4. Within 2-3 seconds, BootOS loads entirely into memory and presents the interactive terminal menu:

```text
  ____              _    ___  ____  
 | __ )  ___   ___ | |_ / _ \/ ___| 
 |  _ \ / _ \ / _ \| __| | | \___ \ 
 | |_) | (_) | (_) | |_| |_| |___) |
 |____/ \___/ \___/ \__|\___/|____/ 
 
 BootOS - 100% RAM-Resident OS Downloader & Bootloader
 Running entirely from DRAM. USB can be safely removed!
 ------------------------------------------------------------
 Memory : 3912 MB total, 3650 MB free
 Network: Connected (192.168.1.150)
 ------------------------------------------------------------
 Main Menu:
  [1] Download & Boot Lubuntu (Fast / Best for Old PCs)
  [2] Download & Boot Ubuntu 24.04 LTS
  [3] Download & Boot Custom Kernel/Initrd
  [4] Flash Downloaded ISO to Internal Hard Drive / SSD
  [5] Setup Network (Ethernet DHCP / Diagnostics)
  [6] Launch iPXE / Netboot.xyz (Hundreds of OSs on-demand)
  [7] Open Root Terminal Shell
  [8] Reboot System
  [9] Power Off

 Please select an option [1-9]:
```

---

## ⚙️ How It Boots into Another OS (`kexec`)

Traditional OS installers require rebooting the computer and changing BIOS settings. BootOS includes `kexec-tools`:
1. When you select an option (e.g., Lubuntu or Ubuntu Netboot), BootOS downloads the Linux kernel (`vmlinuz`) and initial RAM disk (`initrd.gz`) over the network into DRAM.
2. It calls:
   ```sh
   kexec -l /tmp/vmlinuz --initrd=/tmp/initrd.gz --command-line="boot=casper toram"
   kexec -e
   ```
3. The running BootOS kernel seamlessly hands control over to the newly downloaded OS in RAM without touching the BIOS!

---

## 🛠️ Rebuilding `bootos.iso`

If you ever wish to modify `src/bootos-menu.sh` and recompile the ISO:
- Right-click `build.ps1` in Windows PowerShell and run:
  ```powershell
  .\build.ps1
  ```
The script will assemble the updated kernel, initramfs, bootloaders, and output a fresh `bootos.iso`.
>>>>>>> e32a815 ([changelog1] Initial release of BootOS (100% RAM-Resident OS Downloader))
