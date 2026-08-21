#!/bin/bash

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
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
ui_rule()    { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM$C_GREY" "$C_RESET"; }

ui_menu_item() {
    printf '   %s%s)%s %s%s%s  %s%s%s\n' \
        "$C_ACCENT$C_BOLD" "$1" "$C_RESET" \
        "$C_BOLD" "$2" "$C_RESET" \
        "$C_GREY$C_DIM" "$3" "$C_RESET"
}

CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Homelab"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Homelab"

# Set by X-Linuxtool.sh when run from a local clone, to use scripts on disk.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Homelab}"

_download() {
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

while true; do
    clear 2>/dev/null
    ui_step "HomeLab"
    ui_rule
    ui_menu_item 1 "Install Docker" "Install Docker CE and add your user to the docker group"
    ui_menu_item 2 "Auto Update setup" "Set up automatic OS/package updates"
    ui_menu_item 3 "Docker Compose Updater" "Update running Docker Compose stacks"
    ui_menu_item 0 "Back" "Return to the main menu"
    printf '%s  ❯%s Enter your choice %s[0-3]%s: ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET"
    read choice || exit 0

    case $choice in
        0)
            ui_info "Returning to the main menu…"
            exit 0
            ;;
        1)
            ui_step "Install Docker"
            fetch_repo_file "Scripts/Docker/Docker-Install.sh" Docker-Install.sh || exit 1
            sudo bash Docker-Install.sh
            sudo rm Docker-Install.sh
            ;;
        2)
            ui_step "Server-Updater"
            fetch_repo_file "Scripts/Server-Updater.sh" Server-Updater.sh || exit 1
            sudo bash Server-Updater.sh
            sudo rm Server-Updater.sh
            ;;
        3)
            ui_step "Docker-Updater"
            fetch_repo_file "Scripts/Docker/Docker-Updater.sh" Docker-Updater.sh || exit 1
            sudo bash Docker-Updater.sh
            sudo rm Docker-Updater.sh
            ;;
        *)
            ui_err "Invalid choice."
            ;;
    esac

    printf '\n'
    printf '%s  ❯%s Press Enter to return to this menu…%s ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY"
    read -r _
    printf '%s' "$C_RESET"
done
