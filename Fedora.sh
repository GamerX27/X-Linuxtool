#!/bin/bash
# Script to choose between Fedora-Minimal.sh and Fedora-PostSetup.sh
echo "Choose a script to run:"
echo "1) Fedora-Minimal"
echo "2) Fedora-PostSetup"
echo "3) Fedora-Kionite-Setup"
echo -n "Enter your choice (1, 2, or 3): "
read choice

case $choice in
    1)
        echo "Downloading and running Fedora-Minimal.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-Minimal.sh -o /tmp/Fedora-Minimal.sh
        chmod +x /tmp/Fedora-Minimal.sh
        /tmp/Fedora-Minimal.sh
        rm -f /tmp/Fedora-Minimal.sh
        ;;
    2)
        echo "Downloading and running Fedora-PostSetup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-PostSetup.sh -o /tmp/Fedora-PostSetup.sh
        chmod +x /tmp/Fedora-PostSetup.sh
        /tmp/Fedora-PostSetup.sh
        rm -f /tmp/Fedora-PostSetup.sh
        ;;
    3)
        echo "Downloading and running Fedora-Kionite-Setup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-Kionite-Setup.sh -o /tmp/Fedora-Kionite-Setup.sh
        chmod +x /tmp/Fedora-Kionite-Setup.sh
        /tmp/Fedora-Kionite-Setup.sh
        rm -f /tmp/Fedora-Kionite-Setup.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
