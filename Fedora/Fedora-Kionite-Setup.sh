#!/bin/bash

# Check if the script is being run with sudo privileges
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# This stops the script from continuing if you press Ctrl+C
trap 'echo -e "\nProcess interrupted. Exiting."; exit 1' SIGINT SIGTERM

# Functions to handle the logging used in your code
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

# --- Configuration ---
APPS_TO_REMOVE=(org.kde.elisa org.kde.kmahjongg org.kde.kolourpaint org.kde.kmines)
APPS_TO_INSTALL=(
    com.brave.Browser
    org.videolan.VLC
    org.jellyfin.JellyfinDesktop
    org.localsend.localsend_app
    io.github.kolunmi.Bazaar
    com.unicornsonlsd.finamp
)

# --- Flatpak Remote Configuration ---
info "Configuring Flatpak remotes..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --disable fedora-testing 2>/dev/null || warn "Failed to disable fedora-testing remote (may not exist)."
flatpak remote-modify --disable fedora 2>/dev/null || warn "Failed to disable fedora remote (may not exist)."

# --- App Cleanup ---
info "Cleaning up default KDE apps..."
for app in "${APPS_TO_REMOVE[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        flatpak remove --noninteractive "$app" || warn "Failed to remove $app (may not be installed)."
    fi
done

# --- Install Apps ---
info "Installing core Flatpaks..."
for app in "${APPS_TO_INSTALL[@]}"; do
    try "Installing $app" flatpak install --assumeyes flathub "$app"
done

# --- Update Flatpaks ---
info "Running initial Flatpak update..."
flatpak update --noninteractive
flatpak --system update --noninteractive 2>/dev/null || warn "Failed to update system Flatpaks (may not be applicable)."

# --- NetworkManager Connectivity Fix ---
info "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"
mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || warn "Failed to back up NetworkManager config."
fi
printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

# --- RPM-OSTree Automatic Updates ---
info "Configuring rpm-ostree automatic updates..."
cat <<EOF > /etc/rpm-ostreed.conf
[Daemon]
AutomaticUpdatePolicy=stage
EOF
systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed service not active (will be enabled next)."
systemctl enable --now rpm-ostreed-automatic.timer

# --- Final System Upgrade ---
info "Performing final system upgrade..."
rpm-ostree upgrade --allow-downgrade

# --- Update time ---
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

# --- Flatpak Autostart for Updates ---
info "Setting up Flatpak autostart for updates..."
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/flatup <<EOF
#!/bin/sh
sleep 30
flatpak update --noninteractive && notify-send -a "Updater" "Apps updated!"
EOF
chmod +x ~/.config/autostart/flatup

# --- Shutdown Sequence ---
info "Setup Complete! Rebooting in 5 seconds. Press Ctrl+C to cancel."
sleep 5
reboot