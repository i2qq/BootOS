#!/bin/sh
# ==============================================================================
# BootOS - Ultra-lightweight RAM-resident Bootloader & OS Downloader
# ==============================================================================

# Colors
BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

clear

get_ram_info() {
    free -m | awk '/Mem:/ {printf "%d MB total, %d MB free", $2, $7}'
}

get_net_info() {
    ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [ -n "$ip_addr" ]; then
        echo -e "${GREEN}Connected ($ip_addr)${RESET}"
    else
        echo -e "${RED}Disconnected (Run Option 6)${RESET}"
    fi
}

check_internet() {
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "  ____              _    ___  ____  "
    echo " | __ )  ___   ___ | |_ / _ \/ ___| "
    echo " |  _ \ / _ \ / _ \| __| | | \___ \ "
    echo " | |_) | (_) | (_) | |_| |_| |___) |"
    echo " |____/ \___/ \___/ \__|\___/|____/ "
    echo -e "${RESET}"
    echo -e " ${BOLD}BootOS - 100% RAM-Resident OS Downloader & Bootloader${RESET}"
    echo -e " Running entirely from DRAM. USB can be safely removed!"
    echo " ------------------------------------------------------------"
    echo -e " ${BOLD}Memory :${RESET} $(get_ram_info)"
    echo -e " ${BOLD}Network:${RESET} $(get_net_info)"
    echo " ------------------------------------------------------------"
}

setup_network() {
    echo -e "\n${YELLOW}Configuring Network Interfaces...${RESET}"
    for iface in $(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo'); do
        echo -e "Bringing up $iface..."
        ip link set "$iface" up
        udhcpc -i "$iface" -n -q -t 5 2>/dev/null || dhclient -1 "$iface" 2>/dev/null
    done

    if check_internet; then
        echo -e "${GREEN}✓ Internet connection established!${RESET}"
    else
        echo -e "${RED}✗ Could not reach internet. Please plug in Ethernet cable or configure Wi-Fi.${RESET}"
    fi
    echo -e "\nPress Enter to continue..."
    read -r _
}

# Boot via kexec
boot_kexec() {
    kernel_path="$1"
    initrd_path="$2"
    cmdline="$3"

    echo -e "\n${CYAN}Loading target kernel into DRAM via kexec...${RESET}"
    if ! command -v kexec >/dev/null 2>&1; then
        echo -e "${RED}Error: kexec utility not found!${RESET}"
        return 1
    fi

    echo -e "Kernel : $kernel_path"
    echo -e "Initrd : $initrd_path"
    echo -e "Params : $cmdline"

    kexec -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Starting target operating system now!${RESET}"
        sleep 2
        kexec -e
    else
        echo -e "${RED}Failed to load kernel into kexec!${RESET}"
    fi
}

download_and_boot_lubuntu() {
    show_banner
    echo -e "${YELLOW}=== Download & Boot Lubuntu (Lightweight for Old PCs) ===${RESET}\n"
    if ! check_internet; then
        echo -e "${RED}Network is not ready! Setting up network first...${RESET}"
        setup_network
    fi

    mkdir -p /tmp/target_os
    cd /tmp/target_os || exit 1

    echo -e "${CYAN}Choose Lubuntu Boot Mode:${RESET}"
    echo " 1) Fast Netboot (Downloads ~80MB kernel+initrd, installs over internet)"
    echo " 2) Live ISO to RAM (Downloads full ~2.5GB Live ISO into DRAM - needs >=4GB RAM)"
    echo " 3) Back to Menu"
    echo -n "Select [1-3]: "
    read -r mode

    case "$mode" in
        1)
            echo -e "${GREEN}Fetching Lubuntu/Ubuntu Netboot Assets...${RESET}"
            # Ubuntu netboot assets
            VMLINUZ_URL="https://archive.ubuntu.com/ubuntu/dists/noble/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux"
            INITRD_URL="https://archive.ubuntu.com/ubuntu/dists/noble/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
            
            # Alternative: Debian/Ubuntu mini netboot
            echo "Downloading netboot kernel..."
            wget -q --show-progress -O vmlinuz "$VMLINUZ_URL" || curl -L -o vmlinuz "$VMLINUZ_URL"
            echo "Downloading netboot initrd..."
            wget -q --show-progress -O initrd.gz "$INITRD_URL" || curl -L -o initrd.gz "$INITRD_URL"

            if [ -s vmlinuz ] && [ -s initrd.gz ]; then
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd.gz" "auto=true priority=critical"
            else
                echo -e "${RED}Download failed. Please check network connection.${RESET}"
                read -r _
            fi
            ;;
        2)
            echo -e "${YELLOW}Enter Lubuntu ISO direct download URL:${RESET}"
            echo "Default: https://cdimage.ubuntu.com/lubuntu/releases/24.04/release/lubuntu-24.04-desktop-amd64.iso"
            echo -n "Press Enter to use default or paste custom URL: "
            read -r iso_url
            [ -z "$iso_url" ] && iso_url="https://cdimage.ubuntu.com/lubuntu/releases/24.04/release/lubuntu-24.04-desktop-amd64.iso"

            echo -e "${GREEN}Downloading ISO into RAM (/tmp/lubuntu.iso)...${RESET}"
            wget -q --show-progress -O /tmp/lubuntu.iso "$iso_url" || curl -L -o /tmp/lubuntu.iso "$iso_url"

            if [ -s /tmp/lubuntu.iso ]; then
                echo -e "${GREEN}Extracting kernel and initrd from ISO...${RESET}"
                mkdir -p /tmp/iso_mount
                mount -o loop /tmp/lubuntu.iso /tmp/iso_mount
                cp /tmp/iso_mount/casper/vmlinuz /tmp/target_os/
                cp /tmp/iso_mount/casper/initrd /tmp/target_os/
                umount /tmp/iso_mount
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd" "boot=casper toram iso-scan/filename=/tmp/lubuntu.iso quiet splash"
            else
                echo -e "${RED}Download failed!${RESET}"
                read -r _
            fi
            ;;
        *)
            return
            ;;
    esac
}

download_and_boot_ubuntu() {
    show_banner
    echo -e "${YELLOW}=== Download & Boot Ubuntu 24.04 LTS ===${RESET}\n"
    if ! check_internet; then
        setup_network
    fi

    mkdir -p /tmp/target_os
    cd /tmp/target_os || exit 1

    echo -e "${CYAN}Select Ubuntu Flavor:${RESET}"
    echo " 1) Ubuntu Server 24.04 (Netboot / Direct Boot)"
    echo " 2) Ubuntu Desktop 24.04 Live"
    echo " 3) Back"
    echo -n "Choice: "
    read -r ub_choice

    case "$ub_choice" in
        1)
            # Ubuntu Netboot
            echo -e "${GREEN}Downloading Ubuntu Noble Netboot kernel & initrd...${RESET}"
            KERNEL="https://cloud-images.ubuntu.com/minimal/releases/noble/release/unpacked/ubuntu-24.04-minimal-cloudimg-amd64-vmlinuz-generic"
            INITRD="https://cloud-images.ubuntu.com/minimal/releases/noble/release/unpacked/ubuntu-24.04-minimal-cloudimg-amd64-initrd-generic"
            wget -q --show-progress -O vmlinuz "$KERNEL" || curl -L -o vmlinuz "$KERNEL"
            wget -q --show-progress -O initrd "$INITRD" || curl -L -o initrd "$INITRD"
            if [ -s vmlinuz ] && [ -s initrd ]; then
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd" "console=tty1 root=/dev/ram0 rw"
            fi
            ;;
        2)
            echo -e "${YELLOW}Enter Ubuntu Desktop ISO direct URL (or press Enter for default):${RESET}"
            DEFAULT_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso"
            echo -n "URL [$DEFAULT_URL]: "
            read -r custom_url
            [ -z "$custom_url" ] && custom_url="$DEFAULT_URL"

            wget -q --show-progress -O /tmp/ubuntu.iso "$custom_url" || curl -L -o /tmp/ubuntu.iso "$custom_url"
            if [ -s /tmp/ubuntu.iso ]; then
                mkdir -p /tmp/iso_mount
                mount -o loop /tmp/ubuntu.iso /tmp/iso_mount
                cp /tmp/iso_mount/casper/vmlinuz /tmp/target_os/
                cp /tmp/iso_mount/casper/initrd /tmp/target_os/
                umount /tmp/iso_mount
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd" "boot=casper toram iso-scan/filename=/tmp/ubuntu.iso quiet splash"
            fi
            ;;
        *)
            return
            ;;
    esac
}

custom_os_downloader() {
    show_banner
    echo -e "${YELLOW}=== Custom OS Downloader & Boot ===${RESET}\n"
    echo "Enter direct URL for Kernel (vmlinuz):"
    read -r k_url
    echo "Enter direct URL for Initrd:"
    read -r i_url
    echo "Enter kernel boot parameters (or press Enter for default 'quiet'):"
    read -r cmd_params
    [ -z "$cmd_params" ] && cmd_params="quiet"

    if [ -n "$k_url" ] && [ -n "$i_url" ]; then
        mkdir -p /tmp/custom
        echo "Downloading kernel..."
        wget -q --show-progress -O /tmp/custom/vmlinuz "$k_url" || curl -L -o /tmp/custom/vmlinuz "$k_url"
        echo "Downloading initrd..."
        wget -q --show-progress -O /tmp/custom/initrd "$i_url" || curl -L -o /tmp/custom/initrd "$i_url"

        if [ -s /tmp/custom/vmlinuz ] && [ -s /tmp/custom/initrd ]; then
            boot_kexec "/tmp/custom/vmlinuz" "/tmp/custom/initrd" "$cmd_params"
        else
            echo -e "${RED}Download failed!${RESET}"
            read -r _
        fi
    fi
}

flash_drive_utility() {
    show_banner
    echo -e "${YELLOW}=== Flash Downloaded OS ISO to Internal Drive / SSD ===${RESET}\n"
    echo -e "${RED}${BOLD}WARNING: Writing an image will ERASE the target drive!${RESET}\n"
    
    echo -e "${CYAN}Available Storage Drives:${RESET}"
    lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null || fdisk -l | grep "Disk /dev"
    echo ""
    echo "Enter direct URL of the ISO image to download:"
    read -r iso_url
    if [ -z "$iso_url" ]; then
        echo "Aborted."
        read -r _
        return
    fi

    echo "Enter target drive path (e.g. /dev/sda, /dev/nvme0n1):"
    read -r target_drive

    if [ ! -b "$target_drive" ]; then
        echo -e "${RED}Error: '$target_drive' is not a valid block device!${RESET}"
        read -r _
        return
    fi

    echo -e "${RED}Are you absolutely sure you want to write to $target_drive? (type 'YES')${RESET}"
    read -r confirm
    if [ "$confirm" != "YES" ]; then
        echo "Canceled."
        read -r _
        return
    fi

    echo -e "${GREEN}Streaming and writing ISO directly to $target_drive...${RESET}"
    curl -L "$iso_url" | dd of="$target_drive" bs=4M status=progress conv=fdatasync
    echo -e "\n${GREEN}Write complete! You can now reboot into the installed system.${RESET}"
    read -r _
}

# Main Loop
while true; do
    show_banner
    echo -e " ${BOLD}Main Menu:${RESET}"
    echo -e "  ${GREEN}[1]${RESET} Download & Boot Lubuntu (Fast / Best for Old PCs)"
    echo -e "  ${GREEN}[2]${RESET} Download & Boot Ubuntu 24.04 LTS"
    echo -e "  ${GREEN}[3]${RESET} Download & Boot Custom Kernel/Initrd"
    echo -e "  ${GREEN}[4]${RESET} Flash Downloaded ISO to Internal Hard Drive / SSD"
    echo -e "  ${GREEN}[5]${RESET} Setup Network (Ethernet DHCP / Diagnostics)"
    echo -e "  ${GREEN}[6]${RESET} Launch iPXE / Netboot.xyz (Hundreds of OSs on-demand)"
    echo -e "  ${GREEN}[7]${RESET} Open Root Terminal Shell"
    echo -e "  ${GREEN}[8]${RESET} Reboot System"
    echo -e "  ${GREEN}[9]${RESET} Power Off"
    echo ""
    echo -n " Please select an option [1-9]: "
    read -r choice

    case "$choice" in
        1) download_and_boot_lubuntu ;;
        2) download_and_boot_ubuntu ;;
        3) custom_os_downloader ;;
        4) flash_drive_utility ;;
        5) setup_network ;;
        6)
            echo -e "${GREEN}Chainloading netboot.xyz via iPXE...${RESET}"
            if command -v ipxe >/dev/null 2>&1; then
                ipxe
            else
                # Download netboot.xyz lkrn and kexec
                mkdir -p /tmp/netboot
                wget -O /tmp/netboot/netboot.xyz.lkrn https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn 2>/dev/null || curl -L -o /tmp/netboot/netboot.xyz.lkrn https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn
                kexec -l /tmp/netboot/netboot.xyz.lkrn
                kexec -e
            fi
            ;;
        7)
            echo -e "\n${CYAN}Dropping to BootOS Terminal Shell. Type 'exit' to return to menu.${RESET}\n"
            /bin/sh
            ;;
        8)
            echo -e "\n${YELLOW}Rebooting...${RESET}"
            reboot
            ;;
        9)
            echo -e "\n${YELLOW}Shutting down...${RESET}"
            poweroff
            ;;
        *)
            echo -e "\n${RED}Invalid option!${RESET}"
            sleep 1
            ;;
    esac
done
