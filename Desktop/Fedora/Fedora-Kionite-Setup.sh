#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

trap 'echo -e "\nProcess interrupted. Exiting."; exit 1' SIGINT SIGTERM

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

info() { printf '%s[INFO]%s %s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$1"; }
ok()   { printf '%s  ✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$1" >&2; }
err()  { printf '%s[ERROR]%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$1" >&2; }
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
        warn "Neither curl nor wget is available."
        return 1
    fi
}

fetch_repo_file() {
    # fetch_repo_file <relative/path> <output-file>
    local rel="$1" out="$2"

    info "Fetching ${rel} from Codeberg..."
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        return 0
    fi

    warn "Codeberg unreachable; falling back to GitHub mirror..."
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        return 0
    fi

    warn "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}

info "Configuring Flatpak remotes..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak remote-modify --disable fedora-testing 2>/dev/null || warn "Failed to disable fedora-testing remote (may not exist)."
flatpak remote-modify --disable fedora 2>/dev/null || warn "Failed to disable fedora remote (may not exist)."

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

info "Cleaning up default KDE apps..."
for app in "${APPS_TO_REMOVE[@]}"; do
    if flatpak list --app | grep -q "$app"; then
        flatpak remove --noninteractive "$app" || warn "Failed to remove $app (may not be installed)."
    fi
done

info "Installing core Flatpaks..."
for app in "${APPS_TO_INSTALL[@]}"; do
    try "Installing $app" flatpak install --assumeyes flathub "$app"
done

info "Debloating Brave Browser..."
fetch_repo_file "Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh
chmod +x /tmp/make_brave_great_again.sh
if bash /tmp/make_brave_great_again.sh; then
    ok "Brave Browser debloat completed."
else
    warn "Brave Browser debloat may have failed (non-critical)."
fi
rm -f /tmp/make_brave_great_again.sh

info "Running initial Flatpak update..."
flatpak update --noninteractive
flatpak --system update --noninteractive 2>/dev/null || warn "Failed to update system Flatpaks (may not be applicable)."

info "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"
mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || warn "Failed to back up NetworkManager config."
fi
printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

info "Configuring rpm-ostree automatic updates..."
cat <<EOF > /etc/rpm-ostreed.conf
[Daemon]
AutomaticUpdatePolicy=stage
EOF
systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed service not active (will be enabled next)."
systemctl enable --now rpm-ostreed-automatic.timer

info "Performing final system upgrade..."
rpm-ostree upgrade --allow-downgrade

set_locale_time() {
    info "Attempting to set LC_TIME to C.UTF-8..."
    if localectl list-locales | grep -q "C.UTF-8"; then
        if localectl set-locale LC_TIME=C.UTF-8; then
            ok "Successfully set LC_TIME."
        else
            err "Failed to set the locale time."
            return 1
        fi
    else
        warn "C.UTF-8 locale not available. Skipping."
    fi
}
set_locale_time

info "Setting up Flatpak autostart for updates..."
fetch_repo_file "Flatpak/Flatpak-AutoUpdate-Setup.sh" Flatpak-AutoUpdate-Setup.sh
sudo bash Flatpak-AutoUpdate-Setup.sh
rm Flatpak-AutoUpdate-Setup.sh

sleep 5
reboot
