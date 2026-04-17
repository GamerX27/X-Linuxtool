#!/bin/bash
echo "Choose a script to download and run:"
echo "1) Fedora Desktop"
echo "2) HomeLab"
echo "3) Brave Debloat"
echo "4) Kron4ek Wine Installer"
echo "5) Proton CachyOS Installer"
echo "6) Gigabyte Sleep Fix"
echo "7) Custom Fastfetch Config"
read -p "Enter your choice (1, 2, 3, 4, 5, 6, or 7): " choice

case $choice in
    1)
        echo "Downloading and running Fedora Desktop..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Fedora.sh
        sudo bash Fedora.sh
        sudo rm Fedora.sh
        ;;
    2)
        echo "Downloading and running for HomeLab..."
        wget https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main/X27-Homelab.sh
        sudo bash X27-Homelab.sh
        sudo rm X27-Homelab.sh
        ;;
    3)
        echo "Downloading and running Brave Debloat..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh
        sudo bash make_brave_great_again.sh
        sudo rm make_brave_great_again.sh
        ;;
    4)
        echo "Downloading and running Kron4ek Wine Installer..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/Kron4ek-wine-installer.sh
        bash Kron4ek-wine-installer.sh
        rm Kron4ek-wine-installer.sh
        ;;
    5)
        echo "Downloading and running Proton CachyOS Installer..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/proton-cachyos-installer.sh
        bash proton-cachyos-installer.sh
        rm proton-cachyos-installer.sh
        ;;
    6)
        echo "Downloading and running Gigabyte Sleep Fix..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Tools/GigabyteSleep-Fix.sh
        sudo bash GigabyteSleep-Fix.sh
        sudo rm GigabyteSleep-Fix.sh
        ;;
    7)
        echo "Downloading and running Fastfetch Config Update..."
        wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Tools/fsfetch.sh
        bash fsfetch.sh
        rm fsfetch.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
