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
info "Configuring system and user-level Flatpak updates with notifications..."

# Identify the original user to handle notifications and user-level configs
REAL_USER=$(logname)
USER_UID=$(id -u "$REAL_USER")
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# --- System-wide Configuration ---
# Create the system update script
cat << EOF > /usr/local/bin/flatpak-system-update.sh
#!/bin/bash
# Run the update
/usr/bin/flatpak update --system --noninteractive -y
EXIT_CODE=\$?

# Define the connection to the user's desktop session
USER_BUS="unix:path=/run/user/$USER_UID/bus"

if [ \$EXIT_CODE -eq 0 ]; then
    MESSAGE="System Flatpak updates completed successfully."
else
    MESSAGE="System Flatpak update failed with error code \$EXIT_CODE."
fi

# Send the notification to the user's KDE desktop
sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="\$USER_BUS" notify-send "Flatpak System Update" "\$MESSAGE"
EOF

chmod +x /usr/local/bin/flatpak-system-update.sh

# Create the systemd service file
cat << 'EOF' > /etc/systemd/system/flatpak-autoupdate.service
[Unit]
Description=System Flatpak Autoupdater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flatpak-system-update.sh

[Install]
WantedBy=multi-user.target
EOF

# Create the systemd timer file
cat << 'EOF' > /etc/systemd/system/flatpak-autoupdate.timer
[Unit]
Description=Run System Flatpak update daily and after boot

[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=5min

[Install]
WantedBy=timers.target
EOF

# --- User-level Configuration ---
mkdir -p "$USER_HOME/.config/systemd/user"

# Create a script for the user level to handle its own notifications easily
cat << EOF > /usr/local/bin/flatpak-user-update.sh
#!/bin/bash
/usr/bin/flatpak update --user --noninteractive -y
EXIT_CODE=\$?

if [ \$EXIT_CODE -eq 0 ]; then
    notify-send "Flatpak User Update" "User Flatpak updates completed successfully."
else
    notify-send "Flatpak User Update" "User Flatpak update failed!"
fi
EOF

chmod +x /usr/local/bin/flatpak-user-update.sh

# Create the user-level service file
cat << EOF > "$USER_HOME/.config/systemd/user/flatpak-autoupdate.service"
[Unit]
Description=User Flatpak Autoupdater
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flatpak-user-update.sh

[Install]
WantedBy=default.target
EOF

# Create the user-level timer file
cat << 'EOF' > "$USER_HOME/.config/systemd/user/flatpak-autoupdate.timer"
[Unit]
Description=Run User Flatpak update daily and after boot

[Timer]
OnCalendar=daily
Persistent=true
OnBootSec=5min

[Install]
WantedBy=timers.target
EOF

# Reload and enable
systemctl daemon-reload
systemctl enable --now flatpak-autoupdate.timer

sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" systemctl --user daemon-reload
sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$USER_UID" systemctl --user enable --now flatpak-autoupdate.timer

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
