#!/bin/bash

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

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }

ui_step "Setting Up Bazzite Machine"

# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
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
        ui_err "Neither curl nor wget is available."
        return 1
    fi
}

fetch_repo_file() {
    # fetch_repo_file <relative/path> <output-file>
    local rel="$1" out="$2"

    if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE/$rel" ]; then
        ui_info "Using local copy: ${rel}"
        cp "$LOCAL_BASE/$rel" "$out"
        return 0
    fi

    ui_info "Fetching ${rel} from Codeberg…"
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        ui_ok "Downloaded from Codeberg."
        return 0
    fi

    ui_warn "Codeberg unreachable; falling back to GitHub mirror…"
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        ui_ok "Downloaded from GitHub mirror."
        return 0
    fi

    ui_err "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}


ui_step "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"
mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || ui_warn "Failed to back up NetworkManager config."
fi
printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
systemctl restart NetworkManager

ui_step "Replacing Firefox with Brave Browser..."
if flatpak list --app | grep -q "org.mozilla.firefox"; then
    ui_info "Firefox Flatpak found, removing..."
    flatpak uninstall -y org.mozilla.firefox
else
    ui_warn "Firefox Flatpak not found, skipping removal."
fi
ui_info "Installing Brave Browser from Flathub..."
flatpak install -y flathub com.brave.Browser com.brave.Browser



ui_step "Running Make Brave Great Again Tweak..."
fetch_repo_file "Browser/make_brave_great_again.sh" make_brave_great_again.sh
bash make_brave_great_again.sh
rm -f make_brave_great_again.sh



ui_step "Running a update..."
ujust update

ui_ok "Setup complete! Reboot recommended."
printf '%sReboot now?%s %s(y/n)%s: ' "$C_FG" "$C_RESET" "$C_GREY" "$C_RESET"
read -r reboot_choice
if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
    ui_info "Rebooting in..."
    for count in 10 9 8 7 6 5 4 3 2 1 0; do
        echo "$count"
        sleep 1
    done
    reboot
else
    ui_warn "Skipping reboot. Don't forget to restart when ready!"
fi
