#!/bin/bash

# Define paths
BIN_DIR="$HOME/.local/bin"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SCRIPT_PATH="$BIN_DIR/flatpak-autoupdate.sh"
SERVICE_PATH="$SYSTEMD_USER_DIR/flatpak-update.service"
TIMER_PATH="$SYSTEMD_USER_DIR/flatpak-update.timer"

# Create directories if they do not exist
mkdir -p "$BIN_DIR"
mkdir -p "$SYSTEMD_USER_DIR"

# Create the actual update logic script
cat << 'EOF' > "$SCRIPT_PATH"
#!/bin/bash

# Run the flatpak update command and capture both output and errors
output=$(flatpak update -y 2>&1)
exit_code=$?

if [ $exit_code -eq 0 ]; then
    # If everything went well, send a success notification
    notify-send "Flatpak Update" "All applications are up to date."
else
    # Extract the first line of error for the notification to avoid text overflow
    error_summary=$(echo "$output" | head -n 1)
    notify-send "Flatpak Update Error" "An error occurred: $error_summary"
fi
EOF

# Make the logic script executable
chmod +x "$SCRIPT_PATH"

# Create the systemd service file
cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Update Flatpaks automatically

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH

[Install]
WantedBy=default.target
EOF

# Create the systemd timer file
# OnCalendar=daily ensures it runs every day
# OnBootSec=15min ensures that if the machine was just turned on, it waits 15 minutes
cat << EOF > "$TIMER_PATH"
[Unit]
Description=Run Flatpak update daily and 15 minutes after boot

[Timer]
OnCalendar=daily
OnBootSec=15min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload the systemd user daemon to recognize new files
systemctl --user daemon-reload

# Enable and start the timer
systemctl --user enable flatpak-update.timer
systemctl --user start flatpak-update.timer

echo "Setup complete. The Flatpak auto-updater is now active."
