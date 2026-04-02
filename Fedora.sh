#!/bin/bash
# Script to choose between Fedora-Minimal.sh and Fedora-PostSetup.sh
echo "Choose a script to run:"
echo "1) Fedora-Minimal"
echo "2) Fedora-PostSetup"
echo "3) Fedora-Kionite-Setup"
echo -n "Enter your choice (1 or 2): "
read choice

case $choice in
    1)
        echo "Running Fedora-Minimal.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-Minimal.sh | bash
        ;;
    2)
        echo "Running Fedora-PostSetup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-PostSetup.sh | bash
        ;;
    3)
        echo "Running Fedora-Kionite-Setup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora/Fedora-Kionite-Setup.sh | bash
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac