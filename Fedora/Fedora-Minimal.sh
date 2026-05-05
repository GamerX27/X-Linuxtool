#!/bin/bash

# ==============================================================================
# 1. MANDATORY ROOT CHECK (THE "HARD STOP")
# This prevents the script from attempting any commands if not run with sudo.
# ==============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "##################################################################"
   echo "ERROR: THIS SCRIPT REQUIRES ROOT PRIVILEGES."
   echo "Please run it using: sudo ./Fedora-Minimal.sh"
   echo "##################################################################"
   exit 1
fi

echo "Starting Fedora Post-Setup..."

# ==============================================================================
# 2. REPOSITORY UPDATES
# ==============================================================================
echo "Updating and refreshing repositories..."
dnf update --refresh && dnf upgrade -y

# ==============================================================================
# 3. DESKTOP ENVIRONMENT (KDE)
# ==============================================================================
echo "Installing KDE Desktop..."
dnf group install -y kde-desktop
systemctl enable sddm
systemctl set-default graphical.target

# ==============================================================================
# 4. RPM FUSION REPOSITORIES
# ==============================================================================
echo "Installing RPM Fusion repositories..."
dnf install -y \
https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-notfree-release-$(rpm -E %fedora).noarch.rpm

dnf update -y @core
dnf install -y libavcodec-freeworld
dnf group install -y multimedia

# ==============================================================================
# 5. HARDWARE ACCELERATION
# ==============================================================================
swap_amd() {
    echo "Swapping to AMD drivers..."
    dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
}

swap_intel() {
    echo "Installing Intel drivers..."
    dnf install -y intel-media-driver
}

skip_swap() {
    echo "Skipping driver swaps."
}

echo ""
echo "Select Video Acceleration Option:"
echo "1. AMD"
echo "2. Intel"
echo "3. None"
# The < /dev/tty is critical here to prevent the script from eating its own input
read -p "Enter your choice (1/2/3): " choice < /dev/tty

case $choice in
    1) swap_amd ;;
    2) swap_intel ;;
    3) skip_swap ;;
    *) echo "Invalid choice. Skipping hardware acceleration step." ;;
esac

# ==============================================================================
# 6. UTILITIES & CORE APPS
# ==============================================================================
echo "Installing system utilities and core apps..."
dnf install wget fastfetch fish htop nano papirus-icon-theme curl lspci sensors -y
dnf install vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer -y
dnf remove -y dragon juk elisa-player kmail khelpcenter

# ==============================================================================
# 7. FLATPAK SETUP
# ==============================================================================
echo "Setting up Flatpak and Flathub..."
dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# ==============================================================================
# 8. NETWORK MANAGER PRIVACY & WIFI
# ==============================================================================
echo "Configuring NetworkManager privacy settings..."
mkdir -p /etc/NetworkManager/conf.d
[[ -e /etc/NetworkManager/conf.d/20-connectivity-fedora.conf ]] && cp -n /etc/NetworkManager/conf.d/20-connectivity-fedora.conf /etc/NetworkManager/conf.d/20-connectivity-fedora.conf.bak
printf "[connectivity]\nenabled=false\n" | tee /etc/Network/Manager/conf.d/20-connectivity-fedora.conf >/dev/null
systemctl restart NetworkManager

if ! rpm -q NetworkManager-wifi >/dev/null 2>&1; then
    echo "Installing NetworkManager-wifi..."
    dnf install -y NetworkManager-wifi
fi

# ==============================================================================
# 9. BROWSERS
# ==============================================================================
echo "Installing Browsers..."

# Brave
curl -fsS https://dl.brave.com/install.sh | sh
wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh
bash make_brave_great_again.sh
rm -f make_brave_great_again.sh

# Librewolf
curl -fsSL https://repo.librewolf.net/librewolf.repo | tee /etc/yum.repos.d/librewolf.repo
dnf install -y librewolf

# Chromium & Tor
dnf install -y chromium torbrowser-launcher

# ==============================================================================
# 10. DEV TOOLS
# ==============================================================================
echo "Installing Dev Tools..."

# Zed
curl -f https://zed.dev/install.sh | sh
sleep 10
# ==============================================================================
# 11. HOSTNAME SETUP
# ==============================================================================
echo ""
read -p "Enter the new hostname for your Fedora system: " new_hostname < /dev/tty

if [ -n "$new_hostname" ]; then
    hostnamectl set-hostname "$new_hostname"
    echo "127.0.0.1   $new_hostname localhost localhost.localdomain localhost4 localhost4.localdomain4" > /etc/hosts
    echo "::1         $new_hostname localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /etc/hosts
    echo "Hostname changed to $new_hostname."
else
    echo "No hostname entered. Skipping hostname change."
fi

# ==============================================================================
# 12. GAMING PACKAGES
# ==============================================================================
echo ""
read -p "Do you want to install Gaming Packages? (yes/no): " gaming_choice < /dev/tty
if [[ "$gaming_choice" =~ ^[Yy](es)?$ ]]; then
    echo "Downloading and running the Gaming Packages script..."
    wget -q --show-progress https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/Gaming.sh
    chmod +x Gaming.sh
    ./Gaming.sh
    rm -f Gaming.sh
else
    echo "Skipping Gaming Packages installation."
fi

# ==============================================================================
# 13. FLATPAKS
# ==============================================================================
echo "Installing Flatpak applications..."
wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Flatpak/flatpaks.sh
bash flatpaks.sh
rm -f flatpaks.sh

# ==============================================================================
# 14. Set Locale to 24 Hour
# ==============================================================================
set_locale_time() {
    echo "Attempting to set LC_TIME to C.UTF-8..."
    if sudo localectl set-locale LC_TIME=C.UTF-8; then
        echo "Successfully set LC_TIME."
    else
        echo "Error: Failed to set the locale time. Check if you have permission or if the command is correct." >&2
        return 1
    fi
}

set_locale_time

# ==============================================================================
# 15. SECURITY & CLEANUP
# ==============================================================================
echo "Securing system (Disabling OpenSSH)..."
systemctl stop sshd
systemctl disable sshd

echo "Finalizing installation and cleaning up..."
sleep 5
dnf autoremove -y
sleep 5

echo "Setup Complete. System will reboot in 10 seconds."
sleep 10
reboot
