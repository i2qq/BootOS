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
    linux-firmware-rtw88 \
    linux-firmware-bnx2 \
    linux-firmware-tigon \
    linux-firmware-e100 \
    linux-firmware-ath9k_htc \
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
    xf86-video-intel \
    xf86-video-ati \
    xf86-video-amdgpu \
    xf86-video-nouveau \
    xf86-video-vmware \
    xf86-video-qxl \
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
    alsa-lib \
    tar \
    bash \
    bash-completion \
    sudo \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    nano \
    less \
    font-noto-emoji \
    python3 \
    python3-tkinter \
    py3-pip \
    py3-pillow \
    py3-rich \
    py3-pydantic \
    py3-starlette \
    py3-aiofiles \
    py3-anyio \
    py3-websockets
"

# Copy kernel out to ISO boot folder
cp "${ROOTFS_DIR}/boot"/vmlinuz-lts "${ISO_ROOT}/boot/vmlinuz"

# Strip unneeded huge firmware (keep Intel/Realtek/Broadcom/Atheros Ethernet & Wi-Fi)
echo "--> Optimizing firmware footprint to keep initramfs ultra-compact..."
mkdir -p /tmp/fw_keep
cp -r "${ROOTFS_DIR}/lib/firmware/intel" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/rtl_nic" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/rtlwifi" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/rtw88" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/ath"* /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/tigon" /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/bnx2"* /tmp/fw_keep/ 2>/dev/null || true
cp -r "${ROOTFS_DIR}/lib/firmware/e100" /tmp/fw_keep/ 2>/dev/null || true
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

# Install BootOS Native Desktop File Explorer
echo "--> Installing BootOS Native Desktop File Explorer..."
cp "${WORKSPACE_DIR}/src/bootos_explorer.py" "${ROOTFS_DIR}/usr/local/bin/bootos_explorer.py"
chmod +x "${ROOTFS_DIR}/usr/local/bin/bootos_explorer.py"
cp "${WORKSPACE_DIR}/src/explorer-launcher.sh" "${ROOTFS_DIR}/usr/local/bin/explorer"
chmod +x "${ROOTFS_DIR}/usr/local/bin/explorer"
ln -sf /usr/local/bin/explorer "${ROOTFS_DIR}/usr/local/bin/files"
ln -sf /usr/local/bin/explorer "${ROOTFS_DIR}/usr/bin/explorer"

# Pre-install Python 3 libraries: Pillow, FastAPI, Gradio, Rich, ABC
echo "--> Installing requested Python 3 libraries: Pillow, FastAPI, Gradio, Rich, ABC..."
mkdir -p "${ROOTFS_DIR}/proc" "${ROOTFS_DIR}/sys" "${ROOTFS_DIR}/dev"
mount -t proc none "${ROOTFS_DIR}/proc" 2>/dev/null || true
mount -t sysfs none "${ROOTFS_DIR}/sys" 2>/dev/null || true
mount --bind /dev "${ROOTFS_DIR}/dev" 2>/dev/null || true

chroot "${ROOTFS_DIR}" /bin/sh -c "
  pip install --no-cache-dir --break-system-packages fastapi gradio
"

umount -l "${ROOTFS_DIR}/proc" 2>/dev/null || true
umount -l "${ROOTFS_DIR}/sys" 2>/dev/null || true
umount -l "${ROOTFS_DIR}/dev" 2>/dev/null || true

mkdir -p "${ROOTFS_DIR}/tmp/.X11-unix" "${ROOTFS_DIR}/var/log"
chmod 1777 "${ROOTFS_DIR}/tmp/.X11-unix"

# Configure sudo (passwordless for root & wheel)
mkdir -p "${ROOTFS_DIR}/etc/sudoers.d"
cat <<'EOF' > "${ROOTFS_DIR}/etc/sudoers.d/wheel"
Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Defaults env_keep += "PATH"
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
root ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 440 "${ROOTFS_DIR}/etc/sudoers.d/wheel"
chmod 4755 "${ROOTFS_DIR}/usr/bin/sudo" 2>/dev/null || true

# Set root default shell to bash
sed -i 's|root:x:0:0:root:/root:/bin/sh|root:x:0:0:root:/root:/bin/bash|' "${ROOTFS_DIR}/etc/passwd" 2>/dev/null || true

# Create full-featured bashrc with prompt, aliases, and completion
mkdir -p "${ROOTFS_DIR}/root" "${ROOTFS_DIR}/etc/bash"
cat <<'EOF' > "${ROOTFS_DIR}/root/.bashrc"
# BootOS Full GNU Shell Configuration
export PS1='\[\033[1;36m\]bootos\[\033[0m\]:\[\033[1;32m\]\w\[\033[0m\]# '
export TERM=linux
export HISTSIZE=2000
export HISTFILESIZE=4000
export PAGER=less
export EDITOR=nano
alias ls='ls --color=auto'
alias ll='ls -la --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias menu='/usr/local/bin/bootos'
alias explorer='/usr/local/bin/explorer'
alias files='/usr/local/bin/explorer'

# Source bash completion if available
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion 2>/dev/null
EOF
cp "${ROOTFS_DIR}/root/.bashrc" "${ROOTFS_DIR}/etc/bash/bashrc"

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
if [ -z "$BOOTOS_SHELL" ] && [ "$(tty 2>/dev/null)" = "/dev/tty1" ]; then
    /usr/local/bin/bootos
fi
EOF
chmod +x "${ROOTFS_DIR}/etc/profile.d/bootos.sh"

echo "bootos" > "${ROOTFS_DIR}/etc/hostname"

# Configure sysctl to enable kexec loading
mkdir -p "${ROOTFS_DIR}/etc/sysctl.d"
echo "kernel.kexec_load_disabled = 0" >> "${ROOTFS_DIR}/etc/sysctl.conf" 2>/dev/null || true
echo "kernel.kexec_load_disabled = 0" > "${ROOTFS_DIR}/etc/sysctl.d/99-kexec.conf" 2>/dev/null || true

# Bulletproof reboot & poweroff wrappers
mkdir -p "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/usr/local/sbin"
cat <<'EOF' > "${ROOTFS_DIR}/usr/local/bin/reboot"
#!/bin/sh
sync
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
busybox reboot -f "$@" 2>/dev/null || reboot -f 2>/dev/null || echo b > /proc/sysrq-trigger
EOF
chmod +x "${ROOTFS_DIR}/usr/local/bin/reboot"
cp "${ROOTFS_DIR}/usr/local/bin/reboot" "${ROOTFS_DIR}/usr/local/sbin/reboot"

cat <<'EOF' > "${ROOTFS_DIR}/usr/local/bin/poweroff"
#!/bin/sh
sync
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
busybox poweroff -f "$@" 2>/dev/null || poweroff -f 2>/dev/null || echo o > /proc/sysrq-trigger
EOF
chmod +x "${ROOTFS_DIR}/usr/local/bin/poweroff"
cp "${ROOTFS_DIR}/usr/local/bin/poweroff" "${ROOTFS_DIR}/usr/local/sbin/poweroff"

ln -sf /usr/local/bin/poweroff "${ROOTFS_DIR}/usr/local/bin/shutdown"
ln -sf /usr/local/bin/poweroff "${ROOTFS_DIR}/usr/local/bin/halt"
ln -sf /usr/local/sbin/poweroff "${ROOTFS_DIR}/usr/local/sbin/shutdown"
ln -sf /usr/local/sbin/poweroff "${ROOTFS_DIR}/usr/local/sbin/halt"

# Universal terminal screen clear (zero terminfo dependency)
cat <<'EOF' > "${ROOTFS_DIR}/usr/local/bin/clear"
#!/bin/sh
printf "\033[2J\033[1;1H"
EOF
chmod +x "${ROOTFS_DIR}/usr/local/bin/clear"
cp "${ROOTFS_DIR}/usr/local/bin/clear" "${ROOTFS_DIR}/usr/bin/clear" 2>/dev/null || true

# 5. Create /init wrapper with hardware detection & module auto-loading
echo "--> Packing complete OS into RAM-resident initramfs..."
cat <<'EOF' > "${ROOTFS_DIR}/init"
#!/bin/sh
trap 'sync; echo 1 > /proc/sys/kernel/sysrq 2>/dev/null; busybox reboot -f 2>/dev/null || echo b > /proc/sysrq-trigger' TERM INT QUIT

mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs none /tmp
mount -t tmpfs none /run

# Suppress kernel printk spam onto console so user UI stays clean
echo 1 > /proc/sys/kernel/printk 2>/dev/null || true

# Enable kexec in Alpine kernel
echo 0 > /proc/sys/kernel/kexec_load_disabled 2>/dev/null || true

echo "--> [1/4] BootOS: Initializing kernel filesystems & devices..."
# Fast device population via mdev
echo /sbin/mdev > /proc/sys/kernel/hotplug 2>/dev/null || true
mdev -s 2>/dev/null || true

echo "--> [2/4] BootOS: Loading hardware drivers..."
# Essential Storage (NVMe, SATA AHCI, IDE, USB, Card Readers)
for mod in loop isofs squashfs overlay ext4 vfat fat nvme nvme_core ahci libahci ata_piix pata_acpi ata_generic sata_nv sata_sil sata_via sata_sis uas usb_storage mmc_block sdhci sdhci_pci; do
    modprobe $mod 2>/dev/null || true
done

# Essential Networking (Intel, Realtek, Broadcom, Marvell, Atheros, JMicron, USB dongles & tethering)
for mod in e1000 e1000e igb igc r8169 r8152 tg3 b44 sky2 alx atl1c atl1e atl1 jme e100 asix ax88179_178a cdc_ether cdc_ncm rndis_host; do
    modprobe $mod 2>/dev/null || true
done

# Essential Input (Keyboards, Mice, Touchpads)
for mod in i8042 atkbd psmouse evdev usbhid hid_generic hid_multitouch; do
    modprobe $mod 2>/dev/null || true
done

# Ensure loop device nodes exist in /dev
[ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
for i in 0 1 2 3 4 5 6 7; do
    [ -e "/dev/loop$i" ] || mknod "/dev/loop$i" b 7 "$i" 2>/dev/null || true
done

mkdir -p /tmp/.X11-unix /var/log /run/user/0 /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix

# Bring up loopback & DNS
ip link set lo up 2>/dev/null || ifconfig lo 127.0.0.1 up 2>/dev/null
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Background network auto-configuration
for iface in $(ls /sys/class/net 2>/dev/null | grep -v '^lo$'); do
    ip link set "$iface" up 2>/dev/null
    udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -b -T 2 -t 3 2>/dev/null &
done

echo "--> [3/4] BootOS: Checking persistent storage..."
PERSIST_DEV=""
for part in $(blkid -o device -t TYPE=vfat -t TYPE=ext4 2>/dev/null | grep -v '^/dev/sr'); do
    [ -b "$part" ] || continue
    mkdir -p /mnt/p_check
    if mount -o ro "$part" /mnt/p_check 2>/dev/null; then
        pfile=""
        if [ -f "/mnt/p_check/bootos-persist.tgz" ]; then
            pfile="/mnt/p_check/bootos-persist.tgz"
        elif [ -f "/mnt/p_check/bootos/bootos-persist.tgz" ]; then
            pfile="/mnt/p_check/bootos/bootos-persist.tgz"
        fi

        if [ -n "$pfile" ]; then
            echo "--> Restoring persistent configuration from $part..."
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

echo "--> [4/4] BootOS: Starting user interface..."
export TERM=vt100
export TERMINFO_DIRS=/usr/share/terminfo:/etc/terminfo:/lib/terminfo
export HOME=/root

# Direct attachment to active controlling terminal (TTY1)
while true; do
    if [ -c /dev/tty1 ]; then
        setsid /bin/sh -c 'exec /usr/local/bin/bootos <> /dev/tty1 >&0 2>&1'
    elif [ -c /dev/console ]; then
        setsid /bin/sh -c 'exec /usr/local/bin/bootos <> /dev/console >&0 2>&1'
    else
        /usr/local/bin/bootos
    fi
    sleep 1
done
EOF
# Sanitize all scripts to pure Unix LF line endings
find "${ROOTFS_DIR}/usr/local/bin" "${ROOTFS_DIR}/usr/local/sbin" "${ROOTFS_DIR}/etc" -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true
sed -i 's/\r$//' "${ROOTFS_DIR}/init" 2>/dev/null || true
chmod +x "${ROOTFS_DIR}/usr/local/bin/"* 2>/dev/null || true
chmod +x "${ROOTFS_DIR}/init"

# Run depmod inside rootfs before packing
chroot "${ROOTFS_DIR}" depmod -a 2>/dev/null || true

# Pack initramfs using cpio
(cd "${ROOTFS_DIR}" && find . -print0 | cpio --null -H newc -o | gzip -9) > "${ISO_ROOT}/boot/initramfs.gz"

echo "Initramfs created. Size: $(du -h "${ISO_ROOT}/boot/initramfs.gz" | cut -f1)"

# 6. Configure ISOLINUX (Legacy BIOS for Old PCs)
echo "--> Setting up ISOLINUX for Legacy BIOS boot..."
mkdir -p "${ISO_ROOT}/isolinux" "${ISO_ROOT}/syslinux" "${ISO_ROOT}/boot/syslinux"
cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_ROOT}/isolinux/" 2>/dev/null || cp /usr/lib/syslinux/isolinux.bin "${ISO_ROOT}/isolinux/"
cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/menu.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true
cp /usr/lib/syslinux/modules/bios/libutil.c32 "${ISO_ROOT}/isolinux/" 2>/dev/null || true

cat <<'EOF' > "${ISO_ROOT}/isolinux/isolinux.cfg"
DEFAULT bootos
PROMPT 0
TIMEOUT 50

UI menu.c32
MENU TITLE BootOS - Universal Deployment (100% DRAM Resident)

LABEL bootos
  MENU LABEL ^1. Start BootOS (Standard - Fast Boot)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.gz quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init

LABEL bootos_safe
  MENU LABEL ^2. Start BootOS (Safe Graphics - nomodeset)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.gz nomodeset vga=791 quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init

LABEL bootos_compat
  MENU LABEL ^3. Start BootOS (Legacy Hardware Compatibility Mode)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.gz nomodeset vga=normal quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init

LABEL bootos_debug
  MENU LABEL ^4. Start BootOS (Verbose Debug Mode)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.gz kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init
EOF

cp "${ISO_ROOT}/isolinux/isolinux.cfg" "${ISO_ROOT}/isolinux/syslinux.cfg"
cp "${ISO_ROOT}/isolinux/isolinux.cfg" "${ISO_ROOT}/syslinux/syslinux.cfg"
cp "${ISO_ROOT}/isolinux/isolinux.cfg" "${ISO_ROOT}/boot/syslinux/syslinux.cfg"
cp "${ISO_ROOT}/isolinux/isolinux.cfg" "${ISO_ROOT}/isolinux.cfg"
cp "${ISO_ROOT}/isolinux/isolinux.cfg" "${ISO_ROOT}/syslinux.cfg"

# 7. Configure GRUB (UEFI Boot)
echo "--> Setting up GRUB for UEFI boot..."
cat <<'EOF' > "${ISO_ROOT}/boot/grub/grub.cfg"
set default="0"
set timeout=5

menuentry "BootOS (Standard - Fast Boot)" {
    linux /boot/vmlinuz quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init
    initrd /boot/initramfs.gz
}

menuentry "BootOS (Safe Graphics Mode - nomodeset)" {
    linux /boot/vmlinuz nomodeset quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init
    initrd /boot/initramfs.gz
}

menuentry "BootOS (Legacy Hardware Compatibility Mode)" {
    linux /boot/vmlinuz nomodeset vga=normal quiet loglevel=3 kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init
    initrd /boot/initramfs.gz
}

menuentry "BootOS (Verbose Debug Mode)" {
    linux /boot/vmlinuz kexec_load_disabled=0 console=tty0 usbcore.autosuspend=-1 init=/init
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
