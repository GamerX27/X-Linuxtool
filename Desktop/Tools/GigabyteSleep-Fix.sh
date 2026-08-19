#all credits go to Piotr Pliszko
#source: https://pliszko.com/blog/post/2025-07-31-fixing-instant-wake-from-suspend-on-gigabyte-motherboards-on-arch-linux
#!/bin/bash

# Script to permanently fix GPP0 wakeup issue

# Step 1: Create a systemd service for a permanent fix
echo "Creating systemd service to disable GPP0 on boot..."
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

# Step 2: Enable the service
echo "Enabling the service..."
sudo systemctl enable wakeup-disable-GPP0.service

echo "Done! GPP0 will now be disabled as a wakeup source on every boot."
