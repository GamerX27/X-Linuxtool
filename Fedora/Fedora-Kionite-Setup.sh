#!/bin/bash

# --- FORCED SUDO BLOCK ---
if [[ $EUID -ne 0 ]]; then
   echo "This script requires root privileges. Re-running with sudo..."
   exec sudo "$0" "$@"
fi

# Set strict error handling
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
try() {
  local msg="$1"
  shift
  echo -e "${YELLOW}[TRY]${NC} $msg"
  if "$@"; then
    echo -e "${GREEN}[OK]${NC} $msg"
  else
    echo -e "${RED}[FAILED]${NC} $msg"
    exit 1
  fi
}

# --- 1. Flatpak Configuration ---
info "Configuring Flatpak remotes..."
flatpak remote-modify --disable fedora-testing || warn "Failed to disable fedora-testing remote (may not exist)."
flatpak remote-modify --disable fedora || warn "Failed to disable fedora remote (may not exist)."

# App Cleanup
info "Cleaning up default KDE apps..."
APPS_TO_REMOVE=(org.kde.elisa org.kde.kmahjongg org.kde.kolourpaint org.kde.kmines)
for app in "${APPS_TO_REMOVE[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        flatpak remove -y "$app" || warn "Failed to remove $app (may not be installed)."
    fi
done

# Install Apps
info "Installing core Flatpaks..."
try "Installing Flatpaks" \
    flatpak -y install flathub \
    com.brave.Browser \
    org.videolan.VLC \
    org.jellyfin.JellyfinDesktop \
    org.localsend.localsend_app \
    io.github.kolunmi.Bazaar \
    com.unicornsonlsd.finamp

# --- Run Flatpak Update and Notify ---
info "Running initial Flatpak update..."
flatpak update -y
flatpak --system update -y

# Send notification ONLY to users with an active desktop session
for user in $(loginctl list-sessions --no-legend --value | awk '{print $1}'); do
    USER_UID=$(id -u "$user" 2>/dev/null || continue)
    DBUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"
    if [ -S "/run/user/$USER_UID/bus" ]; then
        su - "$user" -c "DBUS_SESSION_BUS_ADDRESS=$DBUS_ADDRESS notify-send 'Flatpak Update' 'Your Flatpaks have been updated during setup.'"
    fi
done

# --- 2. Brave Debloat ---
info "Debloating Brave Browser..."
BRAVE_DEBLOAT_URL="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh"
wget -q -O /tmp/make_brave_great_again.sh "$BRAVE_DEBLOAT_URL"
chmod +x /tmp/make_brave_great_again.sh
if bash /tmp/make_brave_great_again.sh; then
    echo -e "${GREEN}[OK]${NC} Brave Browser debloat completed."
else
    warn "Brave Browser debloat may have failed (non-critical)."
fi
rm -f /tmp/make_brave_great_again.sh

# --- 3. RPM-OSTree Automatic Updates ---
info "Configuring rpm-ostree automatic updates..."
cat <<EOF > /etc/rpm-ostreed.conf
[Daemon]
AutomaticUpdatePolicy=stage
EOF
systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed service not active (will be enabled next)."
systemctl enable --now rpm-ostreed-automatic.timer

---
### 4. Flatpak Auto-Update (User-Level)
info "Setting up user-level Flatpak autoupdate..."
FLATPAK_AUTOUPDATE_URL="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Flatpak/Flatpak-AutoUpdate-Setup.sh"
wget -q -O /tmp/Flatpak-AutoUpdate-Setup.sh "$FLATPAK_AUTOUPDATE_URL"
chmod +x /tmp/Flatpak-AutoUpdate-Setup.sh

for user in $(loginctl list-sessions --no-legend --value | awk '{print $1}'); do
    USER_UID=$(id -u "$user" 2>/dev/null || continue)
    DBUS_ADDRESS="unix:path=/run/user/$USER_UID/bus"
    if [ -S "/run/user/$USER_UID/bus" ]; then
        su - "$user" -c "bash /tmp/Flatpak-AutoUpdate-Setup.sh"
    fi
done

rm -f /tmp/Flatpak-AutoUpdate-Setup.sh

# --- 5. NetworkManager Connectivity Fix ---
info "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"

mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || warn "Failed to back up NetworkManager config."
fi

printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

# --- 6. Final System Upgrade ---
info "Performing final system upgrade..."
sleep 5
rpm-ostree upgrade

# --- 7. Update time ---
set_locale_time() {
    echo "Attempting to set LC_TIME to C.UTF-8..."
    if sudo localectl set-locale LC_TIME=C.UTF-8; then
        echo "Successfully set LC_TIME."
    else
        echo "Error: Failed to set the locale time. Check if you have permission or if the command is correct." >&2
        return 1
    fi
}

set_locale_time

info "Setup Complete! Rebooting now."
sleep 5
reboot