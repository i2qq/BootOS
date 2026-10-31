#!/bin/sh
# ==============================================================================
# BootOS Chromium Launcher
# ==============================================================================
# Launches Chromium in a lightweight Openbox/Xorg session without desktop bloat.
# ==============================================================================

TARGET_URL="${1:-https://google.com}"

# Ensure URL has protocol scheme
case "$TARGET_URL" in
    http://*|https://*|file://*|about:*|chrome:*) ;;
    *) TARGET_URL="https://$TARGET_URL" ;;
esac

# 1. Setup required runtime directories
mkdir -p /tmp/.X11-unix /run/user/0 /root/.config/chromium /root/.config/openbox /var/log
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
export DISPLAY=:0

# 2. Setup DBus machine-id
[ -f /var/lib/dbus/machine-id ] || dbus-uuidgen --ensure 2>/dev/null || true
[ -f /etc/machine-id ] || dbus-uuidgen --ensure /etc/machine-id 2>/dev/null || true

# 3. Create Openbox configuration
cat <<'EOF' > /root/.config/openbox/rc.xml
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <placement>
    <policy>Smart</policy>
  </placement>
  <applications>
    <application class="*">
      <maximized>true</maximized>
      <decor>yes</decor>
    </application>
  </applications>
</openbox_config>
EOF

# 4. Generate .xinitrc session script
cat <<EOF > /root/.xinitrc
# Standard X mouse cursor and dark background
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
    "$TARGET_URL"
EOF

echo "Starting graphical display and Chromium browser..."
echo "Close the Chromium window or press Alt+F4 to return to BootOS."
xinit /root/.xinitrc -- :0 -novtswitch >/tmp/xorg.log 2>&1

echo "Chromium closed. Returning to terminal..."
sleep 1
