Here’s the updated script with the **`APPS_TO_REMOVE` and `APPS_TO_INSTALL`** arrays moved **under the Flatpak remote configuration** section, as requested:

---

```bash
#!/bin/bash

# =============================================
# INITIAL CHECKS AND FUNCTIONS
# =============================================

# Check if the script is being run with sudo privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# Handle Ctrl+C interruption
trap 'echo -e "\nProcess interrupted. Exiting."; exit 1' SIGINT SIGTERM

# Logging functions
info() { echo -e "[INFO] $1"; }
warn() { echo -e "[WARN] $1" >&2; }
try() {
    local msg="$1"
    shift
    if "$@"; then
        info "$msg: Success."
    else
        warn "$msg: Failed."
        return 1
    fi
}

# =============================================
# FLATPAK SETUP
# =============================================

# Configure Flatpak remotes
info "Configuring Flatpak remotes..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --disable fedora-testing 2>/dev/null || warn "Failed to disable fedora-testing remote (may not exist)."
flatpak remote-modify --disable fedora 2>/dev/null || warn "Failed to disable fedora remote (may not exist)."

# Apps to remove and install
APPS_TO_REMOVE=(
    org.kde.elisa
    org.kde.kmahjongg
    org.kde.kolourpaint
    org.kde.kmines
)

APPS_TO_INSTALL=(
    com.brave.Browser
    org.videolan.VLC
    org.jellyfin.JellyfinDesktop
    org.localsend.localsend_app
    io.github.kolunmi.Bazaar
    com.unicornsonlsd.finamp
)

# Clean up default KDE apps
info "Cleaning up default KDE apps..."
for app in "${APPS_TO_REMOVE[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        flatpak remove --noninteractive "$app" || warn "Failed to remove $app (may not be installed)."
    fi
done

# Install core Flatpaks
info "Installing core Flatpaks..."
for app in "${APPS_TO_INSTALL[@]}"; do
    try "Installing $app" flatpak install --assumeyes flathub "$app"
done

# =============================================
# BRAVE BROWSER DEBLOAT
# =============================================

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

# =============================================
# SYSTEM UPDATES AND CONFIGURATION
# =============================================

# Update Flatpaks
info "Running initial Flatpak update..."
flatpak update --noninteractive
flatpak --system update --noninteractive 2>/dev/null || warn "Failed to update system Flatpaks (may not be applicable)."

# Disable NetworkManager connectivity check
info "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"
mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || warn "Failed to back up NetworkManager config."
fi
printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

# Configure rpm-ostree automatic updates
info "Configuring rpm-ostree automatic updates..."
cat <<EOF > /etc/rpm-ostreed.conf
[Daemon]
AutomaticUpdatePolicy=stage
EOF
systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed service not active (will be enabled next)."
systemctl enable --now rpm-ostreed-automatic.timer

# Perform final system upgrade
info "Performing final system upgrade..."
rpm-ostree upgrade --allow-downgrade

# Set locale time
set_locale_time() {
    echo "Attempting to set LC_TIME to C.UTF-8..."
    if localectl list-locales | grep -q "C.UTF-8"; then
        if localectl set-locale LC_TIME=C.UTF-8; then
            echo "Successfully set LC_TIME."
        else
            echo "Error: Failed to set the locale time." >&2
            return 1
        fi
    else
        warn "C.UTF-8 locale not available. Skipping."
    fi
}
set_locale_time

# =============================================
# FLATPAK AUTO-UPDATE SETUP
# =============================================

info "Setting up Flatpak autostart for updates..."
sudo bash -c 'mkdir -p /home/$SUDO_USER/.config/autostart
cat > /home/$SUDO_USER/.config/autostart/flatup <<"EOF"
#!/bin/sh
sleep 30
if flatpak update --noninteractive | grep -q "ID.*Branch.*Op.*Remote"; then
    notify-send -a "Updater" "Apps updated!"
fi
EOF
chmod +x /home/$SUDO_USER/.config/autostart/flatup
chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.config/autostart'

# =============================================
# FINISH
# =============================================

info "Setup Complete! Rebooting in 5 seconds. Press Ctrl+C to cancel."
sleep 5
reboot
```