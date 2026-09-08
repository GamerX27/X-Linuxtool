#!/bin/bash

# Designed to run via `curl | bash`, which means bash reads THIS script from
# stdin — so we can't redirect stdin away from it wholesale. Interactive
# commands (menu + sub-scripts) instead read from $INPUT, which points at
# the controlling terminal when one exists.
if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

# Dispatched sub-scripts get stdout forced onto the same real terminal device
# used for INPUT, not just whatever fd they'd otherwise inherit. dnf (and
# other tools with a live progress bar) only draws it when stdout is a real
# tty, and this guarantees one all the way down the dispatch chain regardless
# of how X-Linuxtool.sh itself was invoked (local, curl | bash, etc.).
if [ -w /dev/tty ]; then
    OUTPUT=/dev/tty
else
    OUTPUT=/dev/stdout
fi

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
            # Nearest 256-color approximations of the Nord palette.
            C_CYAN=$'\033[38;5;116m'    # nord8  88c0d0
            C_BLUE=$'\033[38;5;110m'    # nord9  81a1c1
            C_RED=$'\033[38;5;167m'     # nord11 bf616a
            C_YELLOW=$'\033[38;5;222m'  # nord13 ebcb8b
            C_GREEN=$'\033[38;5;150m'   # nord14 a3be8c
            C_MAGENTA=$'\033[38;5;139m' # nord15 b48ead
            ;;
        *)
            C_CYAN=$'\033[38;2;136;192;208m'   # nord8  88c0d0
            C_BLUE=$'\033[38;2;129;161;193m'   # nord9  81a1c1
            C_RED=$'\033[38;2;191;97;106m'     # nord11 bf616a
            C_YELLOW=$'\033[38;2;235;203;139m' # nord13 ebcb8b
            C_GREEN=$'\033[38;2;163;190;140m'  # nord14 a3be8c
            C_MAGENTA=$'\033[38;2;180;142;173m' # nord15 b48ead
            ;;
    esac
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN=""
fi

ui_banner() {
    printf '\n%s  X 2 7   T O O L B O X%s\n' "$C_BOLD" "$C_RESET"
    printf '%s  Linux desktop · homelab · gaming%s\n\n' "$C_CYAN" "$C_RESET"
}

ui_rule()    { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }
ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }

ui_menu_item() {
    printf '   %s%s)%s %s\n' "$C_BOLD" "$1" "$C_RESET" "$2"
}

# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CB_BASE="https://codeberg.org/X27/X-Linuxtool/raw/branch/main"
GH_BASE="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main"

CB_TOOLBOX="${CB_BASE}/Desktop"
GH_TOOLBOX="${GH_BASE}/Desktop"

CB_TOOLS="${CB_BASE}/Tools"
GH_TOOLS="${GH_BASE}/Tools"

CB_HOMELAB="${CB_BASE}/Homelab"
GH_HOMELAB="${GH_BASE}/Homelab"

CB_YTDLP="https://codeberg.org/X27/YTDLP-Easy-Script/raw/branch/main"
GH_YTDLP="https://raw.githubusercontent.com/GamerX27/YTDLP-Easy-Script/main"

# When run from a local clone (not `curl | bash`), use the scripts already on
# disk instead of re-downloading them. Exported so the sub-scripts we spawn
# below (which run from /tmp and can't find local files via their own path)
# know where the clone lives too.
LOCAL_ROOT=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -d "$LOCAL_ROOT/Desktop" ] && [ -d "$LOCAL_ROOT/Homelab" ] || LOCAL_ROOT=""
fi
export X27_LOCAL_ROOT="$LOCAL_ROOT"

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

fetch_file() {
    local cb="$1" gh="$2" out="$3" local_rel="$4"

    if [ -n "$LOCAL_ROOT" ] && [ -n "$local_rel" ] && [ -f "$LOCAL_ROOT/$local_rel" ]; then
        ui_info "Using local copy: ${local_rel}" >&2
        cp "$LOCAL_ROOT/$local_rel" "$out"
        return 0
    fi

    ui_info "Fetching from Codeberg…" >&2
    if _download "$cb" "$out"; then
        ui_ok "Downloaded from Codeberg." >&2
        return 0
    fi

    ui_warn "Codeberg unreachable; falling back to GitHub mirror…" >&2
    if _download "$gh" "$out"; then
        ui_ok "Downloaded from GitHub mirror." >&2
        return 0
    fi

    ui_err "Could not download from Codeberg or GitHub."
    return 1
}

check_and_install_dependencies() {
    local dependencies=("wget" "git" "curl")
    local pkg_manager=""

    if command -v apt &> /dev/null; then
        pkg_manager="apt"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    fi

    if [ -z "$pkg_manager" ]; then
        ui_warn "Unsupported package manager. Ensure wget, git, and curl are installed manually."
        return 0
    fi

    ui_step "Checking dependencies"
    ui_info "Required: ${dependencies[*]}"
    local missing_deps=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        ui_warn "Missing: ${missing_deps[*]} — installing via $pkg_manager…"
        sudo $pkg_manager install -y "${missing_deps[@]}"
        if [ $? -eq 0 ]; then
            ui_ok "Dependencies installed successfully."
        else
            ui_err "Failed to install dependencies. Please install them manually."
            exit 1
        fi
    else
        ui_ok "All dependencies are already installed."
    fi
}

clear 2>/dev/null
ui_banner

check_and_install_dependencies

while true; do
    clear 2>/dev/null
    ui_banner

    ui_step "Choose a script to download and run"
    ui_rule
    ui_menu_item 1  "Desktop-Linux"
    ui_menu_item 2  "HomeLab"
    ui_menu_item 3  "YT-DLP"
    ui_menu_item 4  "Fastfetch"
    ui_menu_item 5  "Virtualization"
    ui_menu_item 0  "Exit"
    printf '%s  ❯%s Enter your choice [0-5]: ' "$C_BOLD" "$C_RESET"
    read -r choice < "$INPUT"

    if [ -z "$choice" ] || [ "$choice" -eq 0 ] 2>/dev/null; then
        clear 2>/dev/null
        ui_ok "Goodbye."
        exit 0
    fi

    clear 2>/dev/null

    case $choice in
        1)
            ui_step "Desktop-Linux"
            # Run as the normal user (NOT with sudo): Fedora.sh dispatches to
            # per-option sub-scripts that each handle privilege escalation
            # themselves as needed (Fedora-PostSetup.sh requests sudo internally
            # for its per-user steps; most other sub-scripts are invoked by
            # Fedora.sh with sudo directly).
            fetch_file "${CB_TOOLBOX}/Scripts/Fedora.sh" "${GH_TOOLBOX}/Scripts/Fedora.sh" /tmp/Fedora.sh "Desktop/Scripts/Fedora.sh" || exit 1
            bash /tmp/Fedora.sh < "$INPUT" > "$OUTPUT"
            rm -f /tmp/Fedora.sh
            ;;
        2)
            ui_step "HomeLab"
            fetch_file "${CB_HOMELAB}/X27-Homelab.sh" "${GH_HOMELAB}/X27-Homelab.sh" /tmp/X27-Homelab.sh "Homelab/X27-Homelab.sh" || exit 1
            sudo bash /tmp/X27-Homelab.sh < "$INPUT" > "$OUTPUT"
            sudo rm -f /tmp/X27-Homelab.sh
            ;;
        3)
            ui_step "YT-DLP"
            fetch_file "${CB_YTDLP}/Install-YT-DLP-Easy.sh" "${GH_YTDLP}/Install-YT-DLP-Easy.sh" /tmp/Install-YT-DLP-Easy.sh || exit 1
            bash /tmp/Install-YT-DLP-Easy.sh < "$INPUT" > "$OUTPUT"
            sudo rm -f /tmp/Install-YT-DLP-Easy.sh
            ;;
        4)
            ui_step "Fastfetch"
            fetch_file "${CB_TOOLS}/fsfetch.sh" "${GH_TOOLS}/fsfetch.sh" /tmp/fsfetch.sh "Tools/fsfetch.sh" || exit 1
            bash /tmp/fsfetch.sh < "$INPUT" > "$OUTPUT"
            rm -f /tmp/fsfetch.sh
            ;;
        5)
            ui_step "Virtualization"
            fetch_file "${CB_TOOLS}/Virtualization_Setup.sh" "${GH_TOOLS}/Virtualization_Setup.sh" /tmp/Virtualization_Setup.sh "Tools/Virtualization_Setup.sh" || exit 1
            sudo bash /tmp/Virtualization_Setup.sh < "$INPUT" > "$OUTPUT"
            sudo rm -f /tmp/Virtualization_Setup.sh
            ;;
        *)
            ui_err "Invalid choice."
            ;;
    esac

    printf '\n'
    printf '%s  ❯%s Press Enter to return to the main menu… ' "$C_BOLD" "$C_RESET"
    read -r _ < "$INPUT"
    printf '%s' "$C_RESET"
done
