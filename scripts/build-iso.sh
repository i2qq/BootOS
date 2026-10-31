#!/bin/bash
set -e

echo "=== Building BootOS Live ISO (RAM-Resident) ==="

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="/tmp/bootos-build"
ISO_ROOT="${BUILD_DIR}/iso"
ROOTFS_DIR="${BUILD_DIR}/rootfs"
OUTPUT_ISO="${WORKSPACE_DIR}/bootos.iso"

# Clean up any previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${ISO_ROOT}/boot/grub"
mkdir -p "${ISO_ROOT}/isolinux"
mkdir -p "${ROOTFS_DIR}"

# 1. Fetch Alpine Minirootfs for a lightweight base (< 10 MB)
ALPINE_VERSION="3.20"
ALPINE_RELEASE="3.20.3"
MINIROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/x86_64/alpine-minirootfs-${ALPINE_RELEASE}-x86_64.tar.gz"

echo "--> Downloading Alpine minirootfs..."
curl -sSL "${MINIROOTFS_URL}" -o "${BUILD_DIR}/minirootfs.tar.gz"
tar -xzf "${BUILD_DIR}/minirootfs.tar.gz" -C "${ROOTFS_DIR}"

# 2. Configure DNS & Repositories inside RootFS
echo "nameserver 1.1.1.1" > "${ROOTFS_DIR}/etc/resolv.conf"
cat <<EOF > "${ROOTFS_DIR}/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community
EOF

# 3. Chroot and install essential tools & Linux Kernel
echo "--> Installing kernel and runtime packages inside rootfs..."
chroot "${ROOTFS_DIR}" /bin/sh -c "
  apk update
  apk add --no-cache \
    linux-lts \
    kexec-tools \
    curl \
    wget \
    busybox-extras \
    iproute2 \
    util-linux \
    parted \
    pciutils \
    usbutils \
    wpa_supplicant \
    ca-certificates \
    dialog \
    ncurses
"

# Copy kernel out to ISO boot folder
cp "${ROOTFS_DIR}/boot"/vmlinuz-lts "${ISO_ROOT}/boot/vmlinuz"

# Strip giant graphics/telecom firmware to keep BootOS under ~100MB while keeping ethernet & Wi-Fi
echo "--> Optimizing firmware footprint..."
rm -rf "${ROOTFS_DIR}/lib/firmware/amdgpu" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/radeon" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/nvidia" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/mellanox" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/netronome" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/qcom" 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware/liquidio" 2>/dev/null || true

# 4. Install BootOS Startup Script and Auto-Login
echo "--> Installing BootOS terminal interface and auto-login configuration..."
cp "${WORKSPACE_DIR}/src/bootos-menu.sh" "${ROOTFS_DIR}/usr/local/bin/bootos"
chmod +x "${ROOTFS_DIR}/usr/local/bin/bootos"

# Configure inittab
cat <<'EOF' > "${ROOTFS_DIR}/etc/inittab"
::sysinit:/sbin/rc sysinit
::sysinit:/sbin/rc boot
::wait:/sbin/rc default

# BootOS auto-launch on console / tty1
tty1::respawn:/usr/local/bin/bootos
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/rc shutdown
EOF

# Auto-launch profile
cat <<'EOF' > "${ROOTFS_DIR}/etc/profile.d/bootos.sh"
if [ "$(tty)" = "/dev/tty1" ]; then
    /usr/local/bin/bootos
fi
EOF
chmod +x "${ROOTFS_DIR}/etc/profile.d/bootos.sh"

# Hostname
echo "bootos" > "${ROOTFS_DIR}/etc/hostname"

# Loopback & Ethernet DHCP
mkdir -p "${ROOTFS_DIR}/etc/network"
cat <<'EOF' > "${ROOTFS_DIR}/etc/network/interfaces"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# 5. Create /init wrapper and pack rootfs into DRAM-resident initramfs
echo "--> Packing complete OS into RAM-resident initramfs..."
cat <<'EOF' > "${ROOTFS_DIR}/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /tmp
mount -t tmpfs none /run

# Bring up loopback
ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null

# Clean console and start BootOS
clear
exec /usr/local/bin/bootos
EOF
chmod +x "${ROOTFS_DIR}/init"

# Pack initramfs using cpio
(cd "${ROOTFS_DIR}" && find . -print0 | cpio --null -H newc -o | gzip -9) > "${ISO_ROOT}/boot/initramfs.gz"

echo "Initramfs created. Size: $(du -h "${ISO_ROOT}/boot/initramfs.gz" | cut -f1)"

# 6. Configure ISOLINUX (Legacy BIOS for Old PCs)
echo "--> Setting up ISOLINUX for Legacy BIOS boot..."
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_ROOT}/isolinux/" 2>/dev/null || cp /usr/lib/syslinux/isolinux.bin "${ISO_ROOT}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/menu.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/libutil.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true

cat <<'EOF' > "${ISO_ROOT}/isolinux/isolinux.cfg"
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT bootos

MENU TITLE BootOS - 100% DRAM Resident

LABEL bootos
  MENU LABEL ^1. Start BootOS (100% DRAM Mode - Safe for 2GB USB)
  LINUX /boot/vmlinuz
  INITRD /boot/initramfs.gz
  APPEND quiet console=tty1 init=/init

LABEL bootos_debug
  MENU LABEL ^2. Start BootOS (Verbose Debug Mode)
  LINUX /boot/vmlinuz
  INITRD /boot/initramfs.gz
  APPEND console=tty1 init=/init
EOF

# 7. Configure GRUB (UEFI Boot)
echo "--> Setting up GRUB for UEFI boot..."
cat <<'EOF' > "${ISO_ROOT}/boot/grub/grub.cfg"
set default="0"
set timeout=5

menuentry "BootOS (100% DRAM Mode)" {
    linux /boot/vmlinuz quiet console=tty1 init=/init
    initrd /boot/initramfs.gz
}

menuentry "BootOS (Verbose Mode)" {
    linux /boot/vmlinuz console=tty1 init=/init
    initrd /boot/initramfs.gz
}
EOF

# 32MB FAT EFI partition image
dd if=/dev/zero of="${ISO_ROOT}/boot/grub/efi.img" bs=1M count=32
mkfs.vfat "${ISO_ROOT}/boot/grub/efi.img"
mkdir -p /tmp/efi_mount
mount -o loop "${ISO_ROOT}/boot/grub/efi.img" /tmp/efi_mount
mkdir -p /tmp/efi_mount/EFI/BOOT
grub-mkstandalone -d /usr/lib/grub/x86_64-efi/ -O x86_64-efi --modules="part_gpt part_msdos fat iso9660" -o /tmp/efi_mount/EFI/BOOT/BOOTX64.EFI "boot/grub/grub.cfg=${ISO_ROOT}/boot/grub/grub.cfg"
umount /tmp/efi_mount
rm -rf /tmp/efi_mount

# 8. Generate Hybrid ISO with xorriso
echo "--> Generating Hybrid ISO image..."
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "BOOTOS" \
    -eltorito-boot isolinux/isolinux.bin \
    -eltorito-catalog isolinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot -isohybrid-gpt-basdat \
    -output "${OUTPUT_ISO}" \
    "${ISO_ROOT}"

echo "=========================================================="
echo "✓ SUCCESS! BootOS ISO created successfully:"
ls -lh "${OUTPUT_ISO}"
echo "=========================================================="
