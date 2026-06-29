#!/bin/bash

# --- Piped execution support ------------------------------------------------
# This script is designed to be run directly from the web, e.g.:
#   curl -fsSL https://raw.githubusercontent.com/GamerX27/X-Linuxtool/refs/heads/main/X-Linuxtool.sh | bash
#   curl -fsSL https://codeberg.org/X27/X-Linuxtool/raw/branch/main/X-Linuxtool.sh | bash
#
# When piped into bash, bash reads THIS script from stdin (the pipe), so we
# must not redirect the whole script's stdin away from it. Instead, point
# interactive commands (the menu and any sub-scripts) at the controlling
# terminal individually via $INPUT. When a terminal isn't available we fall
# back to the normal stdin.
if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

# --- Theme / colors ---------------------------------------------------------
# Only enable colors when writing to a terminal that supports them, so piped
# or redirected output stays clean.
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[38;5;203m'
    C_GREEN=$'\033[38;5;114m'
    C_YELLOW=$'\033[38;5;221m'
    C_BLUE=$'\033[38;5;75m'
    C_MAGENTA=$'\033[38;5;176m'
    C_CYAN=$'\033[38;5;80m'
    C_GREY=$'\033[38;5;245m'
    C_ACCENT=$'\033[38;5;147m'
else
    C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
    C_BLUE="" C_MAGENTA="" C_CYAN="" C_GREY="" C_ACCENT=""
fi

# --- UI helpers -------------------------------------------------------------
ui_banner() {
    local width=46
    # Center a plain (ASCII) string inside the box and print it as a row.
    _bline() {
        local text="$1" color="$2" len pad_l pad_r
        len=${#text}
        pad_l=$(( (width - len) / 2 ))
        pad_r=$(( width - len - pad_l ))
        printf '%s║%s%*s%s%s%s%*s%s║%s\n' \
            "$C_CYAN$C_BOLD" "$C_RESET" "$pad_l" "" \
            "$color" "$text" "$C_RESET" "$pad_r" "" \
            "$C_CYAN$C_BOLD" "$C_RESET"
    }
    local bar
    bar=$(printf '═%.0s' $(seq 1 "$width"))

    printf '\n'
    printf '%s╔%s╗%s\n' "$C_CYAN$C_BOLD" "$bar" "$C_RESET"
    _bline "" ""
    _bline "X 2 7   T O O L B O X" "$C_ACCENT$C_BOLD"
    _bline "Linux desktop · homelab · gaming" "$C_GREY"
    _bline "" ""
    printf '%s╚%s╝%s\n' "$C_CYAN$C_BOLD" "$bar" "$C_RESET"
    printf '%s          all-in-one installer & setup tool%s\n\n' "$C_GREY" "$C_RESET"
}

ui_rule() {
    printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
}

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }

ui_menu_item() {
    # ui_menu_item <number> <icon> <label>
    printf '   %s%s)%s %s  %s%s%s\n' \
        "$C_ACCENT$C_BOLD" "$1" "$C_RESET" "$2" "$C_BOLD" "$3" "$C_RESET"
}

# --- Repository locations ---------------------------------------------------
# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CB_TOOLBOX="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main"
GH_TOOLBOX="https://raw.githubusercontent.com/GamerX27/X27-Linux-Desktop-Toolbox/main"

CB_HOMELAB="https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main"
GH_HOMELAB="https://raw.githubusercontent.com/GamerX27/X27-Homelab-ToolBox/main"

CB_YTDLP="https://codeberg.org/X27/YTDLP-Easy-Script/raw/branch/main"
GH_YTDLP="https://raw.githubusercontent.com/GamerX27/YTDLP-Easy-Script/main"

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

fetch_file() {
    # fetch_file <codeberg-url> <github-url> <output-file>
    # Downloads from Codeberg (primary); falls back to the GitHub mirror.
    local cb="$1" gh="$2" out="$3"

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
        sudo $pkg_manager update -y &> /dev/null
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

# --- Main -------------------------------------------------------------------
clear 2>/dev/null
ui_banner

# Run dependency check before showing choices
check_and_install_dependencies

ui_step "Choose a script to download and run"
ui_rule
ui_menu_item 1 "🐧" "Fedora Desktop"
ui_menu_item 2 "🏠" "HomeLab"
ui_menu_item 3 "🦁" "Brave Debloat"
ui_menu_item 4 "🎬" "YT-DLP-Easy Installer"
ui_menu_item 5 "🍷" "Kron4ek Wine Installer"
ui_menu_item 6 "🎮" "Proton CachyOS Installer"
ui_menu_item 7 "💤" "Gigabyte Sleep Fix"
ui_menu_item 8 "⚡" "Custom Fastfetch Config"
ui_menu_item 9 "🖥️ " "Virtualization Setup"
ui_rule
printf '%s  ❯%s Enter your choice %s[1-9]%s: ' "$C_CYAN$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET"
read -r choice < "$INPUT"

case $choice in
    1)
        ui_step "Fedora Desktop"
        fetch_file "${CB_TOOLBOX}/Fedora.sh" "${GH_TOOLBOX}/Fedora.sh" /tmp/Fedora.sh || exit 1
        sudo bash /tmp/Fedora.sh < "$INPUT"
        sudo rm -f /tmp/Fedora.sh
        ;;
    2)
        ui_step "HomeLab"
        fetch_file "${CB_HOMELAB}/X27-Homelab.sh" "${GH_HOMELAB}/X27-Homelab.sh" /tmp/X27-Homelab.sh || exit 1
        sudo bash /tmp/X27-Homelab.sh < "$INPUT"
        sudo rm -f /tmp/X27-Homelab.sh
        ;;
    3)
        ui_step "Brave Debloat"
        fetch_file "${CB_TOOLBOX}/Browser/make_brave_great_again.sh" "${GH_TOOLBOX}/Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh || exit 1
        sudo bash /tmp/make_brave_great_again.sh < "$INPUT"
        sudo rm -f /tmp/make_brave_great_again.sh
        ;;
    4)
        ui_step "YT-DLP-Easy Installer"
        fetch_file "${CB_YTDLP}/Install-YT-DLP-Easy.sh" "${GH_YTDLP}/Install-YT-DLP-Easy.sh" /tmp/Install-YT-DLP-Easy.sh || exit 1
        bash /tmp/Install-YT-DLP-Easy.sh < "$INPUT"
        sudo rm -f /tmp/Install-YT-DLP-Easy.sh
        ;;
    5)
        ui_step "Kron4ek Wine Installer"
        fetch_file "${CB_TOOLBOX}/Gaming/Kron4ek-wine-installer.sh" "${GH_TOOLBOX}/Gaming/Kron4ek-wine-installer.sh" /tmp/Kron4ek-wine-installer.sh || exit 1
        bash /tmp/Kron4ek-wine-installer.sh < "$INPUT"
        rm -f /tmp/Kron4ek-wine-installer.sh
        ;;
    6)
        ui_step "Proton CachyOS Installer"
        fetch_file "${CB_TOOLBOX}/Gaming/proton-cachyos-installer.sh" "${GH_TOOLBOX}/Gaming/proton-cachyos-installer.sh" /tmp/proton-cachyos-installer.sh || exit 1
        bash /tmp/proton-cachyos-installer.sh < "$INPUT"
        rm -f /tmp/proton-cachyos-installer.sh
        ;;
    7)
        ui_step "Gigabyte Sleep Fix"
        fetch_file "${CB_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" "${GH_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" /tmp/GigabyteSleep-Fix.sh || exit 1
        sudo bash /tmp/GigabyteSleep-Fix.sh < "$INPUT"
        sudo rm -f /tmp/GigabyteSleep-Fix.sh
        ;;
    8)
        ui_step "Custom Fastfetch Config"
        fetch_file "${CB_TOOLBOX}/Tools/fsfetch.sh" "${GH_TOOLBOX}/Tools/fsfetch.sh" /tmp/fsfetch.sh || exit 1
        bash /tmp/fsfetch.sh < "$INPUT"
        rm -f /tmp/fsfetch.sh
        ;;
    9)
        ui_step "Virtualization Setup"
        fetch_file "${CB_TOOLBOX}/Tools/Virtualization_Setup.sh" "${GH_TOOLBOX}/Tools/Virtualization_Setup.sh" /tmp/Virtualization_Setup.sh || exit 1
        sudo bash /tmp/Virtualization_Setup.sh < "$INPUT"
        sudo rm -f /tmp/Virtualization_Setup.sh
        ;;
    *)
        ui_err "Invalid choice. Exiting."
        exit 1
        ;;
esac
