#!/bin/bash

if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
            # Nearest 256-color approximations of the Nord palette.
            C_BLUE=$'\033[38;5;110m'    # nord9  81a1c1
            C_RED=$'\033[38;5;167m'     # nord11 bf616a
            C_YELLOW=$'\033[38;5;222m'  # nord13 ebcb8b
            C_GREEN=$'\033[38;5;150m'   # nord14 a3be8c
            C_MAGENTA=$'\033[38;5;139m' # nord15 b48ead
            ;;
        *)
            C_BLUE=$'\033[38;2;129;161;193m'   # nord9  81a1c1
            C_RED=$'\033[38;2;191;97;106m'     # nord11 bf616a
            C_YELLOW=$'\033[38;2;235;203;139m' # nord13 ebcb8b
            C_GREEN=$'\033[38;2;163;190;140m'  # nord14 a3be8c
            C_MAGENTA=$'\033[38;2;180;142;173m' # nord15 b48ead
            ;;
    esac
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA=""
fi

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }
ui_rule()    { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }

ui_menu_item() {
    # ui_menu_item <number> <label>
    printf '   %s%s)%s %s%s%s\n' \
        "$C_BOLD" "$1" "$C_RESET" \
        "$C_BOLD" "$2" "$C_RESET"
}

# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop"

# When invoked by a local X-Linuxtool.sh clone, X27_LOCAL_ROOT points at
# the clone root; prefer the scripts already on disk over re-downloading.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Desktop}"

CB_TOOLS="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Tools"
GH_TOOLS="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Tools"
LOCAL_TOOLS="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Tools}"

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

fetch_tool_file() {
    # fetch_tool_file <relative/path> <output-file>
    local rel="$1" out="$2"

    if [ -n "$LOCAL_TOOLS" ] && [ -f "$LOCAL_TOOLS/$rel" ]; then
        ui_info "Using local copy: ${rel}"
        cp "$LOCAL_TOOLS/$rel" "$out"
        return 0
    fi

    ui_info "Fetching ${rel} from Codeberg…"
    if _download "${CB_TOOLS}/${rel}" "$out"; then
        ui_ok "Downloaded from Codeberg."
        return 0
    fi

    ui_warn "Codeberg unreachable; falling back to GitHub mirror…"
    if _download "${GH_TOOLS}/${rel}" "$out"; then
        ui_ok "Downloaded from GitHub mirror."
        return 0
    fi

    ui_err "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}

# Loop this submenu until the user explicitly backs out, so finishing one
# task (e.g. Fedora Post-Setup) returns here instead of exiting the script —
# that's what lets you run another Desktop-Linux task, or pick "Back" to
# return to the main X-Linuxtool.sh menu.
while true; do
    clear 2>/dev/null
    ui_step "Desktop-Linux"
    ui_rule
    ui_menu_item 1 "Fedora Post-Setup"
    ui_menu_item 2 "Fedora-Kinoite-Setup"
    ui_menu_item 3 "Bazzite Setup"
    ui_menu_item 4 "Brave"
    ui_menu_item 5 "Proton/Wine & Gaming"
    ui_menu_item 6 "Sleep Fix"
    ui_menu_item 7 "Flatpak Apps"
    ui_menu_item 8 "Flatpak Updates"
    ui_menu_item 0 "Back"
    printf '%s  ❯%s Enter your choice [0-8]: ' "$C_BOLD" "$C_RESET"
    read -r choice < "$INPUT" || exit 0

    case $choice in
        0)
            ui_info "Returning to the main menu…"
            exit 0
            ;;
        1)
            ui_step "Fedora Post-Setup"
            fetch_repo_file "Linux-Desktop/Fedora/Fedora-PostSetup.sh" /tmp/Fedora-PostSetup.sh || exit 1
            chmod +x /tmp/Fedora-PostSetup.sh
            bash /tmp/Fedora-PostSetup.sh
            rm -f /tmp/Fedora-PostSetup.sh
            ;;
        2)
            ui_step "Fedora-Kinoite-Setup"
            fetch_repo_file "Linux-Desktop/Fedora/Fedora-Kionite-Setup.sh" /tmp/Fedora-Kionite-Setup.sh || exit 1
            chmod +x /tmp/Fedora-Kionite-Setup.sh
            sudo /tmp/Fedora-Kionite-Setup.sh
            sudo rm -f /tmp/Fedora-Kionite-Setup.sh
            ;;
        3)
            ui_step "Bazzite Setup"
            fetch_repo_file "Linux-Desktop/Bazzite/Bazzite-Setup.sh" /tmp/Bazzite-Setup.sh || exit 1
            chmod +x /tmp/Bazzite-Setup.sh
            sudo /tmp/Bazzite-Setup.sh
            sudo rm -f /tmp/Bazzite-Setup.sh
            ;;
        4)
            ui_step "Brave"
            fetch_repo_file "Linux-Desktop/Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh || exit 1
            chmod +x /tmp/make_brave_great_again.sh
            sudo /tmp/make_brave_great_again.sh
            sudo rm -f /tmp/make_brave_great_again.sh
            ;;
        5)
            ui_step "Proton/Wine & Gaming"
            # Run as the normal user (NOT with sudo): GamingTools.sh dispatches to
            # per-option sub-scripts that each handle privilege escalation
            # themselves as needed (Wine and Proton run as the normal user;
            # Gaming Setup is invoked by GamingTools.sh with sudo directly).
            fetch_repo_file "Scripts/GamingTools.sh" /tmp/GamingTools.sh || exit 1
            chmod +x /tmp/GamingTools.sh
            bash /tmp/GamingTools.sh
            rm -f /tmp/GamingTools.sh
            ;;
        6)
            ui_step "Sleep Fix"
            fetch_tool_file "GigabyteSleep-Fix.sh" /tmp/GigabyteSleep-Fix.sh || exit 1
            chmod +x /tmp/GigabyteSleep-Fix.sh
            sudo /tmp/GigabyteSleep-Fix.sh
            sudo rm -f /tmp/GigabyteSleep-Fix.sh
            ;;
        7)
            ui_step "Flatpak Apps"
            fetch_repo_file "Linux-Desktop/Flatpak/flatpaks.sh" /tmp/flatpaks.sh || exit 1
            chmod +x /tmp/flatpaks.sh
            bash /tmp/flatpaks.sh
            rm -f /tmp/flatpaks.sh
            ;;
        8)
            ui_step "Flatpak Updates"
            fetch_repo_file "Linux-Desktop/Flatpak/Flatpak-AutoUpdate-Setup.sh" /tmp/Flatpak-AutoUpdate-Setup.sh || exit 1
            chmod +x /tmp/Flatpak-AutoUpdate-Setup.sh
            sudo /tmp/Flatpak-AutoUpdate-Setup.sh
            sudo rm -f /tmp/Flatpak-AutoUpdate-Setup.sh
            ;;
        *)
            ui_err "Invalid choice."
            ;;
    esac

    printf '\n'
    printf '%s  ❯%s Press Enter to return to this menu… ' "$C_BOLD" "$C_RESET"
    read -r _ < "$INPUT"
    printf '%s' "$C_RESET"
done
