#!/bin/bash

# Script to run X27-Scripts for servers

echo "Choose a script to run:"
echo "1) Install Docker"
echo "2) Auto Update setup"
echo -n "Enter your choice (1 or 2): "
read choice

case $choice in
    1)
        echo "Running Install Docker"
        curl -sSL https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/Servers/Docker-Install.sh | bash
        ;;
    2)
        echo "Running Fedora-PostSetup.sh..."
        curl -sSL https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/Servers/Server-Updater.sh | bash
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac