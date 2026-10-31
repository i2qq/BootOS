#!/bin/sh
# ==============================================================================
# BootOS Windows 11 File Explorer Launcher
# ==============================================================================
# Starts the backend filesystem server and launches the Windows 11 Fluent UI
# File Explorer in an accelerated GUI window.
# ==============================================================================

SERVER_DIR="/usr/local/share/bootos-explorer"
if [ ! -d "$SERVER_DIR" ] && [ -d "$(dirname "$0")/explorer" ]; then
    SERVER_DIR="$(cd "$(dirname "$0")/explorer" && pwd)"
fi

# 1. Start Python 3 Explorer Server if not already active
if ! pgrep -f "bootos-explorer/server.py" >/dev/null 2>&1 && ! pgrep -f "src/explorer/server.py" >/dev/null 2>&1; then
    echo "--> Starting BootOS File Explorer backend server..."
    python3 "${SERVER_DIR}/server.py" >/tmp/explorer-server.log 2>&1 &
    sleep 0.8
fi

# 2. Wait up to 3 seconds for server to respond
COUNT=0
while [ $COUNT -lt 6 ]; do
    if curl -s http://127.0.0.1:54321/api/drives >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
    COUNT=$((COUNT + 1))
done

# 3. Setup runtime environment
mkdir -p /tmp/.X11-unix /run/user/0 /run/udev /root/.config/chromium /root/.config/openbox /var/log /etc/X11/xorg.conf.d
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/0
export XDG_RUNTIME_DIR=/run/user/0
export DISPLAY="${DISPLAY:-:0}"
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24

# 4. Probe input drivers
for mod in psmouse mousedev evdev i8042 usbhid hid_generic vmmouse; do
    modprobe "$mod" 2>/dev/null || true
done

# 5. Check if Xorg is already running
if pgrep -x Xorg >/dev/null 2>&1; then
    # X is running, launch Chromium directly into existing session
    exec chromium \
        --app=http://127.0.0.1:54321/ \
        --window-size=1180,760 \
        --user-data-dir=/root/.config/chromium-explorer \
        --no-first-run \
        --no-default-browser-check \
        --disable-translate \
        --disable-sync \
        --disable-features=Translate \
        --enable-features=OverlayScrollbar \
        --no-sandbox \
        --test-type \
        --class=BootOSExplorer \
        2>/dev/null
fi

# 6. X is not running, launch via xinit with Openbox
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
        <action name="Execute">
          <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
        </action>
      </mousebind>
    </context>
  </mouse>
  <keyboard>
    <keybind key="A-F4">
      <action name="Execute">
        <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
      </action>
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

cat <<'EOF' > /root/.xinitrc
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
xsetroot -cursor_name left_ptr -solid "#191919" 2>/dev/null || true

# Start Openbox in background
openbox &

# Launch File Explorer
chromium \
    --app=http://127.0.0.1:54321/ \
    --window-size=1180,760 \
    --user-data-dir=/root/.config/chromium-explorer \
    --no-first-run \
    --no-default-browser-check \
    --disable-translate \
    --disable-sync \
    --enable-features=OverlayScrollbar \
    --no-sandbox \
    --test-type \
    --class=BootOSExplorer \
    2>/dev/null

# Exit cleanly
openbox --exit 2>/dev/null || true
EOF

echo "--> Launching Windows 11 File Explorer GUI..."
xinit /root/.xinitrc -- /usr/bin/Xorg :0 vt1 -novtswitch -sharevts -s 0 -dpms 2>/dev/null || true

# Return cleanly to terminal
clear
echo "Returned from File Explorer to BootOS."
