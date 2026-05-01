#!/bin/bash

# ==============================================================================
# Script Name: setup-fedora-immutable.sh
# Description: Configures Fedora (Silverblue/Kinoite) for a streamlined 
#              user experience by optimizing Flatpak, NetworkManager, 
#              and rpm-ostree settings.
# Author: Linux System Admin Expert
# Requirements: sudo privileges, internet connection
# ==============================================================================

set -e  # Exit on error

# --- Helper Functions ---
info() { echo -e "\e[32m[INFO]\e[0m $1"; }
warn() { echo -else -e "\e[33m[WARN]\e[0m $1" >&2; }
error() { echo -e "\e[31m[ERROR]\e[0m $1" >&2; exit 1; }

# A 'try' function to wrap commands with error reporting
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

# Ensure flathub is present before attempting installation
if ! flatpak remote-exists flathub; then
    info "Adding Flathub remote..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
fi

# Disable Fedora-specific remotes to prevent package conflicts
sudo flatpak remote-modify --disable fedora-testing 2>/dev/null || warn "fedora-testing remote not found."
sudo flatpak remote-modify --disable fedora 2>/dev/null || warn "fedora remote not found."

# --- 2. Application Management: Cleanup ---
info "Cleaning up default KDE apps..."
for app in "${KDE_BLOAT[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        info "Removing $app..."
        flatpak remove -y "$app" || warn "Failed to remove $app."
    fi
done

# --- 3. Application Management: Installation ---
info "Installing core Flatpaks..."
for app in "${FLATPAK_APPS[@]}"; do
    try "Installing $app" flatpak install -y flathub "$app"
done

# Ensure all apps/runtimes are fully up to date
info "Running final Flatpak update cycle..."
flatpak update -y
sudo flatpak --system update -y

# --- 4. NetworkManager Connectivity Fix ---
info "Disabling NetworkManager connectivity check (prevents boot delays)..."
sudo mkdir -p "$NM_CONF_DIR"
if [[ -e "$NM_CONF_FILE" ]]; then
    sudo cp -n "$NM_CONF_FILE" "${NM_CONF_FILE}.bak" || warn "Failed to backup NetworkManager config."
fi
echo -e '[connectivity]\nenabled=false' | sudo tee "$NM_CONF_FILE" > /dev/null
sudo systemctl restart NetworkManager

# --- 5. System Locale Configuration ---
info "Setting LC_TIME to C.UTF-8 for consistent formatting..."
if sudo localectl set-locale LC_TIME=C.UTF-8; then
    info "Locale time updated."
else
    error "Failed to set locale time."
fi

# --- 6. rpm-ostree Automation & Upgrades ---
info "Configuring rpm-ostree automatic updates..."
# Configure the daemon to stage updates in the background
sudo tee /etc/rpm-ostreed.conf <<EOF > /dev/else
[Daemon]
AutomaticUpdatePolicy=stage
EOF

sudo systemctl enable --now rpm-ostree-automatic.timer
sudo systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed reload failed (service may not be active)."

info "Performing final system upgrade..."
# Note: This may require a reboot to apply changes
sudo rpm-ostree upgrade

# --- 7. User Autostart Configuration ---
info "Creating user autostart script for post-boot updates..."
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_SCRIPT="$AUTOSTART_DIR/flatup.desktop"
INTERNAL_SH_PATH="$HOME/.local/bin/flatup_executor.sh"

mkdir -p "$AUTOSTART_DIR"
mkdir -p "$HOME/.local/bin"

# Create the actual executor script that runs after login
cat <<'EOF' > "$INTERNAL_SH_PATH"
#!/bin/bash
# Wait for desktop environment to settle
sleep 30
# Perform background update and notify via notify-send (if available)
flatpak update -y && notify-send "Flatpak Update" "Post-boot updates completed successfully." || notify-send "Flatpak Update" "Post-boot update failed. Check logs."
EOF
chmod +x "$INTERNAL_SH_PATH"

# Create the .desktop entry for autostart
cat <<EOF > "$AUTOSTART_SCRIPT"
[Desktop Entry]
Type=Application
Name=Flatpak Post-Boot Updater
Exec=$INTERNAL_SH_PATH
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Ensures Flatpaks are updated shortly after login.
EOF

info "Setup Complete! Please reboot your system to apply all changes."
