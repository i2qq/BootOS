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

[ -z "$TERM" ] || [ "$TERM" = "linux" ] && export TERM=vt100
export TERMINFO_DIRS=/usr/share/terminfo:/etc/terminfo:/lib/terminfo
printf "\033[2J\033[1;1H"

get_ram_info() {
    free -m | awk '/Mem:/ {printf "%d MB total, %d MB free", $2, $7}'
}

get_net_info() {
    ip_addr=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    if [ -z "$ip_addr" ]; then
        ip_addr=$(ip -o -4 addr show 2>/dev/null | grep -v ' lo ' | awk '{print $4}' | cut -d/ -f1 | head -n1)
    fi
    if [ -z "$ip_addr" ]; then
        for iface in $(ls /sys/class/net 2>/dev/null | grep -v '^lo$'); do
            if [ "$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo 0)" = "1" ]; then
                udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -n -q -t 2 -T 1 >/dev/null 2>&1 || true
                ip_addr=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
                [ -n "$ip_addr" ] && break
            fi
        done
    fi
    if [ -n "$ip_addr" ]; then
        echo -e "${GREEN}Connected ($ip_addr)${RESET}"
    else
        echo -e "${RED}Disconnected (Run Option 8)${RESET}"
    fi
}

check_internet() {
    # 1. ICMP ping (fast)
    if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    # 2. HTTP connectivity (in case firewall blocks ICMP)
    if curl -s --connect-timeout 2 -I http://1.1.1.1 >/dev/null 2>&1 || wget -q -T 2 -O - http://1.1.1.1 >/dev/null 2>&1; then
        return 0
    fi
    # 3. DNS lookup test
    if nslookup google.com 1.1.1.1 >/dev/null 2>&1 || nslookup google.com 8.8.8.8 >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

get_persist_info() {
    if [ -f /etc/bootos_persist_dev ]; then
        pdev=$(cat /etc/bootos_persist_dev 2>/dev/null | tr -d '\r\n ')
        if [ -n "$pdev" ]; then
            echo -e "${GREEN}Active ($pdev)${RESET}"
            return
        fi
    fi
    echo -e "${YELLOW}Ephemeral DRAM (Run Option 11 to save)${RESET}"
}

show_banner() {
    printf "\033[2J\033[1;1H"
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
    echo -e " ${BOLD}Persist:${RESET} $(get_persist_info)"
    echo " ------------------------------------------------------------"
}

setup_network() {
    echo -e "\n${YELLOW}=== Network Hardware Scanning & Configuration ===${RESET}\n"

    echo "1. Probing network card drivers..."
    for mod in e1000 e1000e igb igc virtio_net vmxnet3 r8169 r8152 cdc_ether cdc_ncm rndis_host ax88179_178a asix pcnet32 tg3 b44 forcedeth 8139too 8139cp atlantic sky2 alx atl1 atl1c atl1e jme e100 hv_netvsc iwlwifi iwlmvm mt7921e mt7921u rtw88_8821ce rtw88_8822ce rtw89_8852ae rtw89_8852be; do
        modprobe "$mod" 2>/dev/null || true
    done

    # Trigger udev for any remaining network devices cleanly and asynchronously
    if command -v udevadm >/dev/null 2>&1; then
        udevadm trigger --subsystem-match=net 2>/dev/null || true
    fi
    sleep 1

    echo "2. Detecting network interfaces..."
    ifaces=$(ls /sys/class/net 2>/dev/null | grep -v '^lo$')

    if [ -z "$ifaces" ]; then
        echo -e "${RED}✗ No network interfaces detected!${RESET}\n"
        echo -e "${CYAN}Hardware Diagnostics:${RESET}"
        lspci -nn 2>/dev/null | grep -iE 'ethernet|network|wireless' || echo "  (No PCI network adapters found via lspci)"
        echo -e "\n${YELLOW}Troubleshooting Tips:${RESET}"
        echo " - In VirtualBox: Open VM Settings -> Network -> Check 'Enable Network Adapter', Attached to: NAT."
        echo " - On Physical PC: Ensure Ethernet cable is firmly plugged in or Wi-Fi card is supported."
        echo -e "\nPress Enter to return..."
        read -r _
        return 1
    fi

    echo -e "Detected interfaces: ${BOLD}$ifaces${RESET}\n"

    for iface in $ifaces; do
        echo -e "--- Configuring ${CYAN}${BOLD}$iface${RESET} ---"
        ip link set "$iface" up 2>/dev/null

        # Check for carrier (up to 3 seconds for PHY auto-negotiation)
        echo -n "Waiting for link carrier..."
        for attempt in 1 2 3; do
            carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo "0")
            if [ "$carrier" = "1" ]; then
                break
            fi
            sleep 1
            echo -n "."
        done
        echo ""

        carrier_state=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || echo "unknown")
        operstate=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
        echo "Link State: operstate=$operstate, carrier=$carrier_state"

        echo "Requesting IP via DHCP (udhcpc)..."
        if [ -f /usr/share/udhcpc/default.script ]; then
            udhcpc -i "$iface" -s /usr/share/udhcpc/default.script -n -q -t 5 -T 2 2>&1
        else
            udhcpc -i "$iface" -n -q -t 5 -T 2 2>&1
        fi

        assigned_ip=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
        if [ -n "$assigned_ip" ]; then
            echo -e "${GREEN}✓ Assigned IP: $assigned_ip on $iface${RESET}\n"
        else
            echo -e "${YELLOW}! No DHCP lease obtained on $iface${RESET}\n"
        fi
    done

    # Fallback default DNS
    if [ ! -s /etc/resolv.conf ]; then
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    fi

    echo "3. Testing internet connectivity..."
    if check_internet; then
        echo -e "${GREEN}✓ Internet connection successfully established!${RESET}"
        current_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
        [ -n "$current_ip" ] && echo -e "Outbound IP: ${BOLD}$current_ip${RESET}"
    else
        echo -e "${RED}✗ Could not reach internet.${RESET}"
        echo "Default route: $(ip route show default 2>/dev/null || echo 'None')"
        echo "DNS servers  : $(cat /etc/resolv.conf 2>/dev/null | tr '\n' ' ')"
        echo -e "\nIf in VirtualBox: VM Settings -> Network -> Adapter 1 -> Attached to: NAT."
        echo "If on physical PC: Check that your router's DHCP server is running and cable is plugged in."
    fi
    echo -e "\nPress Enter to return..."
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
        echo "Press Enter to return..."
        read -r _
        return 1
    fi

    # Attempt to unlock kexec sysctl if writable
    if [ -f /proc/sys/kernel/kexec_load_disabled ]; then
        echo 0 > /proc/sys/kernel/kexec_load_disabled 2>/dev/null || true
    fi

    echo -e "Kernel : $kernel_path"
    echo -e "Initrd : $initrd_path"
    echo -e "Params : $cmdline"

    LOADED=0
    # 1. Try legacy syscall kexec -l (standard for Alpine/BusyBox)
    if [ -n "$initrd_path" ] && [ -f "$initrd_path" ]; then
        if kexec -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline" 2>/dev/null; then
            LOADED=1
        fi
    else
        if kexec -l "$kernel_path" --command-line="$cmdline" 2>/dev/null; then
            LOADED=1
        fi
    fi

    # 2. Try modern file-based syscall kexec -s -l
    if [ $LOADED -eq 0 ]; then
        if [ -n "$initrd_path" ] && [ -f "$initrd_path" ]; then
            if kexec -s -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline" 2>/dev/null; then
                LOADED=1
            fi
        else
            if kexec -s -l "$kernel_path" --command-line="$cmdline" 2>/dev/null; then
                LOADED=1
            fi
        fi
    fi

    # 3. Fallback with --force / --reset-vga
    if [ $LOADED -eq 0 ]; then
        echo -e "${YELLOW}Retrying with reset-vga / force flags...${RESET}"
        if [ -n "$initrd_path" ] && [ -f "$initrd_path" ]; then
            kexec -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline" --reset-vga 2>/dev/null || \
            kexec -s -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline" --reset-vga 2>/dev/null
            [ $? -eq 0 ] && LOADED=1
        fi
    fi

    # 4. Final attempt showing stderr if still failing
    if [ $LOADED -eq 0 ]; then
        echo -e "${YELLOW}Diagnostics attempt (showing output):${RESET}"
        if [ -n "$initrd_path" ] && [ -f "$initrd_path" ]; then
            kexec -l "$kernel_path" --initrd="$initrd_path" --command-line="$cmdline"
            [ $? -eq 0 ] && LOADED=1
        fi
    fi

    if [ $LOADED -eq 1 ]; then
        echo -e "\n${GREEN}Starting target operating system now!${RESET}"
        sleep 1
        kexec -e
    else
        echo -e "\n${RED}Failed to load kernel into kexec!${RESET}"
        if [ -f /proc/sys/kernel/kexec_load_disabled ]; then
            dis_val=$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null || echo "?")
            echo -e "${YELLOW}Kernel kexec status (/proc/sys/kernel/kexec_load_disabled): ${dis_val}${RESET}"
            if [ "$dis_val" = "1" ]; then
                echo -e "${RED}Alpine kernel locked kexec at boot. Boot BootOS with 'kexec_load_disabled=0'.${RESET}"
            fi
        fi
        echo -e "${YELLOW}Tip: You can also use Option [1] to flash the ISO directly to the VM disk.${RESET}"
        echo "Press Enter to return..."
        read -r _
        return 1
    fi
}

# Helper to select a storage disk device
select_target_drive() {
    SELECTED_DEV=""
    echo -e "\n${CYAN}Detected Storage Drives:${RESET}"
    drives_file="/tmp/detected_drives.txt"
    rm -f "$drives_file"

    # List disks excluding cd-rom (sr*) and loop devices
    lsblk -d -n -p -o NAME,SIZE,MODEL,TYPE 2>/dev/null | grep -E "disk" | awk '{print $1 "|" $2 " " $3 " " $4}' > "$drives_file" 2>/dev/null || true

    if [ ! -s "$drives_file" ]; then
        for d in /sys/block/sd* /sys/block/nvme* /sys/block/vd* /sys/block/hd* /sys/block/mmcblk*; do
            [ -e "$d" ] || continue
            dev_name="/dev/$(basename "$d")"
            if [ -b "$dev_name" ]; then
                s=$(cat "$d/size" 2>/dev/null || echo 0)
                sz_mb=$((s / 2048))
                echo "$dev_name|${sz_mb}MB disk" >> "$drives_file"
            fi
        done
    fi

    if [ ! -s "$drives_file" ]; then
        echo -e "${RED}No writable disk drives (HDD/SSD) detected!${RESET}"
        return 1
    fi

    d_count=$(wc -l < "$drives_file")
    d_idx=1
    while IFS='|' read -r dev info; do
        echo -e "  [${GREEN}$d_idx${RESET}] ${BOLD}$dev${RESET} ($info)"
        d_idx=$((d_idx + 1))
    done < "$drives_file"

    echo ""
    echo -n "Select drive [1-$d_count] or type device path: "
    read -r user_dev_input
    [ -z "$user_dev_input" ] && user_dev_input="1"

    if echo "$user_dev_input" | grep -qE '^[0-9]+$'; then
        SELECTED_DEV=$(sed -n "${user_dev_input}p" "$drives_file" | cut -d'|' -f1)
    else
        SELECTED_DEV="$user_dev_input"
    fi

    if [ ! -b "$SELECTED_DEV" ]; then
        echo -e "${RED}Error: '$SELECTED_DEV' is not a valid block device!${RESET}"
        return 1
    fi
    return 0
}

# Helper to flash an image (file or URL) to a target block device
flash_image_to_drive() {
    src="$1"
    target="$2"
    img_name="$3"

    echo -e "\n${RED}${BOLD}======================================================${RESET}"
    echo -e "${RED}${BOLD}  WARNING: ALL DATA ON $target WILL BE PERMANENTLY ERASED!${RESET}"
    echo -e "${RED}${BOLD}======================================================${RESET}"
    echo -e "Image Source: ${BOLD}${img_name:-$src}${RESET}"
    echo -e "Target Drive: ${BOLD}${target}${RESET}\n"

    # Disk capacity pre-flight check
    target_bytes=0
    if command -v blockdev >/dev/null 2>&1; then
        target_bytes=$(blockdev --getsize64 "$target" 2>/dev/null || echo 0)
    fi
    if [ -z "$target_bytes" ] || [ "$target_bytes" -le 0 ]; then
        s_base=$(basename "$target")
        s_blocks=$(cat "/sys/class/block/$s_base/size" 2>/dev/null || echo 0)
        target_bytes=$((s_blocks * 512))
    fi
    target_mb=$((target_bytes / 1048576))

    if [ "$target_mb" -gt 0 ]; then
        echo -e "Drive Capacity: ${CYAN}${target_mb} MB${RESET}"
    fi

    # Check source file size if local file
    if [ -f "$src" ]; then
        src_bytes=$(wc -c < "$src" 2>/dev/null || echo 0)
        src_mb=$((src_bytes / 1048576))
        if [ "$target_mb" -gt 0 ] && [ "$src_mb" -gt "$target_mb" ]; then
            echo -e "\n${RED}${BOLD}ERROR: Insufficient drive space!${RESET}"
            echo -e "Source image requires: ${RED}${src_mb} MB${RESET}"
            echo -e "Target drive size    : ${YELLOW}${target_mb} MB${RESET}"
            echo -e "Flashing aborted to prevent writing a truncated, unbootable disk."
            echo "Press Enter to return..."
            read -r _
            return 1
        fi
    fi

    echo -n "Type 'YES' in capital letters to proceed: "
    read -r confirm
    if [ "$confirm" != "YES" ]; then
        echo -e "${YELLOW}Flashing canceled.${RESET}"
        read -r _
        return 1
    fi

    echo -e "\n${GREEN}Writing $img_name to $target...${RESET}"
    flash_err=0
    if [ -f "$src" ]; then
        dd if="$src" of="$target" bs=4M conv=fsync || flash_err=$?
    else
        # URL source: verify final destination is not an HTML webpage
        if ! echo "$src" | grep -qE '(\.iso|\.img|\.raw|/releases/download/)'; then
            header_sample=$(curl -sIL "$src" 2>/dev/null | grep -i "^content-type:" | tail -n1)
            if echo "$header_sample" | grep -iq "text/html"; then
                echo -e "${RED}Error: The provided URL returned an HTML page instead of an ISO/IMG disk image!${RESET}"
                read -r _
                return 1
            fi
        fi
        (set -o pipefail 2>/dev/null; curl -# -L "$src" | dd of="$target" bs=4M conv=fsync) || flash_err=$?
    fi

    if [ "$flash_err" -ne 0 ]; then
        echo -e "\n${RED}Error: Writing to $target failed or ran out of disk space (exit code $flash_err)!${RESET}"
        echo -e "Target drive is likely too small for this operating system."
        echo "Press Enter to return..."
        read -r _
        return 1
    fi

    sync
    echo -e "\n${GREEN}✔ Flashing complete!${RESET}"
    echo -e "You can now reboot your PC and it will boot into the new OS from $target."
    echo "Press Enter to return..."
    read -r _
    return 0
}
# Helper to query and list GitHub release assets
resolve_github_release_assets() {
    raw_repo="$1"
    clean_input=$(echo "$raw_repo" | sed -e 's|^https://github.com/||' -e 's|^http://github.com/||' -e 's|\.git$||' -e 's|/$||')
    owner=$(echo "$clean_input" | awk -F'/' '{print $1}')
    repo=$(echo "$clean_input" | awk -F'/' '{print $2}')
    tag=""

    if echo "$clean_input" | grep -q '/releases/tag/'; then
        tag=$(echo "$clean_input" | sed -e 's|.*/releases/tag/||')
    fi

    if [ -z "$owner" ] || [ -z "$repo" ]; then
        echo -e "${RED}Invalid repository format! Expected 'owner/repo' or GitHub URL.${RESET}"
        return 1
    fi

    echo -e "\n${CYAN}Querying GitHub API for ${owner}/${repo}...${RESET}"
    auth_header=""
    [ -n "$GITHUB_TOKEN" ] && auth_header="Authorization: token $GITHUB_TOKEN"

    api_url="https://api.github.com/repos/${owner}/${repo}/releases/latest"
    [ -n "$tag" ] && api_url="https://api.github.com/repos/${owner}/${repo}/releases/tags/${tag}"

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
    [ -z "$rel_tag" ] && rel_tag=$(grep -o '"tag_name": *"[^"]*"' "$release_json" | head -n1 | cut -d'"' -f4)
    [ -z "$rel_name" ] && rel_name="$rel_tag"

    if [ -z "$rel_tag" ]; then
        echo -e "${RED}Could not find any release in https://github.com/${owner}/${repo}${RESET}"
        return 1
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

    # Fallback to all assets if none match iso/img
    if [ ! -s "$asset_list" ]; then
        if command -v jq >/dev/null 2>&1; then
            jq -r '.assets[] | "\(.name)|\(.size)|\(.browser_download_url)"' "$release_json" > "$asset_list" 2>/dev/null || true
        fi
    fi

    count=$(wc -l < "$asset_list")
    if [ "$count" -eq 0 ]; then
        echo -e "${RED}No downloadable OS images found in release '${rel_tag}'!${RESET}"
        return 1
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
        return 1
    fi

    GH_SELECTED_NAME=$(echo "$selected_line" | cut -d'|' -f1)
    GH_SELECTED_SIZE=$(echo "$selected_line" | cut -d'|' -f2)
    GH_SELECTED_URL=$(echo "$selected_line" | cut -d'|' -f3)
    return 0
}

# Extract kernel and initrd from ISO using 7z or loop mount
extract_iso_assets() {
    iso_file="$1"
    target_dir="$2"
    mkdir -p "$target_dir"

    # Verify file exists and is larger than 10MB
    if [ ! -s "$iso_file" ]; then
        echo -e "${RED}Error: ISO file does not exist or is empty!${RESET}"
        return 1
    fi
    iso_sz=$(wc -c < "$iso_file" 2>/dev/null || echo 0)
    if [ "$iso_sz" -lt 10485760 ]; then
        echo -e "${RED}Error: File '$iso_file' is only ${iso_sz} bytes (not a valid ISO disk image).${RESET}"
        echo -e "${RED}The download likely failed or the server returned an HTTP 404 error webpage.${RESET}"
        return 1
    fi

    # Ensure kernel loop and fs modules are loaded
    modprobe loop 2>/dev/null || true
    modprobe isofs 2>/dev/null || true
    modprobe squashfs 2>/dev/null || true

    # Method 1: Using 7z (Direct, no loop device required)
    if command -v 7z >/dev/null 2>&1; then
        echo -e "${CYAN}Extracting ISO assets using 7z...${RESET}"
        7z x -y -o"$target_dir" "$iso_file" >/dev/null 2>&1 || true
    fi

    # Method 2: Fallback to loop mount if 7z extracted nothing
    k_check=$(find "$target_dir" -type f \( -iname "vmlinuz*" -o -iname "linux*" -o -iname "bzImage*" \) 2>/dev/null | head -n1)
    if [ -z "$k_check" ]; then
        echo -e "${CYAN}Trying loop mount for $iso_file...${RESET}"
        mount_dir="/tmp/loop_mnt_$$"
        mkdir -p "$mount_dir"
        
        # Ensure loop nodes exist
        [ -e /dev/loop-control ] || mknod /dev/loop-control c 10 237 2>/dev/null || true
        for num in 0 1 2 3 4 5 6 7; do
            [ -e "/dev/loop$num" ] || mknod "/dev/loop$num" b 7 "$num" 2>/dev/null || true
        done

        if mount -o loop,ro "$iso_file" "$mount_dir" 2>/dev/null; then
            cp -r "$mount_dir"/* "$target_dir"/ 2>/dev/null || true
            umount "$mount_dir" 2>/dev/null || true
        fi
        rm -rf "$mount_dir"
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

    if ! resolve_github_release_assets "$raw_repo"; then
        echo "Press Enter to return..."
        read -r _
        return
    fi

    selected_name="$GH_SELECTED_NAME"
    selected_size="$GH_SELECTED_SIZE"
    selected_url="$GH_SELECTED_URL"

    echo -e "\n${BOLD}Selected:${RESET} $selected_name"
    echo -e "${CYAN}What would you like to do with this OS image?${RESET}"
    echo -e "  ${GREEN}[1]${RESET} Flash & Install directly to Hard Drive / SSD"
    echo -e "  ${GREEN}[2]${RESET} Live DRAM Boot (Mount/Extract in RAM and kexec into it)"
    echo -e "  ${GREEN}[3]${RESET} Download ISO to local storage"
    echo -e "  ${GREEN}[4]${RESET} Back to Menu"
    echo -n "Choice [1-4]: "
    read -r action_choice

    case "$action_choice" in
        1)
            if select_target_drive; then
                flash_image_to_drive "$selected_url" "$SELECTED_DEV" "$selected_name"
            else
                read -r _
            fi
            ;;
        2)
            echo -e "\n${GREEN}Downloading $selected_name into DRAM (/tmp/target_os.iso)...${RESET}"
            curl -L -o /tmp/target_os.iso "$selected_url"
            
            if [ -s /tmp/target_os.iso ]; then
                echo -e "${CYAN}Extracting kernel and initrd from ISO...${RESET}"
                rm -rf /tmp/extracted_iso /tmp/kexec_boot
                mkdir -p /tmp/extracted_iso /tmp/kexec_boot

                extract_iso_assets "/tmp/target_os.iso" "/tmp/extracted_iso"

                # Locate kernel using case-insensitive find
                k_file=$(find /tmp/extracted_iso -type f \( -iname "vmlinuz*" -o -iname "linux*" -o -iname "bzImage*" -o -iname "kernel*" \) ! -iname "*.c32" ! -iname "*.cfg" ! -iname "*.msg" ! -iname "*.txt" ! -iname "*.png" 2>/dev/null | head -n1)
                # Locate initrd using case-insensitive find
                i_file=$(find /tmp/extracted_iso -type f \( -iname "initrd*" -o -iname "initramfs*" -o -iname "rootfs.cpio*" \) ! -iname "*.cfg" ! -iname "*.txt" 2>/dev/null | head -n1)

                if [ -n "$k_file" ]; then
                    echo -e "${GREEN}✓ Found Kernel:${RESET} $k_file"
                    cp "$k_file" /tmp/kexec_boot/vmlinuz
                    if [ -n "$i_file" ]; then
                        echo -e "${GREEN}✓ Found Initrd:${RESET} $i_file"
                        cp "$i_file" /tmp/kexec_boot/initrd
                    fi

                    # Determine optimal command line arguments
                    default_params="quiet root=/dev/ram0 rw"
                    if [ -d "/tmp/extracted_iso/casper" ]; then
                        default_params="boot=casper toram iso-scan/filename=/tmp/target_os.iso quiet splash"
                    elif [ -f "/tmp/extracted_iso/init" ] || [ -f "/tmp/extracted_iso/usr/local/bin/bootos" ]; then
                        default_params="init=/init quiet console=tty1"
                    fi

                    echo -e "\n${CYAN}Boot parameters (press Enter for auto-detected defaults):${RESET}"
                    echo -e "Default: ${YELLOW}$default_params${RESET}"
                    echo -n "Params: "
                    read -r user_params
                    [ -z "$user_params" ] && user_params="$default_params"

                    boot_kexec "/tmp/kexec_boot/vmlinuz" "/tmp/kexec_boot/initrd" "$user_params"
                else
                    echo -e "${RED}Could not locate a standard Linux kernel inside the ISO!${RESET}"
                    echo "Contents extracted:"
                    ls -la /tmp/extracted_iso
                    echo "Press Enter to return..."
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

    echo -e "${CYAN}Select Lubuntu Release:${RESET}"
    echo "  [1] Lubuntu 26.04 (Next-Gen Daily / Rolling)"
    echo "  [2] Lubuntu 24.04.5 LTS (Noble Numbat - Long Term Support)"
    echo "  [3] Back to Menu"
    echo ""
    echo -n "Select version [1-3]: "
    read -r ver_choice

    case "$ver_choice" in
        1)
            LUBUNTU_NAME="Lubuntu 26.04 (Next-Gen Daily)"
            DEFAULT_LUBUNTU="https://cdimage.ubuntu.com/lubuntu/daily-live/current/pending-desktop-amd64.iso"
            KERNEL_URL="https://cloud-images.ubuntu.com/daily/server/current/unpacked/vmlinuz-generic"
            INITRD_URL="https://cloud-images.ubuntu.com/daily/server/current/unpacked/initrd-generic"
            ;;
        2)
            LUBUNTU_NAME="Lubuntu 24.04.5 LTS Desktop"
            DEFAULT_LUBUNTU="https://cdimage.ubuntu.com/lubuntu/releases/noble/release/lubuntu-24.04.5-desktop-amd64.iso"
            KERNEL_URL="https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-vmlinuz-generic"
            INITRD_URL="https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-initrd-generic"
            ;;
        *)
            return
            ;;
    esac

    echo -e "\n${CYAN}Choose Mode for ${LUBUNTU_NAME}:${RESET}"
    echo "  [1] Flash Live ISO directly to Hard Drive / SSD (Recommended for install)"
    echo "  [2] Live ISO to RAM (Downloads full ~3.8 GB Live ISO into DRAM - needs >= 5 GB RAM)"
    echo "  [3] Fast Minimal Netboot (~45 MB - installs over internet)"
    echo "  [4] Back"
    echo ""
    echo -n "Select [1-4]: "
    read -r mode

    case "$mode" in
        1)
            echo -e "\n${CYAN}Flash ${LUBUNTU_NAME} directly to storage drive:${RESET}"
            if select_target_drive; then
                flash_image_to_drive "$DEFAULT_LUBUNTU" "$SELECTED_DEV" "$LUBUNTU_NAME"
            fi
            ;;
        2)
            get_ram_info
            if [ "$FREE_RAM" -lt 4500 ]; then
                echo -e "${YELLOW}Warning: Lubuntu Desktop ISO is ~3.8 GB. You have ${FREE_RAM} MB free RAM.${RESET}"
                echo -e "Storing a 3.8 GB ISO in RAM might cause an Out-Of-Memory freeze on low-RAM systems."
                echo -e "Consider using Option [1] (Flash directly to drive)."
                echo -n "Proceed anyway? (y/N): "
                read -r proceed
                [ "$proceed" != "y" ] && [ "$proceed" != "Y" ] && return
            fi

            echo -e "\nEnter Lubuntu ISO direct download URL:"
            echo -e "Default: ${CYAN}$DEFAULT_LUBUNTU${RESET}"
            echo -n "Press Enter to use default or paste custom URL: "
            read -r iso_url
            [ -z "$iso_url" ] && iso_url="$DEFAULT_LUBUNTU"

            echo -e "\n${GREEN}Downloading ${LUBUNTU_NAME} into RAM (/tmp/lubuntu.iso)...${RESET}"
            rm -f /tmp/lubuntu.iso
            curl -# -f -L -o /tmp/lubuntu.iso "$iso_url"

            if [ -s /tmp/lubuntu.iso ]; then
                rm -rf /tmp/lubuntu_extracted
                if extract_iso_assets "/tmp/lubuntu.iso" "/tmp/lubuntu_extracted"; then
                    k_file=$(find /tmp/lubuntu_extracted -type f \( -iname "vmlinuz*" -o -iname "linux*" -o -iname "bzImage*" \) 2>/dev/null | head -n1)
                    i_file=$(find /tmp/lubuntu_extracted -type f \( -iname "initrd*" -o -iname "initramfs*" \) 2>/dev/null | head -n1)

                    if [ -n "$k_file" ]; then
                        boot_kexec "$k_file" "$i_file" "boot=casper toram iso-scan/filename=/tmp/lubuntu.iso quiet splash"
                    else
                        echo -e "${RED}Could not locate kernel inside Lubuntu ISO!${RESET}"
                        read -r _
                    fi
                fi
            else
                echo -e "${RED}Download failed or server returned an error!${RESET}"
                read -r _
            fi
            ;;
        3)
            echo -e "${GREEN}Downloading ${LUBUNTU_NAME} Netboot kernel & initrd (~45 MB)...${RESET}"
            curl -# -f -L -o /tmp/target_os/vmlinuz "$KERNEL_URL"
            curl -# -f -L -o /tmp/target_os/initrd.gz "$INITRD_URL"

            if [ -s /tmp/target_os/vmlinuz ] && [ -s /tmp/target_os/initrd.gz ]; then
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd.gz" "console=tty1 root=/dev/ram0 rw"
            else
                echo -e "${RED}Download failed. Please check network connection.${RESET}"
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
    echo -e "${YELLOW}=== Download & Boot Ubuntu (26.04 & 24.04 LTS) ===${RESET}\n"
    if ! check_internet; then
        setup_network
    fi

    mkdir -p /tmp/target_os
    cd /tmp/target_os || exit 1

    echo -e "${CYAN}Select Ubuntu Release:${RESET}"
    echo "  [1] Ubuntu 26.04 (Next-Gen Daily / Rolling Release)"
    echo "  [2] Ubuntu 24.04.5 LTS (Noble Numbat - Long Term Support)"
    echo "  [3] Back to Menu"
    echo ""
    echo -n "Select version [1-3]: "
    read -r ver_choice

    case "$ver_choice" in
        1)
            UBUNTU_NAME="Ubuntu 26.04 (Next-Gen Daily)"
            DEFAULT_URL="https://cdimage.ubuntu.com/daily-live/current/pending-desktop-amd64.iso"
            KERNEL_URL="https://cloud-images.ubuntu.com/daily/server/current/unpacked/vmlinuz-generic"
            INITRD_URL="https://cloud-images.ubuntu.com/daily/server/current/unpacked/initrd-generic"
            ;;
        2)
            UBUNTU_NAME="Ubuntu 24.04.5.1 LTS Desktop"
            DEFAULT_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.5.1-desktop-amd64.iso"
            KERNEL_URL="https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-vmlinuz-generic"
            INITRD_URL="https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-initrd-generic"
            ;;
        *)
            return
            ;;
    esac

    echo -e "\n${CYAN}Choose Mode for ${UBUNTU_NAME}:${RESET}"
    echo "  [1] Flash Live Desktop ISO directly to Hard Drive / SSD (Recommended for install)"
    echo "  [2] Live Desktop ISO to RAM (~5.8 GB ISO in DRAM - needs >= 7 GB RAM)"
    echo "  [3] Minimal Netboot Installer (~45-50 MB - installs over internet in DRAM)"
    echo "  [4] Back"
    echo ""
    echo -n "Choice [1-4]: "
    read -r ub_choice

    case "$ub_choice" in
        1)
            echo -e "\n${CYAN}Flash ${UBUNTU_NAME} directly to storage drive:${RESET}"
            if select_target_drive; then
                flash_image_to_drive "$DEFAULT_URL" "$SELECTED_DEV" "$UBUNTU_NAME"
            fi
            ;;
        2)
            get_ram_info
            if [ "$FREE_RAM" -lt 6500 ]; then
                echo -e "${YELLOW}Warning: Ubuntu Desktop ISO is ~5.8 GB. You have ${FREE_RAM} MB free RAM.${RESET}"
                echo -e "Storing a 5.8 GB ISO in RAM might cause an Out-Of-Memory freeze on low-RAM systems."
                echo -e "Consider using Option [1] (Flash directly to disk)."
                echo -n "Proceed anyway? (y/N): "
                read -r proceed
                [ "$proceed" != "y" ] && [ "$proceed" != "Y" ] && return
            fi

            echo -e "\nEnter Ubuntu Desktop ISO direct URL (or press Enter for default):"
            echo -e "Default: ${CYAN}$DEFAULT_URL${RESET}"
            echo -n "URL: "
            read -r custom_url
            [ -z "$custom_url" ] && custom_url="$DEFAULT_URL"

            rm -f /tmp/ubuntu.iso
            echo -e "\n${GREEN}Downloading ${UBUNTU_NAME} into RAM (/tmp/ubuntu.iso)...${RESET}"
            curl -# -f -L -o /tmp/ubuntu.iso "$custom_url"
            if [ -s /tmp/ubuntu.iso ]; then
                rm -rf /tmp/ubuntu_extracted
                if extract_iso_assets "/tmp/ubuntu.iso" "/tmp/ubuntu_extracted"; then
                    k_file=$(find /tmp/ubuntu_extracted -type f \( -iname "vmlinuz*" -o -iname "linux*" -o -iname "bzImage*" \) 2>/dev/null | head -n1)
                    i_file=$(find /tmp/ubuntu_extracted -type f \( -iname "initrd*" -o -iname "initramfs*" \) 2>/dev/null | head -n1)

                    if [ -n "$k_file" ]; then
                        boot_kexec "$k_file" "$i_file" "boot=casper toram iso-scan/filename=/tmp/ubuntu.iso quiet splash"
                    fi
                fi
            else
                echo -e "${RED}Download failed or server returned an error!${RESET}"
                read -r _
            fi
            ;;
        3)
            echo -e "${GREEN}Downloading ${UBUNTU_NAME} Netboot kernel & initrd (~45-50 MB)...${RESET}"
            curl -# -f -L -o /tmp/target_os/vmlinuz "$KERNEL_URL"
            curl -# -f -L -o /tmp/target_os/initrd "$INITRD_URL"
            if [ -s /tmp/target_os/vmlinuz ] && [ -s /tmp/target_os/initrd ]; then
                boot_kexec "/tmp/target_os/vmlinuz" "/tmp/target_os/initrd" "console=tty1 root=/dev/ram0 rw"
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

online_netboot_menu() {
    show_banner
    echo -e "${YELLOW}=== Online OS Netboot Installers (Direct DRAM Boot) ===${RESET}\n"
    if ! check_internet; then
        echo -e "${RED}Network is not ready! Setting up network first...${RESET}"
        setup_network
    fi

    echo -e "Select an official online netboot installer to boot directly in RAM:"
    echo -e "  ${GREEN}[1]${RESET} Debian 12 (Bookworm) Netboot Installer (~40 MB - Fast)"
    echo -e "  ${GREEN}[2]${RESET} Alpine Linux Live Netboot (~15 MB - Ultra-lightweight)"
    echo -e "  ${GREEN}[3]${RESET} Ubuntu 26.04 (Next-Gen Daily) Minimal Netboot (~50 MB)"
    echo -e "  ${GREEN}[4]${RESET} Ubuntu 24.04 LTS Minimal Netboot (~65 MB)"
    echo -e "  ${GREEN}[5]${RESET} Back to Menu"
    echo ""
    echo -n "Select option [1-5]: "
    read -r nb_choice

    mkdir -p /tmp/netboot
    case "$nb_choice" in
        1)
            echo -e "\n${GREEN}Downloading Debian 12 Bookworm Netboot Installer...${RESET}"
            curl -L -o /tmp/netboot/vmlinuz "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux"
            curl -L -o /tmp/netboot/initrd.gz "http://ftp.debian.org/debian/dists/bookworm/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz"
            if [ -s /tmp/netboot/vmlinuz ] && [ -s /tmp/netboot/initrd.gz ]; then
                boot_kexec "/tmp/netboot/vmlinuz" "/tmp/netboot/initrd.gz" "priority=low console=tty1"
            else
                echo -e "${RED}Download failed!${RESET}"
                read -r _
            fi
            ;;
        2)
            echo -e "\n${GREEN}Downloading Alpine Linux Netboot Assets...${RESET}"
            curl -L -o /tmp/netboot/vmlinuz "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/netboot/vmlinuz-lts"
            curl -L -o /tmp/netboot/initrd.gz "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/netboot/initramfs-lts"
            if [ -s /tmp/netboot/vmlinuz ] && [ -s /tmp/netboot/initrd.gz ]; then
                boot_kexec "/tmp/netboot/vmlinuz" "/tmp/netboot/initrd.gz" "alpine_repo=https://dl-cdn.alpinelinux.org/alpine/v3.20/main modules=loop,squashfs console=tty1"
            else
                echo -e "${RED}Download failed!${RESET}"
                read -r _
            fi
            ;;
        3)
            echo -e "\n${GREEN}Downloading Ubuntu 26.04 (Next-Gen Daily) Netboot Installer...${RESET}"
            curl -L -o /tmp/netboot/vmlinuz "https://cloud-images.ubuntu.com/daily/server/current/unpacked/vmlinuz-generic"
            curl -L -o /tmp/netboot/initrd.gz "https://cloud-images.ubuntu.com/daily/server/current/unpacked/initrd-generic"
            if [ -s /tmp/netboot/vmlinuz ] && [ -s /tmp/netboot/initrd.gz ]; then
                boot_kexec "/tmp/netboot/vmlinuz" "/tmp/netboot/initrd.gz" "console=tty1 root=/dev/ram0 rw"
            else
                echo -e "${RED}Download failed!${RESET}"
                read -r _
            fi
            ;;
        4)
            echo -e "\n${GREEN}Downloading Ubuntu 24.04 LTS Netboot Installer...${RESET}"
            curl -L -o /tmp/netboot/vmlinuz "https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-vmlinuz-generic"
            curl -L -o /tmp/netboot/initrd.gz "https://cloud-images.ubuntu.com/releases/noble/release/unpacked/ubuntu-24.04-server-cloudimg-amd64-initrd-generic"
            if [ -s /tmp/netboot/vmlinuz ] && [ -s /tmp/netboot/initrd.gz ]; then
                boot_kexec "/tmp/netboot/vmlinuz" "/tmp/netboot/initrd.gz" "console=tty1 root=/dev/ram0 rw"
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

flash_drive_utility() {
    show_banner
    echo -e "${YELLOW}=== Flash OS Image to Internal Drive / SSD ===${RESET}\n"
    echo -e "${RED}${BOLD}WARNING: Writing an image will ERASE the target drive!${RESET}\n"

    # Step 1: Select target storage drive
    if ! select_target_drive; then
        echo -e "${YELLOW}Aborted drive selection.${RESET}"
        read -r _
        return
    fi
    target_drive="$SELECTED_DEV"

    # Step 2: Select image source
    echo -e "\n${CYAN}Selected Target Drive:${RESET} ${BOLD}${target_drive}${RESET}"
    echo -e "${CYAN}Choose Image Source:${RESET}"
    echo -e "  [${GREEN}1${RESET}] From GitHub Repository Release (e.g. i2qq/BootOS)"
    echo -e "  [${GREEN}2${RESET}] From Direct Download URL (ISO or IMG)"

    local_isos=$(ls /tmp/*.iso /tmp/*.img 2>/dev/null || true)
    if [ -n "$local_isos" ]; then
        echo -e "  [${GREEN}3${RESET}] Use already downloaded ISO in RAM (/tmp)"
    fi
    echo -e "  [${GREEN}4${RESET}] Back to Menu"
    echo ""
    echo -n "Select source [1-4]: "
    read -r src_choice

    case "$src_choice" in
        1)
            echo -e "
Enter GitHub repository or release URL (e.g. ${CYAN}i2qq/BootOS${RESET}):"
            echo -n "Repo: "
            read -r gh_input
            if [ -z "$gh_input" ]; then
                echo "Aborted."
                read -r _
                return
            fi
            if resolve_github_release_assets "$gh_input"; then
                flash_image_to_drive "$GH_SELECTED_URL" "$target_drive" "$GH_SELECTED_NAME"
            else
                read -r _
            fi
            ;;
        2)
            echo -e "\nEnter direct URL of the ISO image (or GitHub URL):"
            read -r iso_url
            if [ -z "$iso_url" ]; then
                echo "Aborted."
                read -r _
                return
            fi

            # Auto-detect if user entered a GitHub URL instead of direct ISO URL
            if echo "$iso_url" | grep -qE "(github\.com|^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$)"; then
                echo -e "${CYAN}Detected GitHub Repository! Querying release assets...${RESET}"
                if resolve_github_release_assets "$iso_url"; then
                    flash_image_to_drive "$GH_SELECTED_URL" "$target_drive" "$GH_SELECTED_NAME"
                else
                    read -r _
                fi
            else
                flash_image_to_drive "$iso_url" "$target_drive" "Direct Download Image"
            fi
            ;;
        3)
            if [ -n "$local_isos" ]; then
                echo -e "\n${CYAN}Available local images in RAM:${RESET}"
                l_idx=1
                for f in $local_isos; do
                    sz=$(ls -lh "$f" | awk '{print $5}')
                    echo -e "  [${GREEN}$l_idx${RESET}] $f ($sz)"
                    l_idx=$((l_idx + 1))
                done
                echo -n "Select file [1-$((l_idx - 1))]: "
                read -r l_choice
                chosen_iso=$(echo "$local_isos" | sed -n "${l_choice}p")
                if [ -n "$chosen_iso" ] && [ -f "$chosen_iso" ]; then
                    flash_image_to_drive "$chosen_iso" "$target_drive" "$(basename "$chosen_iso")"
                else
                    echo -e "${RED}Invalid selection!${RESET}"
                    read -r _
                fi
            else
                return
            fi
            ;;
        *)
            return
            ;;
    esac
}

launch_file_explorer() {
    show_banner
    echo -e "${YELLOW}=== Launch BootOS File Explorer (Native Desktop App) ===${RESET}\n"
    echo -e "${GREEN}Starting BootOS File Explorer...${RESET}"
    echo "Tip: Pure native desktop app (Python 3 & Tk/X11) with instant launch, tabs, drive meters, and real file operations."
    echo "Click Close ([X]) or press Alt+F4 to return to BootOS."
    sleep 0.5

    if [ -x /usr/local/bin/explorer ]; then
        /usr/local/bin/explorer
    elif [ -f /usr/local/bin/bootos_explorer.py ]; then
        python3 /usr/local/bin/bootos_explorer.py
    else
        echo -e "${RED}File Explorer executable not found!${RESET}"
        sleep 2
    fi
}

launch_browser() {
    show_banner
    echo -e "${YELLOW}=== Launch Chromium Web Browser (GUI) ===${RESET}\n"
    if ! check_internet; then
        echo -e "${YELLOW}Notice: Network is not connected yet.${RESET}"
        echo -n "Would you like to configure network before opening browser? (Y/n): "
        read -r net_choice
        if [ "$net_choice" != "n" ] && [ "$net_choice" != "N" ]; then
            setup_network
        fi
    fi

    echo -e "Enter URL to open (or press Enter for default):"
    echo -e "Default: ${CYAN}https://google.com${RESET}"
    echo -n "URL: "
    read -r user_url
    [ -z "$user_url" ] && user_url="https://google.com"

    case "$user_url" in
        http://*|https://*|file://*|about:*|chrome:*) ;;
        *) user_url="https://$user_url" ;;
    esac

    echo -e "\n${GREEN}Launching Chromium...${RESET}"
    echo "Tip: Click the kill ([X]) or minus ([-]) button (or press Alt+F4) to return to BootOS."
    sleep 1

    if [ -x /usr/local/bin/browser ]; then
        /usr/local/bin/browser "$user_url"
    elif command -v browser >/dev/null 2>&1; then
        browser "$user_url"
    else
        echo -e "${RED}Error: Browser launcher (/usr/local/bin/browser) not found!${RESET}"
        read -r _
    fi
}

save_persistent_state() {
    mode="$1"  # "auto" or empty/interactive

    if [ "$mode" != "auto" ]; then
        show_banner
        echo -e "${YELLOW}=== Save Persistent State to Storage Drive ===${RESET}\n"
        echo -e "Persists configurations, Wi-Fi keys, browser history/bookmarks, and"
        echo -e "downloaded files across system restarts.\n"
    fi

    target_part=""
    if [ -f /etc/bootos_persist_dev ]; then
        saved_dev=$(cat /etc/bootos_persist_dev 2>/dev/null | tr -d '\r\n ')
        if [ -b "$saved_dev" ]; then
            target_part="$saved_dev"
        fi
    fi

    # In auto mode (e.g. called automatically from reboot):
    if [ "$mode" = "auto" ]; then
        if [ -n "$target_part" ]; then
            echo -e "${CYAN}Auto-saving persistent state to ${BOLD}$target_part${RESET}...${RESET}"
        else
            echo -e "${YELLOW}Notice: Persistence drive not configured yet.${RESET}"
            echo -n "Would you like to select a drive to save changes before rebooting? (y/N): "
            read -r auto_choice
            if [ "$auto_choice" != "y" ] && [ "$auto_choice" != "Y" ]; then
                return 0
            fi
        fi
    fi

    # If target_part not set or user wants to re-select
    if [ -z "$target_part" ]; then
        echo -e "${CYAN}Scanning for available storage partitions...${RESET}"
        p_list=$(lsblk -rnpo NAME,SIZE,TYPE,FSTYPE,LABEL 2>/dev/null | awk '$3=="part" {print $1 "|" $2 "|" $4 "|" $5}')

        if [ -z "$p_list" ]; then
            # No partitions exist. Check for whole disks.
            echo -e "${YELLOW}No existing partitions found. Checking raw disks...${RESET}"
            if select_target_drive; then
                raw_disk="$SELECTED_DEV"
                echo -e "\n${YELLOW}Would you like to initialize a persistent ext4 partition on ${BOLD}$raw_disk${RESET}?${RESET}"
                echo -e "${RED}Warning: This creates an MBR partition table and ext4 filesystem on $raw_disk!${RESET}"
                echo -n "Initialize persistence partition on $raw_disk? (y/N): "
                read -r init_ans
                if [ "$init_ans" = "y" ] || [ "$init_ans" = "Y" ]; then
                    echo -e "${CYAN}Creating partition and formatting ext4 on $raw_disk...${RESET}"
                    parted -s "$raw_disk" mklabel msdos mkpart primary ext4 1MiB 100% 2>/dev/null || true
                    partprobe "$raw_disk" 2>/dev/null || true
                    sleep 1
                    target_part="${raw_disk}1"
                    [ -b "${raw_disk}p1" ] && target_part="${raw_disk}p1"
                    mkfs.ext4 -F -L "BOOTOS_DATA" "$target_part" 2>/dev/null || true
                else
                    echo "Persistence save cancelled."
                    sleep 1
                    return 0
                fi
            else
                echo -e "${RED}No storage devices available!${RESET}"
                [ "$mode" != "auto" ] && { echo "Press Enter to return..."; read -r _; }
                return 1
            fi
        else
            echo -e "\n${CYAN}Detected Storage Partitions:${RESET}"
            p_count=$(echo "$p_list" | wc -l)
            i=1
            echo "$p_list" | while IFS='|' read -r pname psize pfstype plabel; do
                echo -e "  [${GREEN}$i${RESET}] ${BOLD}$pname${RESET} ($psize, fstype: ${pfstype:-unformatted}, label: ${plabel:-none})"
                i=$((i + 1))
            done

            echo ""
            echo -n "Select partition for BootOS persistence [1-$p_count] (or 0 to cancel): "
            read -r p_choice
            [ -z "$p_choice" ] && p_choice="1"
            if [ "$p_choice" = "0" ]; then
                echo "Cancelled."
                sleep 1
                return 0
            fi

            target_part=$(echo "$p_list" | sed -n "${p_choice}p" | cut -d'|' -f1)
            fstype=$(echo "$p_list" | sed -n "${p_choice}p" | cut -d'|' -f3)

            if [ ! -b "$target_part" ]; then
                echo -e "${RED}Invalid partition selection!${RESET}"
                [ "$mode" != "auto" ] && { echo "Press Enter to return..."; read -r _; }
                return 1
            fi

            # Format if unformatted
            if [ -z "$fstype" ]; then
                echo -e "\n${YELLOW}Partition $target_part is unformatted.${RESET}"
                echo -n "Format as ext4 with label BOOTOS_DATA? (y/N): "
                read -r fmt_ans
                if [ "$fmt_ans" = "y" ] || [ "$fmt_ans" = "Y" ]; then
                    mkfs.ext4 -F -L "BOOTOS_DATA" "$target_part" 2>/dev/null || true
                else
                    return 1
                fi
            fi
        fi
    fi

    # Mount target partition
    mnt_target="/tmp/persist_mnt_$$"
    mkdir -p "$mnt_target"
    if ! mount "$target_part" "$mnt_target" 2>/dev/null; then
        mount -t ext4 "$target_part" "$mnt_target" 2>/dev/null || \
        mount -t vfat "$target_part" "$mnt_target" 2>/dev/null || true
    fi

    if ! mountpoint -q "$mnt_target"; then
        echo -e "${RED}Error: Failed to mount $target_part!${RESET}"
        rm -rf "$mnt_target"
        [ "$mode" != "auto" ] && { echo "Press Enter to return..."; read -r _; }
        return 1
    fi

    echo -e "${CYAN}Creating BootOS persistence archive...${RESET}"
    mkdir -p /etc
    echo "$target_part" > /etc/bootos_persist_dev
    mkdir -p "$mnt_target/bootos"

    # Save /root (config, browser bookmarks, sessions, history), network, hosts
    tar --exclude='root/.cache' \
        --exclude='root/.local/share/Trash' \
        -czf "$mnt_target/bootos-persist.tgz" \
        -C / \
        root \
        etc/wpa_supplicant.conf \
        etc/resolv.conf \
        etc/network \
        etc/hosts \
        etc/hostname \
        etc/bootos_persist_dev \
        2>/dev/null || \
    tar -czf "$mnt_target/bootos-persist.tgz" \
        -C / \
        root \
        etc/resolv.conf \
        etc/bootos_persist_dev \
        2>/dev/null || true

    # Mirror copy in bootos directory
    cp "$mnt_target/bootos-persist.tgz" "$mnt_target/bootos/bootos-persist.tgz" 2>/dev/null || true

    cat <<EOF > "$mnt_target/bootos/bootos-persist.info"
SavedAt: $(date)
Device: $target_part
Kernel: $(uname -r)
BootOS: Persistent State
EOF

    sync
    umount "$mnt_target" 2>/dev/null || true
    rm -rf "$mnt_target"

    echo -e "\n${GREEN}✓ Persistence successfully saved to ${BOLD}${target_part}${RESET}${GREEN}!${RESET}"
    echo -e "${GREEN}All changes will automatically restore into DRAM on restart.${RESET}"
    if [ "$mode" != "auto" ]; then
        echo -e "\nPress Enter to continue..."
        read -r _
    else
        sleep 1
    fi
    return 0
}

# Main Loop
while true; do
    show_banner
    echo -e " ${BOLD}Main Menu:${RESET}"
    echo -e "  ${GREEN}[1]${RESET} ${BOLD}Install / Boot OS from GitHub Release ISO${RESET}"
    echo -e "  ${GREEN}[2]${RESET} ${BOLD}Launch BootOS File Explorer (GUI)${RESET}"
    echo -e "  ${GREEN}[3]${RESET} Download & Boot Lubuntu (26.04 & 24.04 LTS)"
    echo -e "  ${GREEN}[4]${RESET} Download & Boot Ubuntu (26.04 & 24.04 LTS)"
    echo -e "  ${GREEN}[5]${RESET} ${BOLD}Launch Chromium Web Browser (GUI)${RESET}"
    echo -e "  ${GREEN}[6]${RESET} Flash Downloaded ISO to Internal Hard Drive / SSD"
    echo -e "  ${GREEN}[7]${RESET} Download & Boot Custom Kernel/Initrd"
    echo -e "  ${GREEN}[8]${RESET} Setup Network (Ethernet DHCP / Diagnostics)"
    echo -e "  ${GREEN}[9]${RESET} Online OS Netboot Installers (Debian / Alpine / Ubuntu in DRAM)"
    echo -e "  ${GREEN}[10]${RESET} ${BOLD}Open Root Terminal Shell (GNU Bash, sudo, Coreutils)${RESET}"
    echo -e "  ${GREEN}[11]${RESET} ${BOLD}Save Persistent State to Storage Drive${RESET}"
    echo -e "  ${GREEN}[12]${RESET} ${BOLD}Reboot System (Auto-Saves to Disk)${RESET}"
    echo -e "  ${GREEN}[13]${RESET} Power Off"
    echo ""
    echo -n " Please select an option [1-13]: "
    read -r choice

    case "$choice" in
        1|"0"|"gh"|"github") github_release_os_installer ;;
        2|"explorer"|"files") launch_file_explorer ;;
        3) download_and_boot_lubuntu ;;
        4) download_and_boot_ubuntu ;;
        5|"browser"|"chromium"|"web") launch_browser ;;
        6) flash_drive_utility ;;
        7) custom_os_downloader ;;
        8|"net"|"network") setup_network ;;
        9) online_netboot_menu ;;
        10|"sh"|"shell"|"bash")
            echo -e "\n${CYAN}======================================================${RESET}"
            echo -e " ${BOLD}BootOS Root Terminal Shell (GNU Bash)${RESET}"
            echo -e " Full Shell Commands: ${GREEN}sudo${RESET}, ${GREEN}echo${RESET}, ${GREEN}mkdir${RESET}, ${GREEN}touch${RESET}, ${GREEN}cat${RESET}, ${GREEN}nano${RESET}, ${GREEN}grep${RESET}"
            echo -e " Utilities: chromium, browser, curl, wget, 7z, kexec, fdisk, parted, lsblk, ip"
            echo -e " Type '${YELLOW}exit${RESET}' or '${YELLOW}menu${RESET}' to return to the BootOS menu."
            echo -e "${CYAN}======================================================${RESET}\n"
            if [ -x /bin/bash ]; then
                BOOTOS_SHELL=1 HOME=/root USER=root SHELL=/bin/bash /bin/bash -i
            elif command -v cttyhack >/dev/null 2>&1; then
                setsid cttyhack /bin/sh
            else
                PS1='bootos:\w# ' /bin/sh -i
            fi
            echo -e "\nReturning to menu..."
            sleep 1
            ;;
        11|"save"|"persist") save_persistent_state ;;
        12|"reboot")
            echo -e "\n${YELLOW}Preparing to reboot...${RESET}"
            save_persistent_state "auto"
            echo -e "${YELLOW}Rebooting system...${RESET}"
            sync
            echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
            busybox reboot -f 2>/dev/null || reboot -f 2>/dev/null || echo b > /proc/sysrq-trigger
            ;;
        13|"poweroff"|"shutdown")
            echo -e "\n${YELLOW}Shutting down...${RESET}"
            sync
            echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
            busybox poweroff -f 2>/dev/null || poweroff -f 2>/dev/null || echo o > /proc/sysrq-trigger
            ;;
        *)
            echo -e "\n${RED}Invalid option!${RESET}"
            sleep 1
            ;;
    esac
done
