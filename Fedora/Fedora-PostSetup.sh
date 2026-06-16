#!/usr/bin/env bash
#
# Fedora-PostSetup.sh
# Post-installation setup helper for Fedora.
#
# Steps performed:
#   1. Refresh metadata and apply all available updates.
#   2. Enable the RPM Fusion (free + nonfree) repositories.
#   3. Enable the Cisco OpenH264 repository for hardware/codec support.
#   4. Update the @core package group.
#   5. Install the full multimedia / codec stack.
#   6. Install hardware-accelerated video codecs (Intel or AMD).
#   7. Remove unwanted default apps and install base packages.
#   8. Set up Flatpaks (Flathub remote, app list, Vivaldi).
#   9. Disable the NetworkManager connectivity check.
#  10. Install and configure the Brave browser.
#  11. Optionally run the gaming setup script.
#  12. Set LC_TIME locale to C.UTF-8.
#  13. Clean up orphaned packages and optionally reboot.
#
# Usage: ./Fedora-PostSetup.sh
#

set -euo pipefail

# --- Helpers ----------------------------------------------------------------

log() {
    printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$1"
}

err() {
    printf '\n\033[1;31mError:\033[0m %s\n' "$1" >&2
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command '$1' not found."
        exit 1
    fi
}

set_locale_time() {
    echo "Attempting to set LC_TIME to C.UTF-8..."
    if sudo localectl set-locale LC_TIME=C.UTF-8; then
        echo "Successfully set LC_TIME."
    else
        echo "Error: Failed to set the locale time. Check if you have permission or if the command is correct." >&2
        return 1
    fi
}

# --- Pre-flight checks ------------------------------------------------------

if [[ "${EUID}" -eq 0 ]]; then
    err "Do not run this script as root. It will call sudo when needed."
    exit 1
fi

require_cmd sudo
require_cmd dnf
require_cmd rpm

# Detect the Fedora release version (e.g. 40, 41, ...).
FEDORA_VERSION="$(rpm -E %fedora)"
log "Detected Fedora ${FEDORA_VERSION}"

# Keep the sudo timestamp alive for the duration of the script.
sudo -v

# --- 1. Refresh and upgrade -------------------------------------------------

log "Refreshing metadata and upgrading the system"
sudo dnf update --refresh -y
sudo dnf upgrade -y

# --- 2. Enable RPM Fusion (free + nonfree) ----------------------------------

log "Enabling RPM Fusion (free + nonfree) repositories"
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

# --- 3. Enable Cisco OpenH264 -----------------------------------------------

log "Enabling the Cisco OpenH264 repository"
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

# --- 4. Update @core --------------------------------------------------------

log "Updating the @core package group"
sudo dnf update -y @core

# --- 5. Multimedia ----------------------------------------------------------

log "Switching to the full ffmpeg build"
sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y

log "Installing additional multimedia codecs"
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

# --- 6. Hardware-accelerated codecs -----------------------------------------

log "Hardware-accelerated video codecs"
echo "Select your GPU vendor for hardware-accelerated (VA-API) codecs:"
echo "  1) Intel (recent - Broadwell/5th-gen and newer)"
echo "  2) Intel (older - pre-Broadwell)"
echo "  3) AMD"
echo "  4) Skip"
read -rp "Enter choice [1/2/3/4]: " gpu_choice

case "${gpu_choice}" in
    1)
        log "Installing Intel (recent) hardware-accelerated codecs"
        sudo dnf install -y intel-media-driver
        ;;
    2)
        log "Installing Intel (older) hardware-accelerated codecs"
        sudo dnf install -y libva-intel-driver
        ;;
    3)
        log "Installing AMD hardware-accelerated codecs"
        sudo dnf install -y mesa-va-drivers-freeworld
        # 32-bit compat libraries (useful for Steam / Wine).
        sudo dnf install -y mesa-va-drivers-freeworld.i686
        ;;
    *)
        log "Skipping hardware-accelerated codec installation"
        ;;
esac

# --- 7. Base packages -------------------------------------------------------

log "Removing unwanted default applications"
sudo dnf remove -y dragon juk elisa-player kmail khelpcenter libreoffice*

log "Installing base command-line tools"
# Note: lspci ships in pciutils, sensors ships in lm_sensors.
sudo dnf install -y wget fastfetch fish htop nano papirus-icon-theme curl pciutils lm_sensors

log "Installing base applications"
sudo dnf install -y vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer gwenview

# --- 8. Flatpaks ------------------------------------------------------------

log "Adding the Flathub remote"
require_cmd flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Running the Flatpak app install script"
FLATPAKS_SCRIPT="$(mktemp /tmp/flatpaks.XXXXXX.sh)"
wget -O "${FLATPAKS_SCRIPT}" \
    https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Flatpak/flatpaks.sh
bash "${FLATPAKS_SCRIPT}"
rm -f "${FLATPAKS_SCRIPT}"

log "Disabling the Fedora Flatpak remotes"
flatpak remote-modify fedora --disable
flatpak remote-modify fedora-testing --disable

log "Installing Vivaldi (Flatpak)"
flatpak install -y flathub com.vivaldi.Vivaldi

# --- 9. Disable NetworkManager connectivity check ---------------------------

log "Disabling the NetworkManager connectivity check"
# An empty connectivity URI disables the check. We write the override to /etc
# (the proper override location) so it persists across updates and survives the
# removal of the vendor connectivity config package below.
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/20-connectivity-fedora.conf >/dev/null <<'EOF'
[connectivity]
uri=
EOF

sudo dnf remove -y NetworkManager-config-connectivity-fedora
sudo systemctl restart NetworkManager

# --- 10. Browser configuration ----------------------------------------------

log "Installing the Brave browser (origin flavor)"
curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh

log "Applying Brave policy configuration"
BRAVE_POLICY_SCRIPT="$(mktemp /tmp/make_brave_great_again.XXXXXX.sh)"
wget -O "${BRAVE_POLICY_SCRIPT}" \
    https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh
sudo bash "${BRAVE_POLICY_SCRIPT}"
rm -f "${BRAVE_POLICY_SCRIPT}"

log "Installing LibreWolf"
sudo dnf config-manager addrepo --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf

log "Installing additional browsers (Chromium, Tor Browser Launcher)"
sudo dnf install -y chromium torbrowser-launcher

# --- 11. Gaming (optional) --------------------------------------------------

log "Gaming setup"
read -rp "Would you like to run the gaming setup script? [y/N]: " gaming_choice

case "${gaming_choice}" in
    [yY] | [yY][eE][sS])
        log "Running the gaming setup script"
        GAMING_SCRIPT="$(mktemp /tmp/Gaming.XXXXXX.sh)"
        wget -O "${GAMING_SCRIPT}" \
            https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/Gaming.sh
        bash "${GAMING_SCRIPT}"
        rm -f "${GAMING_SCRIPT}"
        ;;
    *)
        log "Skipping gaming setup"
        ;;
esac

# --- 12. Locale -------------------------------------------------------------

log "Configuring LC_TIME locale"
set_locale_time

# --- 13. Cleanup and reboot -------------------------------------------------

log "Removing orphaned packages"
sudo dnf autoremove -y

log "Fedora post-setup complete."

read -rp "Would you like to reboot now? [y/N]: " reboot_choice
case "${reboot_choice}" in
    [yY] | [yY][eE][sS])
        log "Rebooting..."
        sudo systemctl reboot
        ;;
    *)
        log "Reboot skipped. Remember to reboot later to apply all changes."
        ;;
esac
