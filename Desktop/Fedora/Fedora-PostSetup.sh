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

# --- Theme / colors ---------------------------------------------------------
# Same Nord palette as X-Linuxtool.sh, anchored on Polar Night #2e3440
# (base/border) and Aurora Red #bf616a (accent/selection).
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
            # Nearest 256-color approximations of the Nord palette.
            C_GREY=$'\033[38;5;244m'    # nord3  4c566a
            C_FG=$'\033[38;5;253m'      # nord4  d8dee9
            C_BLUE=$'\033[38;5;110m'    # nord9  81a1c1
            C_RED=$'\033[38;5;167m'     # nord11 bf616a
            C_YELLOW=$'\033[38;5;222m'  # nord13 ebcb8b
            C_GREEN=$'\033[38;5;150m'   # nord14 a3be8c
            C_MAGENTA=$'\033[38;5;139m' # nord15 b48ead
            C_ACCENT=$'\033[38;5;167m'  # nord11 bf616a
            ;;
        *)
            C_GREY=$'\033[38;2;76;86;106m'     # nord3  4c566a
            C_FG=$'\033[38;2;216;222;233m'     # nord4  d8dee9
            C_BLUE=$'\033[38;2;129;161;193m'   # nord9  81a1c1
            C_RED=$'\033[38;2;191;97;106m'     # nord11 bf616a
            C_YELLOW=$'\033[38;2;235;203;139m' # nord13 ebcb8b
            C_GREEN=$'\033[38;2;163;190;140m'  # nord14 a3be8c
            C_MAGENTA=$'\033[38;2;180;142;173m' # nord15 b48ead
            C_ACCENT=$'\033[38;2;191;97;106m'  # nord11 bf616a
            ;;
    esac
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_GREY="" C_FG="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_ACCENT=""
fi

# --- Helpers ----------------------------------------------------------------

log() {
    printf '\n%s==>%s %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

ok() {
    printf '%s  ✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

warn() {
    printf '%sWarning:%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$1" >&2
}

err() {
    printf '\n%sError:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$1" >&2
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command '$1' not found."
        exit 1
    fi
}

# Repository locations: Codeberg is primary, GitHub is a fallback mirror.
CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop"

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
    read -rp "$(printf '%s%s%s %s[y/N]%s: ' "$C_FG" "$prompt" "$C_RESET" "$C_GREY" "$C_RESET")" answer
    case "${answer}" in
        [yY] | [yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

set_locale_time() {
    log "Setting LC_TIME to C.UTF-8"
    sudo localectl set-locale LC_TIME=C.UTF-8 \
        && ok "Successfully set LC_TIME." \
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
printf '%sSelect your GPU vendor for hardware-accelerated (VA-API) codecs:%s\n' "$C_FG" "$C_RESET"
printf '  %s1)%s Intel (recent - Broadwell/5th-gen and newer)\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s2)%s Intel (older - pre-Broadwell)\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s3)%s AMD\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s4)%s Skip\n' "$C_ACCENT$C_BOLD" "$C_RESET"
read -rp "$(printf '%sEnter choice%s %s[1/2/3/4]%s: ' "$C_FG" "$C_RESET" "$C_GREY" "$C_RESET")" gpu_choice

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
    dragon juk elisa-player kmail khelpcenter kmahjongg kmines kpat firefox \
    kaddressbook korganizer kolourpaint kamoso neochat 'libreoffice*'

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

sudo dnf remove -y NetworkManager-config-connectivity-fedora
sudo systemctl restart NetworkManager

log "Waiting 10 seconds for NetworkManager to settle"
sleep 10

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
