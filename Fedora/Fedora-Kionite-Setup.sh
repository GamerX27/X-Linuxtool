#!/bin/bash
set -euo pipefail

flatpak remote-modify --disable fedora-testing
flatpak remote-modify --disable fedora



#Apps
flatpak remove -y org.kde.elisa org.kde.kmahjongg org.kde.kolourpaint org.kde.kmines org.kde.kolourpaint

flatpak -y install flathub com.brave.Browser org.videolan.VLC org.jellyfin.JellyfinDesktop org.localsend.localsend_app io.github.kolunmi.Bazaar com.unicornsonlsd.finamp 



#Browser
#make Brave less bloated disables AI, better privacy out of the box and makes Qwant based in europe the default search using policy.
wget https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/browser/Brave/make_brave_great_again.sh
sudo bash make_brave_great_again.sh
sudo rm make_brave_great_again.sh


# Step 1: Edit rpm-ostreed.conf to enable staging of updates
sudo tee /etc/rpm-ostreed.conf > /dev/null << 'EOF'
[Daemon]
AutomaticUpdatePolicy=stage
EOF

# Step 2: Reload the rpm-ostree daemon to apply changes
sudo rpm-ostree reload

# Step 3: Enable and start the automatic update timer
sudo systemctl enable --now rpm-ostreed-automatic.timer

# Verification
echo "✅ Configuration complete. Verify with: rpm-ostree status"
echo "🔍 Auto-updates are staged but require manual reboot to apply."


# Define paths
SERVICE_FILE="/etc/systemd/system/update-system-flatpaks.service"
TIMER_FILE="/etc/systemd/system/update-system-flatpaks.timer"

# Create or overwrite the service file
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

# Create or overwrite the timer file
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

# Reload systemd to apply changes
sudo systemctl daemon-reload

# Enable and start the timer
sudo systemctl --system enable --now update-system-flatpaks.timer

echo "✅ Flatpak update service and timer have been configured successfully."


#remove the ping thingy 
#Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
info() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

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

# Check for sudo
if ! command -v sudo &> /dev/null; then
  echo "sudo is required but not installed. Exiting."
  exit 1
fi
SUDO="sudo"

# NetworkManager paths
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"

# Main script
info "Disabling NetworkManager connectivity check via /etc override..."
try "Create NetworkManager conf.d directory" $SUDO mkdir -p "$NM_DIR_ETC"

if [[ -e "$NM_FILE_ETC" ]]; then
  try "Backing up existing ${NM_FILE_ETC}" \
    $SUDO cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak"
fi

try "Writing override config" bash -c "cat <<'EOF' | $SUDO tee '$NM_FILE_ETC' >/dev/null
[connectivity]
enabled=false
EOF"

try "Reloading NetworkManager"  $SUDO systemctl reload NetworkManager
try "Restarting NetworkManager" $SUDO systemctl restart NetworkManager

info "Connectivity check disabled."

sleep 15

#Update System
rpm-ostree upgrade
reboot now