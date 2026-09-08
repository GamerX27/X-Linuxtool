#!/bin/bash

set -e

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

SERVICE_FILE="/etc/systemd/system/flatpak-update.service"
TIMER_FILE="/etc/systemd/system/flatpak-update.timer"

if [[ $EUID -ne 0 ]]; then
   ui_err "This script must be run as root (use sudo)."
   exit 1
fi

if [ -f "$SERVICE_FILE" ] && [ -f "$TIMER_FILE" ]; then
    ui_warn "Flatpak auto-update service and timer already exist. Skipping deployment."
    exit 0
fi

ui_info "Creating service file..."
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Update Flatpaks at boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/flatpak update -y
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

ui_info "Creating timer file..."
cat <<EOF > "$TIMER_FILE"
[Unit]
Description=Run Flatpak update 30 seconds after boot

[Timer]
OnBootSec=30s
Persistent=false

[Install]
WantedBy=timers.target
EOF

ui_info "Reloading systemd daemon..."
systemctl daemon-reload

ui_info "Enabling and starting the timer..."
systemctl enable --now flatpak-update.timer

ui_ok "Flatpak auto-update service and timer deployed successfully."
