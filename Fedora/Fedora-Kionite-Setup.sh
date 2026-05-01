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

# --- 4. System Flatpak Auto-Update (with KDE Notifications) ---
info "Configuring system Flatpak autoupdate..."

# Create a script to handle the update and notifications
cat << 'EOF' > /usr/local/bin/system-flatpak-update.sh
#!/bin/bash

# Check if last run was more than 24 hours ago
LAST_RUN_FILE="/var/lib/flatpak-autoupdate-lastrun"
NOW=$(date +%s)
if [ -f "$LAST_RUN_FILE" ]; then
    LAST_RUN=$(cat "$LAST_RUN_FILE")
    if [ $(( NOW - LAST_RUN )) -lt 86400 ]; then
        exit 0
    fi
fi

# Run system updates
/usr/bin/flatpak --system update -y

# Send notification to all active users via DBUS
for user_home in /home/* /var/home/*; do
    if [ -d "$user_home" ]; then
        USER_NAME=$(basename "$user_home")
        if id "$USER_NAME" >/dev/null 2>&1; then
            USER_UID=$(id -u "$USER_NAME")
            if [ "$USER_UID" -gt 999 ]; then  # Skip system users
                USER_BUS="unix:path=/run/user/$USER_UID/bus"
                # Check if bus exists before sending notification
                if [ -S "$USER_BUS" ]; then
                    sudo -u "$USER_NAME" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" notify-send "Flatpak Update" "Your system Flatpaks have been updated."
                fi
            fi
        fi
    fi
done

# Record the last run time
echo "$NOW" > "$LAST_RUN_FILE"
EOF

chmod +x /usr/local/bin/system-flatpak-update.sh

# Create the systemd service file as specified
cat << 'EOF' > /etc/systemd/system/auto-update-system-flatpaks.service
[Unit]
Description=Automatically update system Flatpaks
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-flatpak-update.sh

[Install]
WantedBy=multi-user.target
EOF

# Create the systemd timer file as specified
cat << 'EOF' > /etc/systemd/system/auto-update-system-flatpaks.timer
[Unit]
Description=Daily automatic update of system Flatpaks

[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=1min

[Install]
WantedBy=timers.target
EOF

# Enable and start the timer
systemctl daemon-reload
systemctl enable --now auto-update-system-flatpaks.timer

# Initial run to test
systemctl start auto-update-system-flatpaks.service

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
