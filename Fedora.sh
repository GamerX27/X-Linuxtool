#!/bin/bash

echo "Choose a script to run:"
echo "1) Fedora Post-Setup"
echo "2) Fedora-Kionite-Setup"
echo "3) Bazzite Setup"
echo -n "Enter your choice (1, 2, or 3): "
read choice

case $choice in
    1)
        echo "Downloading and running Fedora-PostSetup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-PostSetup.sh -o /tmp/Fedora-PostSetup.sh
        chmod +x /tmp/Fedora-PostSetup.sh
        bash /tmp/Fedora-PostSetup.sh
        rm -f /tmp/Fedora-PostSetup.sh
        ;;
    2)
        echo "Downloading and running Fedora-Kionite-Setup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-Kionite-Setup.sh -o /tmp/Fedora-Kionite-Setup.sh
        chmod +x /tmp/Fedora-Kionite-Setup.sh
        /tmp/Fedora-Kionite-Setup.sh
        rm -f /tmp/Fedora-Kionite-Setup.sh
        ;;
    3)
        echo "Downloading and running Bazzite-Setup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Bazzite/Bazzite-Setup.sh -o /tmp/Bazzite-Setup.sh
        chmod +x /tmp/Bazzite-Setup.sh
        /tmp/Bazzite-Setup.sh
        rm -f /tmp/Bazzite-Setup.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
