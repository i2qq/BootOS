#!/bin/sh
# ==============================================================================
# BootOS Partition Wizard & Volume Manager Desktop Launcher
# ==============================================================================
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
export DISPLAY="${DISPLAY:-:0}"
mkdir -p /tmp/.X11-unix /run/user/0 /run/udev /root/.config/openbox /var/log /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0

# Ensure udev daemon is active & coldplug devices are recognized for Xorg input
if [ -x /sbin/udevd ] || command -v udevd >/dev/null 2>&1; then
    if ! pgrep -x udevd >/dev/null 2>&1; then
        /sbin/udevd --daemon 2>/dev/null || udevd --daemon 2>/dev/null || true
        udevadm trigger --action=add 2>/dev/null || true
        udevadm settle --timeout=2 2>/dev/null || true
    fi
fi

# Explicitly probe input and display drivers
for mod in psmouse mousedev evdev uinput i8042 usbhid hid hid-generic vmmouse radeon amdgpu i915; do
    modprobe "$mod" 2>/dev/null || true
done
mdev -s 2>/dev/null || true

PM_SCRIPT="/usr/local/bin/bootos_partition_manager.py"
if [ ! -f "$PM_SCRIPT" ] && [ -f "$(dirname "$0")/bootos_partition_manager.py" ]; then
    PM_SCRIPT="$(cd "$(dirname "$0")" && pwd)/bootos_partition_manager.py"
fi

# 1. If Xorg already active, launch GUI directly
if pgrep -x Xorg >/dev/null 2>&1; then
    exec python3 "$PM_SCRIPT" "$@"
fi

# 2. If Xorg not active, start with Openbox
cat <<'EOF' > /root/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <theme>
    <titleLayout>NLIMC</titleLayout>
  </theme>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <context name="Close">
      <mousebind button="Left" action="Click">
        <action name="Close"/>
      </mousebind>
    </context>
  </mouse>
  <keyboard>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
  </keyboard>
  <applications>
    <application class="*">
      <maximized>true</maximized>
      <decor>yes</decor>
    </application>
  </applications>
</openbox_config>
EOF

cat <<EOF > /root/.xinitrc
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
xsetroot -cursor_name left_ptr -solid "#191919" 2>/dev/null || true
xrandr --auto 2>/dev/null || true

# Set UK keyboard layout with US fallback (safely via setxkbmap)
if command -v setxkbmap >/dev/null 2>&1; then
    setxkbmap -layout "gb,us" 2>/dev/null || setxkbmap gb 2>/dev/null || true
fi

# Map backtick key to pipe | and UK ISO key (keycode 94) to \ and |
if command -v xmodmap >/dev/null 2>&1; then
    xmodmap -e "keycode 94 = backslash bar backslash bar bar brokenbar" 2>/dev/null || true
    xmodmap -e "keysym grave = bar asciitilde bar asciitilde" 2>/dev/null || true
    # Restore mouse pointer mapping to default so mouse movements and clicks are 100% responsive
    xmodmap -e "pointer = default" 2>/dev/null || true
fi

# Start Openbox
openbox &

# Launch Partition Wizard & Volume Manager
python3 "$PM_SCRIPT"

# Clean exit
openbox --exit 2>/dev/null || true
pkill -9 -x openbox 2>/dev/null || true
pkill -9 -f "$PM_SCRIPT" 2>/dev/null || true
pkill -9 -x Xorg 2>/dev/null || true
EOF

echo "--> Launching BootOS Partition Wizard & Volume Manager..."
xinit /root/.xinitrc -- :0 >/tmp/xorg.log 2>&1

# Bulletproof console and keyboard recovery
pkill -9 -x openbox 2>/dev/null || true
pkill -9 -f bootos_partition_manager 2>/dev/null || true
pkill -9 -x Xorg 2>/dev/null || true
sleep 0.2
chvt 1 2>/dev/null || true
kbd_mode -a -C /dev/tty1 2>/dev/null || kbd_mode -a 2>/dev/null || true
stty -F /dev/tty1 sane 2>/dev/null || stty sane 2>/dev/null || true
stty -F /dev/tty1 echo icanon 2>/dev/null || true
printf "\033c\033[?25h" > /dev/tty1 2>/dev/null || true
printf "\033c\033[?25h" 2>/dev/null || true
clear 2>/dev/null || printf "\033[2J\033[1;1H"
