#all credits go to Piotr Pliszko
#source: https://pliszko.com/blog/post/2025-07-31-fixing-instant-wake-from-suspend-on-gigabyte-motherboards-on-arch-linux
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

ui_info "Creating systemd service to disable GPP0 on boot..."
sudo bash -c 'cat > /etc/systemd/system/wakeup-disable-GPP0.service <<EOF
[Unit]
Description=Disable GPP0 as ACPI wakeup source
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "echo GPP0 > /proc/acpi/wakeup"

[Install]
WantedBy=multi-user.target
EOF'

ui_info "Enabling the service..."
sudo systemctl enable wakeup-disable-GPP0.service

ui_ok "Done! GPP0 will now be disabled as a wakeup source on every boot."
