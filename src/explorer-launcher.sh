#!/bin/sh
# ==============================================================================
# BootOS File Explorer Native Desktop Launcher
# ==============================================================================
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
export DISPLAY="${DISPLAY:-:0}"
# 1. Setup required runtime directories
mkdir -p /tmp/.X11-unix /run/user/0 /run/udev /root/.config/openbox /var/log /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0

# 2. Ensure udev daemon is active & coldplug devices are recognized for Xorg input
if [ -x /sbin/udevd ] || command -v udevd >/dev/null 2>&1; then
    if ! pgrep -x udevd >/dev/null 2>&1; then
        /sbin/udevd --daemon 2>/dev/null || udevd --daemon 2>/dev/null || true
        udevadm trigger --action=add 2>/dev/null || true
        udevadm settle --timeout=2 2>/dev/null || true
    fi
fi

# 3. Explicitly probe input and display drivers
for mod in psmouse mousedev evdev uinput i8042 usbhid hid hid-generic vmmouse vboxguest vboxvideo vboxsf radeon amdgpu i915; do
    modprobe "$mod" 2>/dev/null || true
done
mdev -s 2>/dev/null || true

# 4. Setup DBus machine-id
[ -f /var/lib/dbus/machine-id ] || dbus-uuidgen --ensure 2>/dev/null || true
[ -f /etc/machine-id ] || dbus-uuidgen --ensure /etc/machine-id 2>/dev/null || true

EXPLORER_SCRIPT="/usr/local/bin/bootos_explorer.py"
if [ ! -f "$EXPLORER_SCRIPT" ] && [ -f "$(dirname "$0")/bootos_explorer.py" ]; then
    EXPLORER_SCRIPT="$(cd "$(dirname "$0")" && pwd)/bootos_explorer.py"
fi

# 2. Check if Xorg is already active
if pgrep -x Xorg >/dev/null 2>&1; then
    exec python3 "$EXPLORER_SCRIPT"
fi

# 3. If Xorg not active, start with Openbox
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

# Auto-detect native display resolution
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

# Launch pure native desktop application
python3 "$EXPLORER_SCRIPT"

# Clean exit: ensure Openbox and any child processes terminate
openbox --exit 2>/dev/null || true
pkill -9 -x openbox 2>/dev/null || true
pkill -9 -f "$EXPLORER_SCRIPT" 2>/dev/null || true
pkill -9 -x Xorg 2>/dev/null || true
EOF

echo "--> Launching BootOS File Explorer..."
xinit /root/.xinitrc -- :0 >/tmp/xorg.log 2>&1

# Bulletproof console and keyboard recovery
pkill -9 -x openbox 2>/dev/null || true
pkill -9 -f bootos_explorer 2>/dev/null || true
pkill -9 -x Xorg 2>/dev/null || true
sleep 0.2
chvt 1 2>/dev/null || true
kbd_mode -a -C /dev/tty1 2>/dev/null || kbd_mode -a 2>/dev/null || true
stty -F /dev/tty1 sane 2>/dev/null || stty sane 2>/dev/null || true
stty -F /dev/tty1 echo icanon 2>/dev/null || true
printf "\033c\033[?25h" > /dev/tty1 2>/dev/null || true
printf "\033c\033[?25h" 2>/dev/null || true
clear 2>/dev/null || printf "\033[2J\033[1;1H"
