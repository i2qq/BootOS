#!/bin/sh
# ==============================================================================
# BootOS Chromium Launcher
# ==============================================================================
# Launches Chromium in a lightweight Openbox/Xorg session with full mouse,
# keyboard, and hardware input acceleration.
# ==============================================================================

TARGET_URL="${1:-https://google.com}"

# Ensure URL has protocol scheme
case "$TARGET_URL" in
    http://*|https://*|file://*|about:*|chrome:*) ;;
    *) TARGET_URL="https://$TARGET_URL" ;;
esac

# 1. Setup required runtime directories
mkdir -p /tmp/.X11-unix /run/user/0 /run/udev /root/.config/chromium /root/.config/openbox /var/log /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
export DISPLAY=:0
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24

# 2. Ensure udev daemon is active & coldplug devices are recognized for Xorg input
if command -v udevd >/dev/null 2>&1; then
    if ! pgrep -x udevd >/dev/null 2>&1; then
        udevd --daemon 2>/dev/null || true
        udevadm trigger --action=add 2>/dev/null || true
        udevadm settle --timeout=3 2>/dev/null || true
    fi
fi

# 3. Explicitly probe mouse and keyboard drivers
for mod in psmouse mousedev evdev i8042 usbhid hid_generic vmmouse; do
    modprobe "$mod" 2>/dev/null || true
done

# 4. Setup DBus machine-id
[ -f /var/lib/dbus/machine-id ] || dbus-uuidgen --ensure 2>/dev/null || true
[ -f /etc/machine-id ] || dbus-uuidgen --ensure /etc/machine-id 2>/dev/null || true

# 5. Write Xorg Input Configuration (libinput + vmmouse + evdev fallback)
cat <<'EOF' > /etc/X11/xorg.conf.d/10-input.conf
Section "ServerFlags"
    Option "AutoAddDevices" "true"
    Option "AutoEnableDevices" "true"
EndSection

Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Driver "libinput"
    Option "XkbLayout" "us"
EndSection

Section "InputClass"
    Identifier "system-mouse"
    MatchIsPointer "on"
    Driver "libinput"
EndSection

Section "InputClass"
    Identifier "vbox-mouse"
    MatchIsPointer "on"
    Driver "vmmouse"
EndSection

Section "InputClass"
    Identifier "fallback-evdev-pointer"
    MatchIsPointer "on"
    Driver "evdev"
EndSection

Section "InputClass"
    Identifier "fallback-evdev-keyboard"
    MatchIsKeyboard "on"
    Driver "evdev"
EndSection
EOF

# 6. Create Openbox configuration with mouse & window controls
cat <<'EOF' > /root/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>
  </mouse>
  <placement>
    <policy>Smart</policy>
  </placement>
  <keyboard>
    <keybind key="A-F4">
      <action name="Close"/>
    </keybind>
    <keybind key="C-q">
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

# 7. Generate .xinitrc session script
cat <<EOF > /root/.xinitrc
# Set default X11 cursor theme and shape
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
xsetroot -cursor_name left_ptr -solid "#1e1e2e" 2>/dev/null || true

# Start lightweight window manager
openbox &

# Launch Chromium with robust hardware & container compatibility flags
exec dbus-run-session -- chromium \
    --no-sandbox \
    --test-type \
    --disable-gpu-sandbox \
    --disable-dev-shm-usage \
    --disable-software-rasterizer-warning \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --start-maximized \
    --enable-features=OverlayScrollbar \
    "$TARGET_URL"
EOF

echo "Starting graphical display and Chromium browser..."
echo "Close the Chromium window or press Alt+F4 to return to BootOS."
xinit /root/.xinitrc -- :0 -novtswitch >/tmp/xorg.log 2>&1

# Return display to main TTY console
chvt 1 2>/dev/null || true
echo "Chromium closed. Returning to terminal..."
sleep 1
