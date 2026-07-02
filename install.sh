#!/usr/bin/env bash
#
# install.sh — Codespaces bootstrap for Play Store (web variant)
#
# Run this by hand instead of relying on the devcontainer's automatic
# postAttachCommand. One command does everything: installs dependencies,
# starts the virtual display + noVNC bridge on port 8000, then runs the
# SDK/emulator/Play Store pipeline.
#
# Usage (from wherever this file lives in your repo, in a Codespaces terminal):
#   chmod +x install.sh
#   ./install.sh
#
# Then watch this terminal for a URL, or open the "Ports" tab in VS Code
# and click the globe icon next to port 8000.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_PORT="${PLAYSTORE_WEB_PORT:-8000}"
LOG_FILE="$SCRIPT_DIR/playstore-web.log"

echo "== Play Store (Codespaces/web) installer =="
echo "Script dir: $SCRIPT_DIR"

# ---------------------------------------------------------------------
# 0. Locate playstore.py and playstore_web.py regardless of whether this
#    script sits at the repo root or inside a codespaces/ subfolder.
# ---------------------------------------------------------------------
if [ -f "$SCRIPT_DIR/playstore.py" ] && [ -f "$SCRIPT_DIR/playstore_web.py" ]; then
    # This script and both Python files are all in the same folder.
    REPO_ROOT="$SCRIPT_DIR"
    PLAYSTORE_WEB="$SCRIPT_DIR/playstore_web.py"
elif [ -f "$SCRIPT_DIR/playstore.py" ] && [ -f "$SCRIPT_DIR/codespaces/playstore_web.py" ]; then
    # Standard repo layout: this script at repo root, web script in codespaces/.
    REPO_ROOT="$SCRIPT_DIR"
    PLAYSTORE_WEB="$SCRIPT_DIR/codespaces/playstore_web.py"
elif [ -f "$SCRIPT_DIR/../playstore.py" ]; then
    # This script inside codespaces/, playstore.py one level up.
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    PLAYSTORE_WEB="$SCRIPT_DIR/playstore_web.py"
else
    echo "ERROR: Could not find playstore.py and playstore_web.py." >&2
    echo "Expected either:" >&2
    echo "  - playstore.py and playstore_web.py next to this script, or" >&2
    echo "  - playstore.py at the repo root with this script in codespaces/, or" >&2
    echo "  - playstore.py at the repo root with a codespaces/playstore_web.py" >&2
    echo "Re-check where you placed the project files and try again." >&2
    exit 1
fi
echo "Using playstore.py at: $REPO_ROOT/playstore.py"
echo "Using playstore_web.py at: $PLAYSTORE_WEB"

# ---------------------------------------------------------------------
# 1. System dependencies
# ---------------------------------------------------------------------
# - python3: runs playstore.py / playstore_web.py
# - openjdk-17-jre-headless: sdkmanager/avdmanager are Java tools
# - unzip, wget: fetch/extract the Android SDK Command-line Tools
# - xvfb, x11vnc: virtual display + VNC server (Codespaces has no GUI)
# - novnc, websockify: browser-based VNC client + web/WebSocket proxy,
#   so the emulator screen can be viewed over the forwarded port
echo "Installing required packages..."
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    python3 \
    openjdk-17-jre-headless \
    unzip \
    wget \
    ca-certificates \
    xvfb \
    x11vnc \
    novnc \
    websockify \
    libnss3 \
    libxcomposite1 \
    libxcursor1 \
    libxi6 \
    libxtst6 \
    || true
# libasound2's package name changed between Ubuntu releases; try both.
sudo apt-get install -y --no-install-recommends libasound2 \
    || sudo apt-get install -y --no-install-recommends libasound2t64 \
    || true

# Auto-connecting noVNC landing page (skips the "enter host/port" screen).
NOVNC_HTML="$(dpkg -L novnc 2>/dev/null | grep 'vnc\.html$' | head -1 || true)"
if [ -n "$NOVNC_HTML" ]; then
    NOVNC_DIR="$(dirname "$NOVNC_HTML")"
    sudo tee "$NOVNC_DIR/index.html" > /dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Play Store</title>
  <meta http-equiv="refresh" content="0; url=vnc.html?autoconnect=true&resize=scale&reconnect=true&reconnect_delay=2000">
</head>
<body>
  <p>Loading Play Store... if this doesn't redirect automatically,
  <a href="vnc.html?autoconnect=true&resize=scale">click here</a>.</p>
</body>
</html>
EOF
    echo "noVNC auto-connect page installed at $NOVNC_DIR/index.html"
else
    echo "Note: could not locate noVNC's install dir for an auto-connect page;"
    echo "you'll just need to click 'Connect' once you open the port."
fi

# ---------------------------------------------------------------------
# 2. Stop any previous run so re-running this script is safe
# ---------------------------------------------------------------------
echo "Stopping any previous Play Store processes..."
pkill -f "Xvfb :99"        2>/dev/null || true
pkill -f "x11vnc"           2>/dev/null || true
pkill -f "websockify"       2>/dev/null || true
pkill -f "playstore_web.py" 2>/dev/null || true
sleep 1

# ---------------------------------------------------------------------
# 3. Launch everything, fully detached from this terminal (setsid),
#    so closing the terminal or hitting Ctrl+C here doesn't kill it.
# ---------------------------------------------------------------------
echo "Starting Play Store in the background. Logging to: $LOG_FILE"
: > "$LOG_FILE"
cd "$REPO_ROOT"
PLAYSTORE_WEB_PORT="$WEB_PORT" setsid nohup python3 "$PLAYSTORE_WEB" \
    >> "$LOG_FILE" 2>&1 < /dev/null &
disown

echo
echo "Started. Tailing the log now (Ctrl+C stops watching, NOT the app)..."
echo

( tail -n +1 -f "$LOG_FILE" & TAIL_PID=$!; \
  for _ in $(seq 1 120); do \
    grep -q "Open this URL" "$LOG_FILE" 2>/dev/null && break; \
    sleep 1; \
  done; \
  sleep 1; kill "$TAIL_PID" 2>/dev/null ) || true

echo
echo "=================================================================="
echo "If you don't see a URL printed above, open the 'PORTS' tab in the"
echo "Codespaces UI, find port $WEB_PORT, and click the globe icon to"
echo "open it in your browser (set visibility to Public or Private if asked)."
echo
echo "To keep watching progress at any time:  tail -f $LOG_FILE"
echo "To stop everything:                     pkill -f playstore_web.py"
echo "=================================================================="
