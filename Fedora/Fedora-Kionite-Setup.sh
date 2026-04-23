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
try() {
  local msg="$1"
  shift
  echo -e "${YELLOW}[TRY]${NC} $msg"
  if "$@"; then echo -e "${GREEN}[OK]${NC} $msg"; else echo -e "${RED}[FAILED]${NC} $msg"; exit 1; fi
}

# --- 1. Flatpak Configuration ---
info "Configuring Flatpak remotes..."
flatpak remote-modify --disable fedora-testing || true
flatpak remote-modify --disable fedora || true

# App Cleanup
info "Cleaning up default KDE apps..."
APPS_TO_REMOVE=(org.kde.elisa org.kde.kmahjongg org.kde.kolourpaint org.kde.kmines)
for app in "${APPS_TO_REMOVE[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        flatpak remove -y "$app" || true
    fi
done

# Install Apps
try "Installing core Flatpaks" \
    flatpak -y install flathub com.brave.Browser org.videolan.VLC org.jellyfin.JellyfinDesktop org.localsend.localsend_app io.github.kolunmi.Bazaar com.unicornsonlsd.finamp

# --- 2. Brave Debloat ---
info "Debloating Brave Browser..."
BRAVE_DEBLOAT_URL="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh"
wget -q -O /tmp/make_brave_great_again.sh "$BRAVE_DEBLOAT_URL"
chmod +x /tmp/make_brave_great_again.sh
bash /tmp/make_brave_great_again.sh
rm -f /tmp/make_brave_great_again.sh

# --- 3. RPM-OSTree Automatic Updates ---
info "Configuring rpm-ostree automatic updates..."
cat <<EOF > /etc/rpm-ostreed.conf
[Daemon]
AutomaticUpdatePolicy=stage
EOF
systemctl reload rpm-ostreed || true
systemctl enable --now rpm-ostreed-automatic.timer

# --- 4. Flatpak Auto-Update Timer ---
info "Configuring daily Flatpak update service..."
SERVICE_FILE="/etc/systemd/system/update-system-flatpaks.service"
TIMER_FILE="/etc/systemd/system/update-system-flatpaks.timer"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Update system Flatpaks
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update --assumeyes --noninteractive --system
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > "$TIMER_FILE"
[Unit]
Description=Update system Flatpaks daily
[Timer]
OnCalendar=daily
Persistent=true
AccuracySec=1h
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now update-system-flatpaks.timer

# --- 5. NetworkManager Connectivity Fix ---
info "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"

mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || true
fi

printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

# --- 6. Final System Upgrade ---
info "Performing final system upgrade..."
sleep 5
rpm-ostree upgrade

info "Setup Complete! Rebooting now."
sleep 5
reboot
