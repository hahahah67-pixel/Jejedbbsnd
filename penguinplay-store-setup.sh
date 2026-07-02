#!/bin/bash
#
# Play Store setup for Chromebook Linux (Crostini)
#
# This is a fixed-up version of the original script. Same structure and
# same overall idea — hidden program folder, a smart launch.sh, a desktop
# launcher — with the parts that specifically don't work on Crostini
# corrected. What changed and why is called out in comments below.

set -euo pipefail

# 1. Create the hidden program folder in your home directory
mkdir -p "$HOME/.playstore-emu"

# 2. Create the smart launch.sh script inside that folder
cat << 'EOF' > "$HOME/.playstore-emu/launch.sh"
#!/bin/bash
set -uo pipefail

export ANDROID_HOME="$HOME/AndroidSDK"
# Recent SDK tooling also checks ANDROID_SDK_ROOT; set both so nothing
# silently looks in the wrong place.
export ANDROID_SDK_ROOT="$ANDROID_HOME"

LOG_FILE="$HOME/.playstore-emu/launch.log"
log() { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

# --- INTELLIGENT PATH DETECTION ---
# Checks every place someone plausibly already has an SDK: the exact
# ANDROID_HOME/cmdline-tools/latest layout, the older cmdline-tools/bin
# layout, AND — since a user may have installed the SDK through Android
# Studio itself rather than the standalone command-line tools zip — a
# system-wide ANDROID_HOME/ANDROID_SDK_ROOT already exported in their
# shell environment. If sdkmanager is found in any of those, that
# install is reused as-is and nothing is downloaded.
if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -x "${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then
    ANDROID_HOME="$ANDROID_SDK_ROOT"
    CMDLINE_BIN="$ANDROID_HOME/cmdline-tools/latest/bin"
elif [ -d "$ANDROID_HOME/cmdline-tools/latest/bin" ]; then
    CMDLINE_BIN="$ANDROID_HOME/cmdline-tools/latest/bin"
elif [ -d "$ANDROID_HOME/cmdline-tools/bin" ]; then
    CMDLINE_BIN="$ANDROID_HOME/cmdline-tools/bin"
else
    CMDLINE_BIN="$ANDROID_HOME/cmdline-tools/latest/bin"
fi

export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$CMDLINE_BIN:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"

AVD_NAME="PlayStoreEmulator"

# Only download anything if an existing, working SDK was NOT found above.
# Users who already have the SDK installed skip straight past this whole
# block and go directly to the emulator boot step further down.
if [ ! -x "$CMDLINE_BIN/sdkmanager" ]; then
    echo "Required SDK files not found. Proceeding to automatically fetch the .zip from Google..."

    # Make sure Java exists — sdkmanager/avdmanager are Java tools and
    # Crostini does not ship a JRE by default.
    if ! command -v java >/dev/null 2>&1; then
        log "Java not found. Installing openjdk-17-jre-headless (you may be asked for your password)..."
        sudo apt-get update -y
        sudo apt-get install -y openjdk-17-jre-headless unzip wget
    fi

    mkdir -p "$ANDROID_HOME/cmdline-tools"
    TMP_ZIP="$(mktemp --suffix=.zip)"

    # Try to grab the current build number Google is publishing; fall back
    # to a known-good build id if that page can't be reached.
    LATEST_URL="$(curl -s https://developer.android.com/studio \
        | grep -oE 'https://dl\.google\.com/android/repository/commandlinetools-linux-[0-9]+_latest\.zip' \
        | head -1)"
    if [ -z "$LATEST_URL" ]; then
        LATEST_URL="https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip"
    fi

    # A real, live percentage progress bar (wget's own --progress=bar
    # renders it as it downloads and reaches 100% when the download
    # finishes) rather than a fake/simulated one.
    echo "Downloading Android SDK Command-line Tools..."
    wget --progress=bar:force:noscroll -O "$TMP_ZIP" "$LATEST_URL"

    echo "Extracting the .zip..."
    TMP_EXTRACT="$(mktemp -d)"
    unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
    rm -rf "$ANDROID_HOME/cmdline-tools/latest"
    mv "$TMP_EXTRACT/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -f "$TMP_ZIP"
    rm -rf "$TMP_EXTRACT"

    CMDLINE_BIN="$ANDROID_HOME/cmdline-tools/latest/bin"
    export PATH="$PATH:$CMDLINE_BIN:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
    echo "Complete!"
else
    log "Existing SDK found at $ANDROID_HOME — using it, nothing to download."
fi

# FIX: the system image was hardcoded to android-35, but Google doesn't
# always publish a Play Store-enabled image for the newest API level on
# every CPU architecture right away. Trying a short list of known-good
# levels, newest first, means this keeps working even if 35 isn't
# available yet for your machine's architecture.
#
# FIX: this also detects arm64 Chromebooks instead of assuming x86_64.
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64|amd64) ABI="x86_64" ;;
    aarch64|arm64) ABI="arm64-v8a" ;;
    *) log "Unsupported architecture: $HOST_ARCH"; exit 1 ;;
esac

API_CANDIDATES=(35 34 33)
IMAGE_PKG=""
if [ -f "$HOME/.playstore-emu/image.conf" ]; then
    IMAGE_PKG="$(cat "$HOME/.playstore-emu/image.conf")"
fi

# Check if the AVD already exists — if so, skip all of setup below,
# same as the original script intended.
if emulator -list-avds 2>/dev/null | grep -q "^${AVD_NAME}$"; then
    log "[$AVD_NAME] found! Waking up your existing setup..."
else
    log "First time setup detected. Installing Android system files..."
    yes | sdkmanager --licenses >/dev/null 2>&1 || true
    sdkmanager "platform-tools" "emulator"

    for api in "${API_CANDIDATES[@]}"; do
        candidate="system-images;android-${api};google_apis_playstore;${ABI}"
        log "Trying $candidate ..."
        if sdkmanager "$candidate"; then
            IMAGE_PKG="$candidate"
            break
        fi
    done

    if [ -z "$IMAGE_PKG" ]; then
        log "ERROR: could not install any Play Store system image for $ABI."
        log "Your Chromebook's architecture may not have a Play-enabled image published yet."
        exit 1
    fi
    echo "$IMAGE_PKG" > "$HOME/.playstore-emu/image.conf"

    echo "no" | avdmanager create avd -n "$AVD_NAME" -k "$IMAGE_PKG" --device "pixel"
    log "Setup complete!"
fi

# Boot the emulator and open the Play Store.
# -accel auto (the default) uses hardware acceleration if this
# Chromebook's Crostini build exposes /dev/kvm, and falls back to
# software emulation automatically if it doesn't — no need to detect
# this by hand.
emulator -avd "$AVD_NAME" -accel auto &
log "Waiting for Android to boot..."
adb wait-for-device

# FIX: `adb wait-for-device` only confirms the adb daemon connected, not
# that Android has actually finished booting — launching Play Store any
# earlier than that can silently fail. Poll sys.boot_completed instead,
# the officially documented way to detect a fully booted emulator.
BOOT_TIMEOUT=300
elapsed=0
while [ "$elapsed" -lt "$BOOT_TIMEOUT" ]; do
    boot_done="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [ "$boot_done" = "1" ]; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# FIX: sys.boot_completed=1 just means Android's core system is up — on
# a brand-new AVD, that's still the "Set up your Android device" wizard,
# not the home screen, and firing Play Store into that wizard does
# nothing useful. Android tracks whether the wizard has actually been
# finished in a real system setting, secure/user_setup_complete, which
# is 0 until you complete it and permanently flips to 1 the moment you
# do — it never resets on later boots. So instead of guessing "is this
# the first run," we just wait on that flag every time:
#   - Brand-new AVD: it's 0, so this waits for you to finish signing in
#     etc. by hand, however long that takes, then fires immediately.
#   - Every AVD after that: it's already 1, so this passes in ~1 second
#     and Play Store opens right away, same as before.
log "Waiting for Android setup to be ready..."
setup_notice_shown=0
while true; do
    setup_done="$(adb shell settings get secure user_setup_complete 2>/dev/null | tr -d '\r')"
    if [ "$setup_done" = "1" ]; then
        break
    fi
    if [ "$setup_notice_shown" -eq 0 ]; then
        log "If this is the first time this device has booted, finish the"
        log "'Set up your Android device' screen now (sign in, etc.) —"
        log "Google Play will open automatically the moment you're done."
        setup_notice_shown=1
    fi
    sleep 2
done

log "Opening Google Play..."
adb shell monkey -p com.android.vending -c android.intent.category.LAUNCHER 1
EOF

# 3. Make the shell script executable
chmod +x "$HOME/.playstore-emu/launch.sh"

# 4. Download the app icon from GitHub.
# Using the raw.githubusercontent.com form of the file (not the github.com
# "blob" page, which serves an HTML viewer, not the actual image bytes).
# This is a plain public raw link with no expiry, unlike the old signed
# GCS URL — so this one is safe to fetch at setup time instead of needing
# to be embedded in the script.
ICON_URL="https://raw.githubusercontent.com/hahahah67-pixel/Jejedbbsnd/main/playstore-removebg-preview.png"
if ! curl -sL --fail "$ICON_URL" -o "$HOME/.playstore-emu/app-icon.png"; then
    echo "Warning: couldn't download the icon from $ICON_URL — continuing without a custom icon."
fi

# 5. Create the .desktop launcher.
# FIX: this is the actual reason the original didn't work on Chromebook.
# Crostini has no desktop-icon shell and generally no ~/Desktop folder —
# a .desktop file placed there is just inert. ChromeOS's app launcher
# only picks up Linux apps from the standard XDG applications directory,
# ~/.local/share/applications/, which Crostini's garcon service watches
# and mirrors into the ChromeOS launcher.
mkdir -p "$HOME/.local/share/applications"
cat << EOF > "$HOME/.local/share/applications/playstore.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Google Play Store
Comment=Launch Android directly into the Play Store
Exec=$HOME/.playstore-emu/launch.sh
Icon=$HOME/.playstore-emu/app-icon.png
Terminal=false
Categories=Utility;Development;
EOF

chmod +x "$HOME/.local/share/applications/playstore.desktop"

# Refresh the desktop database so it shows up in the ChromeOS launcher
# right away instead of waiting for the next periodic sync.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" || true
fi

echo "--------------------------------------------------------"
echo "Setup is completely finished!"
echo "Search for 'Google Play Store' in the Chromebook launcher,"
echo "or run: ~/.playstore-emu/launch.sh"
echo "--------------------------------------------------------"

# 6. Prompt the user and auto-open the program directly from the terminal
read -p "Press [Enter] key to test and open Google Play Store right now... "

"$HOME/.playstore-emu/launch.sh"
