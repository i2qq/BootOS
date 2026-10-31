#!/bin/sh
# ==============================================================================
# BootOS File Explorer Launcher
# ==============================================================================
# Starts the background Python 3 filesystem server and opens the BootOS
# File Explorer in native desktop app mode via the proven GUI subsystem.
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

# 3. Launch via the proven GUI browser subsystem in native app mode
if [ -x /usr/local/bin/browser ]; then
    exec /usr/local/bin/browser "http://127.0.0.1:54321/" "app"
elif [ -x "$(dirname "$0")/browser-launcher.sh" ]; then
    exec "$(dirname "$0")/browser-launcher.sh" "http://127.0.0.1:54321/" "app"
else
    echo "Error: GUI browser subsystem not found!"
    sleep 2
fi
