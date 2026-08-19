#!/bin/bash

# Script to run X27-Scripts for servers

echo "Choose a script to run:"
echo "1) Install Docker"
echo "2) Auto Update setup"
echo "3) Docker Compose Updater"
echo -n "Enter your choice (1, 2 or 3): "
read choice

case $choice in
    1)
        echo "Running Install Docker"
        wget https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/Scripts/Docker/Docker-Install.sh
        sudo bash Docker-Install.sh
        sudo rm Docker-Install.sh
        ;;
    2)
        echo "Running Server-Updater.sh..."
        wget https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/Scripts/Server-Updater.sh
        sudo bash Server-Updater.sh
        sudo rm Server-Updater.sh
        ;;
    3)
        echo "Running Docker-Updater.sh..."
        wget https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/Scripts/Docker/Docker-Updater.sh
        sudo bash Docker-Updater.sh
        sudo rm Docker-Updater.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
