#!/bin/sh
# ==============================================================================
# BootOS File Explorer Native Desktop Launcher
# ==============================================================================
export DISPLAY="${DISPLAY:-:0}"
mkdir -p /tmp/.X11-unix /run/user/0 /root/.config/openbox
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0

# 1. Probe input devices
for mod in psmouse mousedev evdev i8042 usbhid hid_generic vmmouse; do
    modprobe "$mod" 2>/dev/null || true
done

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

# Start Openbox
openbox &

# Launch pure native desktop application
python3 "$EXPLORER_SCRIPT"

# Clean exit
openbox --exit 2>/dev/null || true
EOF

echo "--> Launching BootOS File Explorer..."
xinit /root/.xinitrc -- :0 -novtswitch >/tmp/xorg.log 2>&1

chvt 1 2>/dev/null || true
clear
