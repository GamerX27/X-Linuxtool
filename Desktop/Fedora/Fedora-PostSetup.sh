#!/usr/bin/env bash
#
# Run as your normal user, not with sudo — it caches its own sudo session
# after one password prompt. Idempotent; safe to re-run.

set -uo pipefail

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

# When invoked by a local X-Linuxtool.sh clone, X27_LOCAL_ROOT points at
# the clone root; prefer the scripts already on disk over re-downloading.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Desktop}"

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
    local rel="$1" out="$2"

    if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE/$rel" ]; then
        log "Using local copy: ${rel}"
        cp "$LOCAL_BASE/$rel" "$out"
        return 0
    fi

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
    printf '%s%s%s %s[y/N]%s: ' "$C_FG" "$prompt" "$C_RESET" "$C_GREY" "$C_RESET"
    read -r answer
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

FEDORA_VERSION="$(rpm -E %fedora)"
log "Detected Fedora ${FEDORA_VERSION}"

log "Refreshing metadata and upgrading the system"
sudo dnf update --refresh -y \
    && sudo dnf upgrade -y \
    && ok "System updated." \
    || warn "System update encountered issues (continuing)."

log "Enabling RPM Fusion (free + nonfree) repositories"
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" \
    && ok "RPM Fusion enabled." \
    || warn "Failed to enable RPM Fusion (continuing)."

log "Enabling the Cisco OpenH264 repository"
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 \
    && ok "Cisco OpenH264 repository enabled." \
    || warn "Failed to enable the Cisco OpenH264 repository (continuing)."

log "Updating the @core package group"
sudo dnf update -y @core \
    && ok "@core package group updated." \
    || warn "Failed to update @core package group (continuing)."

log "Switching to the full ffmpeg build"
sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y \
    && ok "Switched to the full ffmpeg build." \
    || warn "Failed to switch to the full ffmpeg build (continuing)."

log "Installing additional multimedia codecs"
sudo dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin \
    && ok "Multimedia codecs installed." \
    || warn "Failed to install multimedia codecs (continuing)."

log "Hardware-accelerated video codecs"
printf '%sSelect your GPU vendor for hardware-accelerated (VA-API) codecs:%s\n' "$C_FG" "$C_RESET"
printf '  %s1)%s Intel (recent - Broadwell/5th-gen and newer)\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s2)%s Intel (older - pre-Broadwell)\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s3)%s AMD\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '  %s4)%s Skip\n' "$C_ACCENT$C_BOLD" "$C_RESET"
printf '%sEnter choice%s %s[1/2/3/4]%s: ' "$C_FG" "$C_RESET" "$C_GREY" "$C_RESET"
read -r gpu_choice

case "${gpu_choice}" in
    1)
        log "Installing Intel (recent) hardware-accelerated codecs"
        sudo dnf install -y intel-media-driver \
            && ok "Intel (recent) codecs installed." \
            || warn "Failed to install Intel (recent) codecs (continuing)."
        ;;
    2)
        log "Installing Intel (older) hardware-accelerated codecs"
        sudo dnf install -y libva-intel-driver \
            && ok "Intel (older) codecs installed." \
            || warn "Failed to install Intel (older) codecs (continuing)."
        ;;
    3)
        log "Installing AMD hardware-accelerated codecs"
        sudo dnf install -y mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686 \
            && ok "AMD codecs installed." \
            || warn "Failed to install AMD codecs (continuing)."
        ;;
    *)
        log "Skipping hardware-accelerated codec installation"
        ;;
esac

log "Removing unwanted default applications"
sudo dnf remove -y \
    dragon juk elisa-player kmail khelpcenter kmahjongg kmines kpat firefox \
    kaddressbook korganizer kolourpaint kamoso neochat 'libreoffice*' \
    && ok "Unwanted default applications removed." \
    || warn "Failed to remove some default applications (continuing)."

log "Installing base command-line tools"
# Note: lspci ships in pciutils, sensors ships in lm_sensors.
sudo dnf install -y wget fastfetch fish htop nano papirus-icon-theme curl pciutils lm_sensors \
    && ok "Base command-line tools installed." \
    || warn "Failed to install base command-line tools (continuing)."

log "Setting Fish as the default login shell"
sudo chsh -s "$(command -v fish)" "$USER" \
    && ok "Fish set as the default login shell." \
    || warn "Failed to set Fish as the default login shell (continuing)."

log "Configuring Konsole (Fish default profile, hidden toolbars)"
mkdir -p ~/.local/share/konsole ~/.local/share/kxmlgui5/konsole

cat > ~/.local/share/konsole/Fish.profile <<'EOF'
[General]
Command=/usr/bin/fish
Name=Fish
Parent=FALLBACK/
EOF

cat > ~/.config/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=Fish.profile

[General]
ConfigVersion=1

[MainWindow]
MenuBar=Disabled

[SplitView]
SplitViewVisibility=AlwaysHideSplitHeader

[TabBar]
TabBarVisibility=AlwaysHideTabBar
EOF

# Minimal KXMLGUI override; Konsole merges "hidden" into its built-in toolbar defs on launch.
cat > ~/.local/share/kxmlgui5/konsole/konsoleui.rc <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="konsole" version="1">
    <ToolBar name="mainToolBar" hidden="true">
        <text>Main Toolbar</text>
    </ToolBar>
</gui>
EOF

cat > ~/.local/share/kxmlgui5/konsole/sessionui.rc <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="session" version="1">
    <ToolBar name="sessionToolbar" hidden="true">
        <text>Session Toolbar</text>
    </ToolBar>
</gui>
EOF

ok "Konsole configured: Fish is the default profile, all toolbars/tab bar hidden."

log "Installing base applications"
sudo dnf install -y vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer gwenview \
    && ok "Base applications installed." \
    || warn "Failed to install base applications (continuing)."

require_cmd flatpak

log "Adding the Flathub remote"
# Flatpaks are installed system-wide, so the remote must be configured
# system-wide too. This needs root: the cached sudo session covers it without
# triggering a polkit prompt (which would otherwise fail in a non-interactive
# context with "ConfigureRemote not allowed for user").
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
    && ok "Flathub remote added." \
    || warn "Failed to add the Flathub remote (continuing)."

log "Running the Flatpak app install script"
FLATPAKS_SCRIPT="$(mktemp /tmp/flatpaks.XXXXXX.sh)"
fetch_repo_file "Flatpak/flatpaks.sh" "${FLATPAKS_SCRIPT}"
sudo bash "${FLATPAKS_SCRIPT}" \
    && ok "Flatpak apps installed." \
    || warn "Flatpak app install script reported issues (continuing)."
rm -f "${FLATPAKS_SCRIPT}"

log "Disabling the Fedora Flatpak remotes"
sudo flatpak remote-modify fedora --disable
sudo flatpak remote-modify fedora-testing --disable \
    && ok "Fedora Flatpak remotes disabled." \
    || warn "Failed to disable the Fedora Flatpak remotes (continuing)."

log "Installing Vivaldi (Flatpak)"
sudo flatpak install -y flathub com.vivaldi.Vivaldi \
    && ok "Vivaldi installed." \
    || warn "Failed to install Vivaldi (continuing)."

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
sudo systemctl restart NetworkManager \
    && ok "NetworkManager connectivity check disabled." \
    || warn "Failed to disable the NetworkManager connectivity check (continuing)."

log "Waiting 10 seconds for NetworkManager to settle"
sleep 10

log "Installing the Brave browser (origin flavor)"
curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh \
    && ok "Brave browser installed." \
    || warn "Failed to install the Brave browser (continuing)."

log "Setting Brave as the default web browser"
xdg-settings set default-web-browser brave-origin.desktop \
    && ok "Brave set as the default web browser." \
    || warn "Failed to set Brave as the default web browser (continuing)."

log "Applying Brave policy configuration"
BRAVE_POLICY_SCRIPT="$(mktemp /tmp/make_brave_great_again.XXXXXX.sh)"
fetch_repo_file "Browser/make_brave_great_again.sh" "${BRAVE_POLICY_SCRIPT}"
sudo bash "${BRAVE_POLICY_SCRIPT}" \
    && ok "Brave policy configuration applied." \
    || warn "Failed to apply the Brave policy configuration (continuing)."
rm -f "${BRAVE_POLICY_SCRIPT}"

log "Installing LibreWolf"
# --overwrite keeps this idempotent so re-running the script doesn't error out.
sudo dnf config-manager addrepo --overwrite --from-repofile=https://repo.librewolf.net/librewolf.repo
sudo dnf install -y librewolf \
    && ok "LibreWolf installed." \
    || warn "Failed to install LibreWolf (continuing)."

log "Installing additional browsers (Chromium, Tor Browser Launcher)"
sudo dnf install -y chromium torbrowser-launcher \
    && ok "Chromium and Tor Browser Launcher installed." \
    || warn "Failed to install Chromium/Tor Browser Launcher (continuing)."

log "Gaming setup"
if ask_yes_no "Would you like to run the gaming setup script?"; then
    log "Running the gaming setup script"
    GAMING_SCRIPT="$(mktemp /tmp/Gaming.XXXXXX.sh)"
    fetch_repo_file "Gaming/Gaming.sh" "${GAMING_SCRIPT}"
    sudo bash "${GAMING_SCRIPT}" \
        && ok "Gaming setup complete." \
        || warn "Gaming setup script reported issues (continuing)."
    rm -f "${GAMING_SCRIPT}"
else
    log "Skipping gaming setup"
fi

set_locale_time

log "Zed editor"
if ask_yes_no "Would you like to install the Zed editor?"; then
    log "Installing the Zed editor"
    curl -f https://zed.dev/install.sh | sh \
        && ok "Zed editor installed." \
        || warn "Failed to install the Zed editor (continuing)."
else
    log "Skipping Zed editor installation"
fi

log "Removing orphaned packages"
sudo dnf autoremove -y \
    && ok "Orphaned packages removed." \
    || warn "Failed to remove orphaned packages (continuing)."

log "Fedora post-setup complete."

if ask_yes_no "Would you like to reboot now?"; then
    log "Rebooting in..."
    for count in 5 4 3 2 1; do
        echo "$count"
        sleep 1
    done
    sudo systemctl reboot
else
    log "Reboot skipped. Remember to reboot later to apply all changes."
fi
