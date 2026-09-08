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

ui_step "Installing Flatpak apps"
flatpak install -y flathub \
        org.cryptomator.Cryptomator \
        com.bitwarden.desktop \
        org.localsend.localsend_app \
        com.github.zocker_160.SyncThingy \
        org.jellyfin.JellyfinDesktop \
        com.unicornsonlsd.finamp \
        org.gnome.World.Iotas \
        io.github.mfat.sshpilot \
        org.pvermeer.WebAppHub \
        io.missioncenter.MissionCenter
ui_ok "Flatpak apps installed."
