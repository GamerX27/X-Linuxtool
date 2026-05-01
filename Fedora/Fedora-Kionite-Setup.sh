#!/bin/bash

# ==============================================================================
# Fedora Kinoite/Silverblue Complete Setup
# This script MUST be run as a single block to ensure functions are defined.
# ==============================================================================

# EXIT IMMEDIATELY if any command fails or if the user interrupts (Ctrl+C)
set -e
trap 'echo -e "\n\e[31m[INTERRUPTED]\e[0m Process stopped by user. Not rebooting.\n"; exit 1' SIGINT SIGTERM

# --- Helper Functions (CRITICAL: These must be in the same file!) ---
info() { echo -e "\e[32m[INFO]\e[0m $1"; }
warn() { echo -e "\e[33m[WARN]\e[0m $1" >&2; }
error() { echo -e "\e[31m[ERROR]\e[0m $1" >&2; exit 1; }

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

# --- Configuration Variables ---
FLATPAK_APPS=(
    "com.brave.Browser"
    "org.videolan.VLC"
    "org.jellyfin.JellyfinDesktop"
    "org.localsend.localsend_app"
    "io.github.kolunmi.Bazaar"
    "com.unicornsonlsd.finamp"
)

KDE_BLOAT=(
    "org.kde.elisa"
    "org.kde.kmahjongg"
    "org.kde.kolourpaint"
    "org.kde.kmines"
)

NM_CONF_DIR="/etc/NetworkManager/conf.d"
NM_CONF_FILE="${NM_CONF_DIR}/20-connectivity-fedora.conf"

# --- 1. Flatpak Remote Configuration ---
info "Configuring Flatpak remotes..."
if ! flatpak remote-exists flathub; then
    info "Adding Flathulb remote..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

sudo flatpak remote-modify --disable fedora-testing 2>/dev/null || warn "fedora-testing remote not found."
sudo flatpak remote-modify --disable fedora 2>/dev/null || warn "fedora remote not found."

# --- 2. App Cleanup ---
info "Cleaning up default KDE apps..."
for app in "${KDE_BLOAT[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        info "Removing $app..."
        flatlamat-remove -y "$app" || warn "Failed to remove $app."
    fi
done

# --- 3. App Installation ---
info "Installing core Flatpaks..."
for app in "${FLATPAK_APPS[@]}"; do
    try "Installing $app" flatpak install -y flathub "$app"
done

info "Running Flatpak updates..."
flatpak update -y
sudo flatpak --system update -y

# --- 4. NetworkManager Fix ---
info "Disabling NetworkManager connectivity check..."
sudo mkdir -p "$NM_CONF_DIR"
if [[ -e "$NM_CONF_FILE" ]]; then
    sudo cp -n "$NM_CONF_FILE" "${NM_CONF_FILE}.bak" || warn "Backup failed."
fi
echo -e '[connectivity]\nenabled=false' | sudo tee "$NM_CONF_FILE" > /dev/null
sudo systemctl restart NetworkManager

# --- 5. rpm-ostree Automation ---
info "Configuring rpm-ostree automatic updates..."
sudo tee /etc/rpm-ostreed.conf > /dev/null <<EOF
[Daemon]
AutomaticUpdatePolicy=stage
EOF

# Check if the timer exists before enabling to prevent error
if systemctl list-unit-files | grep -q "rpm-ostree-automatic.timer"; then
    sudo systemctl enable --now rpm-ostree-automatic.timer
else
    warn "rpm-ostree-automatic.timer not found. Please install 'rpm-ostree-automatic'."
fi

# --- 6. Final System Upgrade ---
info "Performing final system upgrade..."
info "This part may take a long time. DO NOT interrupt."
if sudo rpm-ostree upgrade; then
    info "System upgrade successful."
else
    error "System upgrade failed! Check logs with 'journalctl -xe'. Skipping reboot."
fi

# --- 7. Locale Setup ---
info "Setting LC_TIME to C.UTF-8..."
sudo localectl set-locale LC_TIME=C.UTF-8

# --- 8. Final Reboot Sequence ---
info "Setup Complete! System will reboot in 15 seconds."
info "Press Ctrl+C now if you need to cancel the reboot."

for i in {15..1}; do
    echo -ne "Rebooting in $i... \r"
    sleep 1
done

sudo reboot
