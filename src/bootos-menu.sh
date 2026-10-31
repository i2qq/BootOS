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
        echo -e "${RED}Disconnected (Run Option 5)${RESET}"
    fi
}

check_internet() {
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
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
    echo -e "\n${YELLOW}Scanning for hardware and probing network drivers...${RESET}"
    depmod -a 2>/dev/null || true

    # Explicitly load common network modules (VirtualBox Intel PRO/1000, VirtIO, Realtek, etc.)
    for mod in e1000 e1000e igb virtio_net vmxnet3 r8169 pcnet32 tg3 b44 forcedeth 8139too 8139cp; do
        modprobe "$mod" 2>/dev/null || true
    done

    # Probe all PCI modaliases
    find /sys -name modalias -exec cat {} + 2>/dev/null | xargs -n1 modprobe 2>/dev/null || true
    sleep 1

    echo -e "${YELLOW}Configuring Network Interfaces via DHCP...${RESET}"
    ifaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v 'lo')
    
    if [ -z "$ifaces" ]; then
        echo -e "${RED}No network interfaces detected!${RESET}"
        echo -e "If running in a VM, check that Network Adapter is enabled (NAT or Bridged)."
    fi

    for iface in $ifaces; do
        echo -e "Bringing up ${BOLD}$iface${RESET}..."
        ip link set "$iface" up 2>/dev/null
        if [ -f /usr/share/udhcpc/default.script ]; then
            udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -n -q -t 5 2>/dev/null || true
        else
            udhcpc -i "$iface" -n -q -t 5 2>/dev/null || true
        fi
    done

    # Fallback default DNS
    if [ ! -s /etc/resolv.conf ]; then
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    fi

    if check_internet; then
        echo -e "${GREEN}✓ Internet connection established!${RESET}"
    else
        echo -e "${RED}✗ Could not reach internet.${RESET}"
        echo -e "In VirtualBox: Ensure VM Settings -> Network -> 'Attached to: NAT' or 'Bridged Adapter'."
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

    if [ -n "$initrd_path" ] && [ -f "$initrd_path" ]; then
        kexec -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline"
    else
        kexec -l "$kernel_path" --command-line="$cmdline"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Starting target operating system now!${RESET}"
        sleep 2
        kexec -e
    else
        echo -e "${RED}Failed to load kernel into kexec!${RESET}"
    fi
}

# ==============================================================================
# GitHub Release ISO Downloader & Installer
# ==============================================================================
github_release_os_installer() {
    show_banner
    echo -e "${YELLOW}=== Install / Boot OS from GitHub Release ISO ===${RESET}\n"

    if ! check_internet; then
        echo -e "${RED}Network is not ready! Attempting auto-configuration...${RESET}"
        setup_network
    fi

    echo -e "Enter the GitHub repository URL or path:"
    echo -e "  Examples: ${CYAN}owner/repo${RESET}  or  ${CYAN}https://github.com/owner/repo${RESET}"
    echo -e "  Or tag:   ${CYAN}https://github.com/owner/repo/releases/tag/v1.0${RESET}"
    echo -n "Repo: "
    read -r raw_repo

    if [ -z "$raw_repo" ]; then
        echo "Aborted."
        sleep 1
        return
    fi

    clean_input=$(echo "$raw_repo" | sed -e 's|^https://github.com/||' -e 's|^http://github.com/||' -e 's|\.git$||' -e 's|/$||')
    owner=$(echo "$clean_input" | awk -F'/' '{print $1}')
    repo=$(echo "$clean_input" | awk -F'/' '{print $2}')
    tag=""

    if echo "$clean_input" | grep -q '/releases/tag/'; then
        tag=$(echo "$clean_input" | sed -e 's|.*/releases/tag/||')
    fi

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo -e "${RED}Invalid repository format! Expected 'owner/repo' or GitHub URL.${RESET}"
        echo "Press Enter to return..."
        read -r _
        return
    fi

    echo -e "\n${CYAN}Querying GitHub API for ${owner}/${repo}...${RESET}"
    
    auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: token $GITHUB_TOKEN"
    fi

    api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    if [ -n "$tag" ]; then
        api_url="https://api.github.com/repos/${owner}/${repo}/releases/tags/${tag}"
    fi

    release_json="/tmp/gh_release.json"
    if [ -n "$auth_header" ]; then
        curl -sSL -H "$auth_header" -H "Accept: application/vnd.github.v3+json" "$api_url" -o "$release_json"
    else
        curl -sSL -H "Accept: application/vnd.github.v3+json" "$api_url" -o "$release_json"
    fi

    if grep -q '"message": "Not Found"' "$release_json" && [ -z "$tag" ]; then
        echo "Latest release not found, checking all releases..."
        curl -sSL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${owner}/${repo}/releases" -o "/tmp/gh_releases_all.json"
        if [ -s "/tmp/gh_releases_all.json" ]; then
            if command -v jq >/dev/null 2>&1; then
                jq '.[0]' /tmp/gh_releases_all.json > "$release_json" 2>/dev/null || true
            fi
        fi
    fi

    rel_name=""
    rel_tag=""
    if command -v jq >/dev/null 2>&1; then
        rel_name=$(jq -r '.name // empty' "$release_json" 2>/dev/null)
        rel_tag=$(jq -r '.tag_name // empty' "$release_json" 2>/dev/null)
    fi

    if [ -z "$rel_tag" ]; then
        rel_tag=$(grep -o '"tag_name": *"[^"]*"' "$release_json" | head -n1 | cut -d'"' -f4)
    fi
    if [ -z "$rel_name" ]; then
        rel_name="$rel_tag"
    fi

    if [ -z "$rel_tag" ]; then
        echo -e "${RED}Could not find any release in https://github.com/${owner}/${repo}${RESET}"
        head -n 5 "$release_json"
        echo "Press Enter to return..."
        read -r _
        return
    fi

    echo -e "${GREEN}✓ Found Release:${RESET} ${BOLD}${rel_name}${RESET} (${rel_tag})"

    asset_list="/tmp/gh_assets.txt"
    rm -f "$asset_list"

    if command -v jq >/dev/null 2>&1; then
        jq -r '.assets[] | select(.name | test("\\.(iso|img|raw)$"; "i")) | "\(.name)|\(.size)|\(.browser_download_url)"' "$release_json" > "$asset_list" 2>/dev/null || true
    fi

    if [ ! -s "$asset_list" ]; then
        awk '
            /"name":/ { gsub(/[",]/,"",$2); name=$2 }
            /"size":/ { gsub(/[",]/,"",$2); size=$2 }
            /"browser_download_url":/ {
                gsub(/[",]/,"",$2); url=$2;
                if (name ~ /\.(iso|img|raw)$/i) {
                    print name "|" size "|" url;
                }
            }
        ' "$release_json" > "$asset_list"
    fi

    count=$(wc -l < "$asset_list")

    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No .iso or .img files found in release '${rel_tag}'!${RESET}"
        echo -e "Available assets in release:"
        if command -v jq >/dev/null 2>&1; then
            jq -r '.assets[].name' "$release_json"
        else
            grep -o '"name": *"[^"]*"' "$release_json" | cut -d'"' -f4
        fi
        echo -e "\nPress Enter to return..."
        read -r _
        return
    fi

    echo -e "\n${CYAN}Available OS Images in this Release:${RESET}"
    i=1
    while IFS='|' read -r aname asize aurl; do
        size_mb=$((asize / 1024 / 1024))
        echo -e "  [${GREEN}$i${RESET}] $aname (${YELLOW}${size_mb} MB${RESET})"
        i=$((i + 1))
    done < "$asset_list"

    selected_idx=1
    if [ "$count" -gt 1 ]; then
        echo -n "Select image [1-$count]: "
        read -r selected_idx
    fi

    selected_line=$(sed -n "${selected_idx}p" "$asset_list")
    if [ -z "$selected_line" ]; then
        echo -e "${RED}Invalid selection!${RESET}"
        read -r _
        return
    fi

    selected_name=$(echo "$selected_line" | cut -d'|' -f1)
    selected_size=$(echo "$selected_line" | cut -d'|' -f2)
    selected_url=$(echo "$selected_line" | cut -d'|' -f3)

    echo -e "\n${BOLD}Selected:${RESET} $selected_name"
    echo -e "${CYAN}What would you like to do with this OS image?${RESET}"
    echo -e "  ${GREEN}[1]${RESET} Flash & Install directly to Hard Drive / SSD (/dev/sda)"
    echo -e "  ${GREEN}[2]${RESET} Live DRAM Boot (Mount in RAM and kexec into it)"
    echo -e "  ${GREEN}[3]${RESET} Download ISO to local storage"
    echo -e "  ${GREEN}[4]${RESET} Back to Menu"
    echo -n "Choice [1-4]: "
    read -r action_choice

    case "$action_choice" in
        1)
            echo -e "\n${YELLOW}=== Storage Drives Detected ===${RESET}"
            lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null || fdisk -l | grep "Disk /dev"
            echo ""
            echo "Enter target drive to install this OS to (e.g. /dev/sda, /dev/nvme0n1):"
            read -r target_dev

            if [ ! -b "$target_dev" ]; then
                echo -e "${RED}Error: '$target_dev' is not a valid block device!${RESET}"
                read -r _
                return
            fi

            echo -e "${RED}${BOLD}WARNING: Writing $selected_name will ERASE ALL DATA on $target_dev!${RESET}"
            echo -n "Type 'YES' to proceed with installation: "
            read -r confirm
            if [ "$confirm" != "YES" ]; then
                echo "Canceled."
                read -r _
                return
            fi

            echo -e "\n${GREEN}Streaming and writing $selected_name to $target_dev...${RESET}"
            curl -L "$selected_url" | dd of="$target_dev" bs=4M status=progress conv=fdatasync
            sync
            echo -e "\n${GREEN}✓ Installation complete!${RESET}"
            echo -e "You can now reboot your PC and it will boot into your newly installed OS from $target_dev."
            echo "Press Enter to return..."
            read -r _
            ;;
        2)
            echo -e "\n${GREEN}Downloading $selected_name into DRAM (/tmp/target_os.iso)...${RESET}"
            curl -L -o /tmp/target_os.iso "$selected_url"
            
            if [ -s /tmp/target_os.iso ]; then
                echo -e "${CYAN}Extracting kernel and initrd from ISO...${RESET}"
                mkdir -p /tmp/gh_mount /tmp/kexec_boot
                mount -o loop /tmp/target_os.iso /tmp/gh_mount

                k_file=$(find /tmp/gh_mount -type f \( -name "vmlinuz*" -o -name "linux" -o -name "bzImage" \) | head -n1)
                i_file=$(find /tmp/gh_mount -type f \( -name "initrd*" -o -name "initramfs*" \) | head -n1)

                if [ -n "$k_file" ]; then
                    echo "Found Kernel: $k_file"
                    cp "$k_file" /tmp/kexec_boot/vmlinuz
                    if [ -n "$i_file" ]; then
                        echo "Found Initrd: $i_file"
                        cp "$i_file" /tmp/kexec_boot/initrd
                    fi
                    umount /tmp/gh_mount

                    echo -e "\n${CYAN}Boot parameters (press Enter for default 'boot=casper toram iso-scan/filename=/tmp/target_os.iso quiet'):${RESET}"
                    read -r user_params
                    [ -z "$user_params" ] && user_params="boot=casper toram iso-scan/filename=/tmp/target_os.iso quiet splash"

                    boot_kexec "/tmp/kexec_boot/vmlinuz" "/tmp/kexec_boot/initrd" "$user_params"
                else
                    umount /tmp/gh_mount
                    echo -e "${RED}Could not locate standard kernel inside the ISO!${RESET}"
                    read -r _
                fi
            else
                echo -e "${RED}Failed to download ISO!${RESET}"
                read -r _
            fi
            ;;
        3)
            echo "Enter directory to save ISO (default /tmp):"
            read -r dest_dir
            [ -z "$dest_dir" ] && dest_dir="/tmp"
            mkdir -p "$dest_dir"
            echo -e "${GREEN}Downloading $selected_name to $dest_dir...${RESET}"
            curl -L -o "${dest_dir}/${selected_name}" "$selected_url"
            echo -e "${GREEN}Saved to ${dest_dir}/${selected_name}!${RESET}"
            read -r _
            ;;
        *)
            return
            ;;
    esac
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
    echo " 2) Live ISO to RAM (Downloads full Live ISO into DRAM - needs >=4GB RAM)"
    echo " 3) Back to Menu"
    echo -n "Select [1-3]: "
    read -r mode

    case "$mode" in
        1)
            echo -e "${GREEN}Fetching Lubuntu/Ubuntu Netboot Assets...${RESET}"
            VMLINUZ_URL="https://archive.ubuntu.com/ubuntu/dists/noble/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/linux"
            INITRD_URL="https://archive.ubuntu.com/ubuntu/dists/noble/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/initrd.gz"
            
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
    echo -e "  ${GREEN}[1]${RESET} ${BOLD}Install / Boot OS from GitHub Release ISO${RESET}"
    echo -e "  ${GREEN}[2]${RESET} Download & Boot Lubuntu (Fast / Best for Old PCs)"
    echo -e "  ${GREEN}[3]${RESET} Download & Boot Ubuntu 24.04 LTS"
    echo -e "  ${GREEN}[4]${RESET} Download & Boot Custom Kernel/Initrd"
    echo -e "  ${GREEN}[5]${RESET} Setup Network (Ethernet DHCP / Diagnostics)"
    echo -e "  ${GREEN}[6]${RESET} Flash Downloaded ISO to Internal Hard Drive / SSD"
    echo -e "  ${GREEN}[7]${RESET} Launch iPXE / Netboot.xyz (Hundreds of OSs on-demand)"
    echo -e "  ${GREEN}[8]${RESET} Open Root Terminal Shell"
    echo -e "  ${GREEN}[9]${RESET} Reboot System"
    echo -e "  ${GREEN}[10]${RESET} Power Off"
    echo ""
    echo -n " Please select an option [1-10]: "
    read -r choice

    case "$choice" in
        1|"0"|"gh"|"github"|"star"|"*") github_release_os_installer ;;
        2) download_and_boot_lubuntu ;;
        3) download_and_boot_ubuntu ;;
        4) custom_os_downloader ;;
        5|"net"|"network") setup_network ;;
        6) flash_drive_utility ;;
        7)
            echo -e "${GREEN}Chainloading netboot.xyz via iPXE...${RESET}"
            if command -v ipxe >/dev/null 2>&1; then
                ipxe
            else
                mkdir -p /tmp/netboot
                wget -O /tmp/netboot/netboot.xyz.lkrn https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn 2>/dev/null || curl -L -o /tmp/netboot/netboot.xyz.lkrn https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn
                kexec -l /tmp/netboot/netboot.xyz.lkrn
                kexec -e
            fi
            ;;
        8)
            echo -e "\n${CYAN}Dropping to BootOS Terminal Shell. Type 'exit' to return to menu.${RESET}\n"
            /bin/sh
            ;;
        9)
            echo -e "\n${YELLOW}Rebooting...${RESET}"
            reboot
            ;;
        10)
            echo -e "\n${YELLOW}Shutting down...${RESET}"
            poweroff
            ;;
        *)
            echo -e "\n${RED}Invalid option!${RESET}"
            sleep 1
            ;;
    esac
done
