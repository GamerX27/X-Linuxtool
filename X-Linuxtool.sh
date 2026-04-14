```sh /home/sindre/Documents/Code/Prosjekter/X-Linuxtool/X-Linuxtool.sh
#!/bin/bash
echo "Choose a script to download and run:"
echo "1) Fedora Desktop"
echo "2) HomeLab"
echo "3) Brave Debloat"
echo "4) Kron4ek Wine Installer"
echo "5) Proton CachyOS Installer"
echo "6) Gigabyte Sleep Fix"
read -p "Enter your choice (1, 2, 3, 4, 5, or 6): " choice

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
        /tmp/make_brave_Great_again.sh
        rm -f /tmp/make_brave_great_again.sh
        ;;
    4)
        echo "Downloading and running Kron4ek Wine Installer..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/Kron4ek-wine-installer.sh -o /tmp/Kron4ek-wine-installer.sh
        chmod +x /tmp/Kron4ek-wine-installer.sh
        /tmp/Kron4ek-wine-installer.sh
        rm -f /tmp/Kron4ek-wine-installer.sh
        ;;
    5)
        echo "Downloading and running Proton CachyOS Installer..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/proton-cachyos-installer.sh -o /tmp/proton-cachyos-installer.sh
        chmod +x /tmp/proton-cachyos-installer.sh
        /tmp/proton-cachyos-installer.sh
        rm -f /tmp/proton-cachyos-installer.sh
        ;;
    6)
        echo "Downloading and running Gigabyte Sleep Fix..."
        curl -sSL https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Tools/GigabyteSleep-Fix.sh -o /tmp/GigabyteSleep-Fix.sh
        chmod +x /tmp/GigabyteSleep-Fix.sh
        /tmp/GigabyteSleep-Fix.sh
        rm -f /tmp/GigabyteSleep-Fix.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
