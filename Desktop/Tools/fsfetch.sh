#!/bin/bash

# Function to detect current user
detect_user() {
    # Try to get the actual user who ran sudo
    if [ -n "$SUDO_USER" ]; then
        # If running with sudo, use the original user
        USER_HOME=$(eval echo ~$SUDO_USER)
        CURRENT_USER="$SUDO_USER"
    else
        # If running as regular user, use current user
        CURRENT_USER=$(whoami)
        USER_HOME=$(eval echo ~$CURRENT_USER)
    fi
    
    # Validate that we have a valid home directory
    if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
        echo "Error: Could not determine user home directory" >&2
        exit 1
    fi
    
    echo "Using user: $CURRENT_USER with home directory: $USER_HOME"
}

# Detect current user
detect_user

# Navigate to .config directory and create fastfetch folder if it doesn't exist
mkdir -p "$USER_HOME/.config/fastfetch" || { echo "Error: Could not navigate or create directory"; exit 1; }

# Generate default configuration in fastfetch directory
fastfetch --gen-config "$USER_HOME/.config/fastfetch/config.jsonc" || { echo "Error: Could not generate default config"; exit 1; }

# Remove the generated default config file if it exists
rm -f "$USER_HOME/.config/fastfetch/config.jsonc"

# Download updated config from GitHub
wget https://raw.githubusercontent.com/harilvfs/fastfetch/refs/heads/old-days/fastfetch/config.jsonc -O "$USER_HOME/.config/fastfetch/config.jsonc" || { echo "Error: Could not download config file"; exit 1; }

# Notify the user to close and reopen terminal
echo "Close your terminal and reopen it to see the changes."