#!/bin/bash

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_MAGENTA=$'\033[35m'
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

detect_user() {
    if [ -n "$SUDO_USER" ]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
        CURRENT_USER="$SUDO_USER"
    else
        CURRENT_USER=$(whoami)
        USER_HOME=$(eval echo ~$CURRENT_USER)
    fi

    if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
        ui_err "Could not determine user home directory"
        exit 1
    fi

    ui_info "Using user: $CURRENT_USER with home directory: $USER_HOME"
}

detect_user

mkdir -p "$USER_HOME/.config/fastfetch" || { ui_err "Could not navigate or create directory"; exit 1; }

wget https://raw.githubusercontent.com/GamerX27/X27-Fastfetch-Config/main/fastfetch/config.jsonc -O "$USER_HOME/.config/fastfetch/config.jsonc" || { ui_err "Could not download config file"; exit 1; }

ui_info "Installing Symbols Nerd Font Mono (icon fallback font)..."

mkdir -p "$USER_HOME/.local/share/fonts" || { ui_err "Could not create fonts directory"; exit 1; }

wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.tar.xz -O /tmp/NerdFontsSymbolsOnly.tar.xz || { ui_err "Could not download Nerd Font symbols pack"; exit 1; }

tar -xf /tmp/NerdFontsSymbolsOnly.tar.xz -C "$USER_HOME/.local/share/fonts" SymbolsNerdFontMono-Regular.ttf || { ui_err "Could not extract Nerd Font symbols pack"; exit 1; }

rm -f /tmp/NerdFontsSymbolsOnly.tar.xz

fc-cache -f "$USER_HOME/.local/share/fonts" >/dev/null 2>&1

ui_ok "Close your terminal and reopen it to see the changes."