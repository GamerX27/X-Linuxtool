# ==============================================================================
# SCRIPT SEGMENT: Finalization, Automation, and Reboot
# Description: Configures rpm-ostree automation, performs final system upgrade,
#              sets locale, and triggers a system reboot.
# ==============================================================================

# --- 3. RPM-OSTree Automatic Updates ---
info "Configuring rpm-ostree automatic updates..."

# Using 'tee' ensures sudo handles the file write correctly in an immutable environment
sudo tee /etc/rpm-ostreed.conf > /dev/null <<EOF
[Daemon]
AutomaticUpdatePolicy=stage
EOF

# Attempt to reload the daemon; if it fails, we assume it needs a fresh start via the timer
sudo systemctl reload rpm-ostreed 2>/dev/null || warn "rpm-ostreed service not active or reload failed (will rely on timer)."
sudo systemctl enable --now rpm-ostree-automatic.timer

# --- 6. Final System Upgrade ---
info "Performing final system upgrade..."
info "This may take several minutes depending on your connection and hardware."

# We add a small buffer to ensure previous filesystem writes are flushed
sleep 5

# Perform the actual deployment upgrade
if sudo rpm-ostree upgrade; then
    info "System upgrade command completed successfully."
else
    warn "rpm-ostree upgrade encountered an issue. Check logs with 'journalctl -xe'."
fi

# --- 7. Update Locale Time ---
# Defined as a function for clean execution flow
set_locale_time() {
    echo -e "\e[32m[INFO]\e[0m Attempting to set LC_TIME to C.UTF-8..."
    if sudo localectl set-locale LC_TIME=C.UTF-8; then
        echo -e "\e[32m[INFO]\e[0m Successfully set LC_TIME."
    else
        echo -e "\e[31m[ERROR]\e[0m Failed to set the locale time. Check permissions or localectl status." >&2
        return 1
    fi
}

set_locale_time

# --- 8. Final Shutdown/Reboot Sequence ---
info "Setup Complete! Preparing for system reboot..."
info "The system will reboot in 10 seconds. Save all work now!"

# Countdown to give the user a chance to cancel (Ctrl+C) if running manually
for i in {10..1}; do
    echo -ne "Rebooting in $i... \r"
    sleep 1
done

echo -e "\n\e[31m[REBOOTING]\e[0m System is restarting to apply all changes."
sudo reboot
