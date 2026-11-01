#!/bin/sh
# ==============================================================================
# BootOS Chromium Launcher
# ==============================================================================
# Launches Chromium in a lightweight Openbox/Xorg session with full mouse,
# keyboard, and hardware input acceleration.
#
# Pressing the Kill ([X]) or Minus ([-]) buttons immediately returns control
# back to the original BootOS terminal homescreen.
# ==============================================================================

TARGET_URL="${1:-https://google.com}"
TARGET_MODE="${2:-browser}"

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

# 3. Explicitly probe input, audio, and display drivers
for mod in psmouse mousedev evdev i8042 usbhid hid_generic vmmouse snd_hda_intel snd_hda_codec_realtek snd_hda_codec_hdmi snd_hda_codec_generic radeon amdgpu i915; do
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
  <theme>
    <titleLayout>NLIMC</titleLayout>
  </theme>
  <mouse>
    <dragThreshold>1</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>400</screenEdgeWarpTime>

    <!-- Close / Kill button: Close window and return to terminal -->
    <context name="Close">
      <mousebind button="Left" action="Click">
        <action name="Execute">
          <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
        </action>
      </mousebind>
    </context>

    <!-- Minus / Minimize button: Instantly return to terminal homescreen -->
    <context name="Iconify">
      <mousebind button="Left" action="Click">
        <action name="Execute">
          <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
        </action>
      </mousebind>
    </context>
  </mouse>
  <placement>
    <policy>Smart</policy>
  </placement>
  <keyboard>
    <keybind key="A-F4">
      <action name="Execute">
        <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
      </action>
    </keybind>
    <keybind key="C-q">
      <action name="Execute">
        <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
      </action>
    </keybind>
    <keybind key="A-minus">
      <action name="Execute">
        <command>sh -c "pkill -f chromium 2>/dev/null || openbox --exit"</command>
      </action>
    </keybind>
    <keybind key="W-d">
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

# 7. Write target URL and mode for session
echo "$TARGET_URL" > /tmp/chromium_target_url
echo "$TARGET_MODE" > /tmp/chromium_target_mode

# 8. Generate .xinitrc session script (quoted heredoc to preserve variables)
cat <<'EOF' > /root/.xinitrc
# Set default X11 cursor theme and shape
export XCURSOR_THEME=Adwaita
export XCURSOR_SIZE=24
xsetroot -cursor_name left_ptr -solid "#1e1e2e" 2>/dev/null || true

# Auto-detect native display resolution via RandR
xrandr --auto 2>/dev/null || true

# Unmute ALSA audio channels
if command -v amixer >/dev/null 2>&1; then
    amixer sset Master 90% unmute 2>/dev/null || true
    amixer sset PCM 90% unmute 2>/dev/null || true
    amixer sset Speaker 90% unmute 2>/dev/null || true
    amixer sset Headphone 90% unmute 2>/dev/null || true
    amixer sset Front 90% unmute 2>/dev/null || true
fi

# Start lightweight window manager
openbox &

# Watcher: if Chromium is closed OR minimized (minus button pressed),
# immediately terminate session and return to the BootOS terminal homescreen
(
    # Wait for Chromium window to appear
    for i in $(seq 1 50); do
        active=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')
        if [ -n "$active" ] && [ "$active" != "0x0" ]; then
            break
        fi
        sleep 0.2
    done
    sleep 0.5

    # Continuous monitor for minimization (minus button pressed)
    while true; do
        sleep 0.3
        if ! pgrep -f chromium >/dev/null 2>&1; then
            break
        fi

        active=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')
        if [ -z "$active" ] || [ "$active" = "0x0" ]; then
            # Window was minimized via minus button -> terminate session immediately
            pkill -TERM -f chromium 2>/dev/null || true
            pkill -9 -f chromium 2>/dev/null || true
            openbox --exit 2>/dev/null || true
            break
        fi

        if xprop -id "$active" _NET_WM_STATE 2>/dev/null | grep -q "_NET_WM_STATE_HIDDEN"; then
            # Window entered hidden/minimized state -> terminate session immediately
            pkill -TERM -f chromium 2>/dev/null || true
            pkill -9 -f chromium 2>/dev/null || true
            openbox --exit 2>/dev/null || true
            break
        fi
    done
) &

# Read target URL and mode
URL="https://google.com"
[ -f /tmp/chromium_target_url ] && URL=$(cat /tmp/chromium_target_url)

MODE="browser"
[ -f /tmp/chromium_target_mode ] && MODE=$(cat /tmp/chromium_target_mode)

EXTRA_FLAGS=""
if [ "$MODE" = "app" ]; then
    EXTRA_FLAGS="--app=$URL --window-size=1180,760"
else
    EXTRA_FLAGS="--start-maximized $URL"
fi

# Launch Chromium with robust hardware & container compatibility flags
exec dbus-run-session -- chromium \
    --no-sandbox \
    --test-type \
    --disable-gpu-sandbox \
    --disable-dev-shm-usage \
    --disable-software-rasterizer-warning \
    --force-device-scale-factor=1 \
    --audio-backend=alsa \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --enable-features=OverlayScrollbar \
    $EXTRA_FLAGS
EOF

echo "Starting graphical display and Chromium browser..."
echo "Tip: Click the kill ([X]) or minus ([-]) buttons to return to the BootOS homescreen."
xinit /root/.xinitrc -- :0 >/tmp/xorg.log 2>&1

# Return display to main TTY console
chvt 1 2>/dev/null || true
echo "Chromium closed. Returning to terminal homescreen..."
sleep 1
