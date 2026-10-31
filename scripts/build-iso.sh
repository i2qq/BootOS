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
echo "--> Installing kernel, 7zip, networking drivers, and runtime packages..."
chroot "${ROOTFS_DIR}" /bin/sh -c "
  apk update
  apk add --no-cache \
    linux-lts \
    linux-firmware-rtl_nic \
    linux-firmware-rtlwifi \
    kexec-tools \
    7zip \
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
    jq \
    dialog \
    ncurses \
    chromium \
    font-noto \
    font-dejavu \
    xorg-server \
    xinit \
    xf86-video-modesetting \
    xf86-video-vesa \
    xf86-video-fbdev \
    xf86-input-libinput \
    xf86-input-evdev \
    xf86-input-vmmouse \
    xf86-input-synaptics \
    openbox \
    dbus \
    eudev \
    eudev-hwids \
    xsetroot \
    adwaita-icon-theme \
    xprop \
    e2fsprogs \
    dosfstools \
    tar
"

# Copy kernel out to ISO boot folder
cp "${ROOTFS_DIR}/boot"/vmlinuz-lts "${ISO_ROOT}/boot/vmlinuz"

# Strip unneeded huge firmware (keep Intel/Realtek Ethernet & Wi-Fi)
echo "--> Optimizing firmware footprint to keep initramfs ultra-compact..."
mkdir -p /tmp/fw_keep
cp -r "${ROOTFS_DIR}/lib/firmware/intel" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/rtl_nic" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/rtlwifi" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/ath"* /tmp/fw_keep/ 2>/dev/null || true
rm -rf "${ROOTFS_DIR}/lib/firmware"/*
mv /tmp/fw_keep/* "${ROOTFS_DIR}/lib/firmware"/ 2>/dev/null || true
rm -rf /tmp/fw_keep "${ROOTFS_DIR}/var/cache/apk"/* "${ROOTFS_DIR}/boot/initramfs"*

# 4. Create robust udhcpc default.script so DHCP sets IP and DNS properly
mkdir -p "${ROOTFS_DIR}/usr/share/udhcpc"
cat <<'EOF' > "${ROOTFS_DIR}/usr/share/udhcpc/default.script"
#!/bin/sh
[ -z "$1" ] && exit 1

RESOLV_CONF="/etc/resolv.conf"

case "$1" in
    deconfig)
        ip addr flush dev "$interface" 2>/dev/null
        ;;
    renew|bound)
        ip addr replace "$ip/${mask:-24}" dev "$interface" 2>/dev/null || ip addr add "$ip/${mask:-24}" dev "$interface" 2>/dev/null
        if [ -n "$router" ]; then
            ip route replace default via "$router" dev "$interface" 2>/dev/null || ip route add default via "$router" dev "$interface" 2>/dev/null
        fi
        if [ -n "$dns" ]; then
            echo -n > "$RESOLV_CONF"
            for d in $dns; do
                echo "nameserver $d" >> "$RESOLV_CONF"
            done
        else
            echo "nameserver 1.1.1.1" > "$RESOLV_CONF"
            echo "nameserver 8.8.8.8" >> "$RESOLV_CONF"
        fi
        ;;
esac
exit 0
EOF
chmod +x "${ROOTFS_DIR}/usr/share/udhcpc/default.script"

# Install BootOS Startup Script, Browser Launcher, and Auto-Login
echo "--> Installing BootOS terminal interface and browser launcher..."
cp "${WORKSPACE_DIR}/src/bootos-menu.sh" "${ROOTFS_DIR}/usr/local/bin/bootos"
chmod +x "${ROOTFS_DIR}/usr/local/bin/bootos"
cp "${WORKSPACE_DIR}/src/browser-launcher.sh" "${ROOTFS_DIR}/usr/local/bin/browser"
chmod +x "${ROOTFS_DIR}/usr/local/bin/browser"
ln -sf /usr/local/bin/browser "${ROOTFS_DIR}/usr/local/bin/chromium-launch"
ln -sf /usr/local/bin/browser "${ROOTFS_DIR}/usr/local/bin/chromium-browser"
mkdir -p "${ROOTFS_DIR}/tmp/.X11-unix" "${ROOTFS_DIR}/var/log"
chmod 1777 "${ROOTFS_DIR}/tmp/.X11-unix"

# Configure inittab
cat <<'EOF' > "${ROOTFS_DIR}/etc/inittab"
::sysinit:/sbin/rc sysinit
::sysinit:/sbin/rc boot
::wait:/sbin/rc default

tty1::respawn:/usr/bin/setsid /bin/sh -c 'exec /usr/local/bin/bootos <> /dev/tty1 >&0 2>&1'
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/rc shutdown
EOF

cat <<'EOF' > "${ROOTFS_DIR}/etc/profile.d/bootos.sh"
if [ "$(tty)" = "/dev/tty1" ]; then
    /usr/local/bin/bootos
fi
EOF
chmod +x "${ROOTFS_DIR}/etc/profile.d/bootos.sh"

echo "bootos" > "${ROOTFS_DIR}/etc/hostname"

# 5. Create /init wrapper with hardware detection & module auto-loading
echo "--> Packing complete OS into RAM-resident initramfs..."
cat <<'EOF' > "${ROOTFS_DIR}/init"
#!/bin/sh
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /tmp
mount -t tmpfs none /run

# 1. Generate module dependencies
KERNEL_VER=$(uname -r)
depmod -a "$KERNEL_VER" 2>/dev/null || true

# 2. Start eudev daemon for dynamic device detection, hotplug, and Xorg input
mkdir -p /run/udev
if command -v udevd >/dev/null 2>&1; then
    udevd --daemon 2>/dev/null || true
    udevadm trigger --action=add 2>/dev/null || true
    udevadm settle --timeout=5 2>/dev/null || true
else
    echo /sbin/mdev > /proc/sys/kernel/hotplug 2>/dev/null || true
    mdev -s 2>/dev/null || true
fi

# 3. Explicitly probe core storage, loop & filesystem modules
for mod in loop isofs squashfs overlay ext4 vfat fat nls_cp437 nls_iso8859_1 nls_utf8; do
    modprobe $mod 2>/dev/null || true
done

# Ensure loop device nodes exist in /dev
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7; do
    [ -e "/dev/loop$i" ] || mknod "/dev/loop$i" b 7 "$i" 2>/dev/null || true
done

# 3b. Probe for and restore BootOS persistent storage if available
echo "Scanning storage devices for BootOS persistent state..."
PERSIST_DEV=""
for part in $(ls /dev/sd[a-z][0-9]* /dev/nvme[0-9]*n[0-9]*p[0-9]* /dev/vd[a-z][0-9]* /dev/xvd[a-z][0-9]* 2>/dev/null); do
    [ -b "$part" ] || continue
    mkdir -p /mnt/p_check
    if mount -o ro "$part" /mnt/p_check 2>/dev/null || \
       mount -t ext4 -o ro "$part" /mnt/p_check 2>/dev/null || \
       mount -t vfat -o ro "$part" /mnt/p_check 2>/dev/null; then
        pfile=""
        if [ -f "/mnt/p_check/bootos-persist.tgz" ]; then
            pfile="/mnt/p_check/bootos-persist.tgz"
        elif [ -f "/mnt/p_check/bootos/bootos-persist.tgz" ]; then
            pfile="/mnt/p_check/bootos/bootos-persist.tgz"
        fi

        if [ -n "$pfile" ]; then
            echo "--> Restoring persistent configuration from $part into DRAM..."
            tar -xzf "$pfile" -C / 2>/dev/null || true
            mkdir -p /etc
            echo "$part" > /etc/bootos_persist_dev
            PERSIST_DEV="$part"
            umount /mnt/p_check 2>/dev/null || true
            rm -rf /mnt/p_check
            break
        fi
        umount /mnt/p_check 2>/dev/null || true
    fi
    rm -rf /mnt/p_check
done
if [ -n "$PERSIST_DEV" ]; then
    echo "✓ Persistent data restored from $PERSIST_DEV"
fi

# 4a. Explicitly probe mouse, keyboard, and input devices (PS/2, USB, VirtualBox, VMware)
for mod in psmouse mousedev evdev i8042 usbhid hid_generic vmmouse joydev; do
    modprobe $mod 2>/dev/null || true
done

# 4b. Explicitly probe physical & virtual network drivers
for mod in e1000 e1000e igb igc virtio_net vmxnet3 r8169 r8152 cdc_ether ax88179_178a asix pcnet32 tg3 b44 forcedeth 8139too 8139cp atlantic sky2 alx hv_netvsc iwlwifi iwlmvm mt7921e mt7921u rtw88_8821ce rtw88_8822ce rtw89_8852ae rtw89_8852be; do
    modprobe $mod 2>/dev/null || true
done

# 4c. Explicitly probe graphics and display modules (VBox, Intel, AMD, generic DRM)
for mod in vboxvideo drm drm_kms_helper bochs_drm virtio_gpu fb_sys_fops syscopyarea sysfillrect sysimgblt; do
    modprobe $mod 2>/dev/null || true
done

mkdir -p /tmp/.X11-unix /var/log /run/user/0 /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix

# 5. Probe PCI modaliases for any additional hardware
find /sys -name modalias -exec cat {} + 2>/dev/null | xargs -n1 modprobe 2>/dev/null || true

# 6. Bring up loopback
ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null

# 7. Default DNS
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# 8. Auto-configure network interfaces via DHCP
for iface in $(ls /sys/class/net 2>/dev/null | grep -v '^lo$'); do
    ip link set "$iface" up 2>/dev/null
    udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -b -T 2 -t 5 2>/dev/null &
done

# Start BootOS with persistent loop & TTY
export TERM=linux
export HOME=/root
clear
while true; do
    if [ -c /dev/tty1 ]; then
        setsid /bin/sh -c 'exec /usr/local/bin/bootos' <> /dev/tty1 >&0 2>&1
    else
        setsid /bin/sh -c 'exec /usr/local/bin/bootos' <> /dev/console >&0 2>&1
    fi
    echo "BootOS finished. Restarting in 2 seconds..."
    sleep 2
done
EOF
chmod +x "${ROOTFS_DIR}/init"

# Run depmod inside rootfs before packing
chroot "${ROOTFS_DIR}" depmod -a 2>/dev/null || true

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
TIMEOUT 30
DEFAULT bootos

MENU TITLE BootOS - 100% DRAM Resident

LABEL bootos
  MENU LABEL ^1. Start BootOS (100% DRAM Mode - Fast Boot)
  LINUX /boot/vmlinuz
  INITRD /boot/initramfs.gz
  APPEND console=tty0 console=tty1 init=/init

LABEL bootos_quiet
  MENU LABEL ^2. Start BootOS (Quiet Mode)
  LINUX /boot/vmlinuz
  INITRD /boot/initramfs.gz
  APPEND quiet console=tty0 console=tty1 init=/init
EOF

# 7. Configure GRUB (UEFI Boot)
echo "--> Setting up GRUB for UEFI boot..."
cat <<'EOF' > "${ISO_ROOT}/boot/grub/grub.cfg"
set default="0"
set timeout=3

menuentry "BootOS (100% DRAM Mode)" {
    linux /boot/vmlinuz console=tty0 console=tty1 init=/init
    initrd /boot/initramfs.gz
}

menuentry "BootOS (Quiet Mode)" {
    linux /boot/vmlinuz quiet console=tty0 console=tty1 init=/init
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

# Also sync to C:/Users/Victor/ISO/Other/bootos.iso if the directory exists
TARGET_VM_DIR="/mnt/c/Users/Victor/ISO/Other"
if [ -d "${TARGET_VM_DIR}" ]; then
    echo "--> Syncing to ${TARGET_VM_DIR}/bootos.iso for VirtualBox..."
    cp "${OUTPUT_ISO}" "${TARGET_VM_DIR}/bootos.iso"
fi
