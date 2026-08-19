#!/bin/bash

# Stop script immediately if any command fails
set -e

SERVICE_FILE="/etc/systemd/system/flatpak-update.service"
TIMER_FILE="/etc/systemd/system/flatpak-update.timer"

# Check if we have root privileges (needed to write to /etc/)
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)."
   exit 1
fi

# 1. Check if files already exist
if [ -f "$SERVICE_FILE" ] && [ -f "$TIMER_FILE" ]; then
    echo "Flatpak auto-update service and timer already exist. Skipping deployment."
    exit 0
fi

# 2. Create the systemd service file
echo "Creating service file..."
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

# Create the systemd timer file
echo "Creating timer file..."
cat <<EOF > "$TIMER_FILE"
[Unit]
Description=Run Flatpak update 30 seconds after boot

[Timer]
OnBootSec=30s
Persistent=false

[Install]
WantedBy=timers.target
EOF

# Reload systemd to recognize new files
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the timer
echo "Enabling and starting the timer..."
systemctl enable --now flatpak-update.timer

# 3. Final confirmation
echo "Flatpak auto-update service and timer deployed successfully."
