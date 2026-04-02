#!/bin/bash

echo "Choose a script to download and run:"
echo "1) Fedora Desktop"
echo "2) HomeLab"
echo "3) Brave Debloat"
read -p "Enter your choice (1, 2, or 3): " choice

case $choice in
    1)
        echo "Downloading and running Fedora Desktop..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora.sh -o /tmp/Fedora.sh
        chmod +x /tmp/Fedora.sh
        /tmp/Fedora.sh
        rm -f /tmp/Fedora.sh
        ;;
    2)
        echo "Downloading and running for HomeLab..."
        curl -sSL https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/X27-Homelab.sh -o /tmp/X27-Homelab.sh
        chmod +x /tmp/X27-Homelab.sh
        /tmp/X27-Homelab.sh
        rm -f /tmp/X27-Homelab.sh
        ;;
    3)
        echo "Downloading and running Brave Debloat..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/commit/3f97124547ce8eef805d34024579f7b047397afe/Browser/make_brave_great_again.sh -o /tmp/make_brave_great_again.sh
        chmod +x /tmp/make_brave_great_again.sh
        /tmp/make_brave_great_again.sh
        rm -f /tmp/make_brave_great_again.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac