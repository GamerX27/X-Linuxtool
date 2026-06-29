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
#  13. Optionally install the Zed editor.
#  14. Clean up orphaned packages and optionally reboot.
#
# Usage: ./Fedora-PostSetup.sh
#
# Run this as your normal user (NOT with sudo). You will be asked for your
# password once; system steps (including the system-wide Flatpak installs) then
# use that cached sudo session, while per-user steps (e.g. Zed) run as you
# without any further prompts.
#
# The script is idempotent: it can be re-run safely without aborting on
# already-installed packages or already-configured repositories.
#

set -uo pipefail

# --- Helpers ----------------------------------------------------------------

log() {
    printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$1"
}

warn() {
    printf '\033[1;33mWarning:\033[0m %s\n' "$1" >&2
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

# Repository locations: Codeberg is primary, GitHub is a fallback mirror.
CODEBERG_RAW="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X27-Linux-Desktop-Toolbox/main"

_download() {
    # _download <url> <output-file>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        err "Neither curl nor wget is available."
        return 1
    fi
}

fetch_repo_file() {
    # fetch_repo_file <relative/path> <output-file>
    # Downloads from Codeberg (primary); falls back to the GitHub mirror.
    local rel="$1" out="$2"

    log "Fetching ${rel} from Codeberg"
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        return 0
    fi

    warn "Codeberg unreachable; falling back to GitHub mirror."
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        return 0
    fi

    err "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}

# Ask a yes/no question; returns 0 for yes, 1 for anything else (default no).
ask_yes_no() {
    local prompt="$1" answer
    read -rp "${prompt} [y/N]: " answer
    case "${answer}" in
        [yY] | [yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

set_locale_time() {
    log "Setting LC_TIME to C.UTF-8"
    sudo localectl set-locale LC_TIME=C.UTF-8 \
        && echo "Successfully set LC_TIME." \
        || warn "Failed to set LC_TIME (continuing)."
}

# --- Pre-flight checks ------------------------------------------------------

if [[ "${EUID}" -eq 0 ]]; then
    err "Do not run this script with sudo or as root. Run it as your normal user; it will request sudo itself."
    exit 1
fi

require_cmd sudo
require_cmd dnf
require_cmd rpm

# Authenticate sudo once up front, then keep the timestamp alive in the
# background so the system (sudo) steps never re-prompt, while the per-user
# steps run as the normal user with no authentication at all.
log "Requesting administrator access (you will be asked for your password once)"
sudo -v

while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

cleanup() {
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
}
trap cleanup EXIT

# Detect the Fedora release version (e.g. 40, 41, ...).
FEDORA_VERSION="$(rpm -E %fedora)"
log "Detected Fedora ${FEDORA_VERSION}"

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
        sudo dnf install -y mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686
        ;;
    *)
        log "Skipping hardware-accelerated codec installation"
        ;;
esac

# --- 7. Base packages -------------------------------------------------------

log "Removing unwanted default applications"
sudo dnf remove -y \
    dragon juk elisa-player kmail khelpcenter kmahjongg kmines kpat firefox 'libreoffice*'

log "Installing base command-line tools"
# Note: lspci ships in pciutils, sensors ships in lm_sensors.
sudo dnf install -y wget fastfetch fish htop nano papirus-icon-theme curl pciutils lm_sensors

log "Installing base applications"
sudo dnf install -y vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer gwenview

# --- 8. Flatpaks ------------------------------------------------------------

require_cmd flatpak

log "Adding the Flathub remote"
# Flatpaks are installed system-wide, so the remote must be configured
# system-wide too. This needs root: the cached sudo session covers it without
# triggering a polkit prompt (which would otherwise fail in a non-interactive
# context with "ConfigureRemote not allowed for user").
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

log "Running the Flatpak app install script"
FLATPAKS_SCRIPT="$(mktemp /tmp/flatpaks.XXXXXX.sh)"
fetch_repo_file "Flatpak/flatpaks.sh" "${FLATPAKS_SCRIPT}"
sudo bash "${FLATPAKS_SCRIPT}"
rm -f "${FLATPAKS_SCRIPT}"

log "Disabling the Fedora Flatpak remotes"
sudo flatpak remote-modify fedora --disable
sudo flatpak remote-modify fedora-testing --disable

log "Installing Vivaldi (Flatpak)"
sudo flatpak install -y flathub com.vivaldi.Vivaldi

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

sudo dnf remove -y --skip-unavailable NetworkManager-config-connectivity-fedora
sudo systemctl restart NetworkManager

# --- 10. Browser configuration ----------------------------------------------

log "Installing the Brave browser (origin flavor)"
curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh

log "Applying Brave policy configuration"
BRAVE_POLICY_SCRIPT="$(mktemp /tmp/make_brave_great_again.XXXXXX.sh)"
fetch_repo_file "Browser/make_brave_great_again.sh" "${BRAVE_POLICY_SCRIPT}"
sudo bash "${BRAVE_POLICY_SCRIPT}"
rm -f "${BRAVE_POLICY_SCRIPT}"

log "Installing LibreWolf"
# --overwrite keeps this idempotent so re-running the script doesn't error out.
sudo dnf config-manager addrepo --overwrite --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf

log "Installing additional browsers (Chromium, Tor Browser Launcher)"
sudo dnf install -y chromium torbrowser-launcher

# --- 11. Gaming (optional) --------------------------------------------------

log "Gaming setup"
if ask_yes_no "Would you like to run the gaming setup script?"; then
    log "Running the gaming setup script"
    GAMING_SCRIPT="$(mktemp /tmp/Gaming.XXXXXX.sh)"
    fetch_repo_file "Gaming/Gaming.sh" "${GAMING_SCRIPT}"
    sudo bash "${GAMING_SCRIPT}"
    rm -f "${GAMING_SCRIPT}"
else
    log "Skipping gaming setup"
fi

# --- 12. Locale -------------------------------------------------------------

set_locale_time

# --- 13. Zed editor (optional) ----------------------------------------------

log "Zed editor"
if ask_yes_no "Would you like to install the Zed editor?"; then
    log "Installing the Zed editor"
    curl -f https://zed.dev/install.sh | sh
else
    log "Skipping Zed editor installation"
fi

# --- 14. Cleanup and reboot -------------------------------------------------

log "Removing orphaned packages"
sudo dnf autoremove -y

log "Fedora post-setup complete."

if ask_yes_no "Would you like to reboot now?"; then
    log "Rebooting..."
    sudo systemctl reboot
else
    log "Reboot skipped. Remember to reboot later to apply all changes."
fi
