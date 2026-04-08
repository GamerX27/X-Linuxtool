#!/bin/bash
echo "Fedora post Setup"

# Update and refresh repos
sudo dnf update --refresh && sudo dnf upgrade -y

# Add Desktop DE
sudo dnf group install -y kde-desktop
sudo systemctl enable sddm
sudo systemctl set-default graphical.target

# RPM Fussion Nonfree and Free
sudo dnf install -y \
https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Install RPMFussion and core utils
sudo dnf update -y @core
sudo dnf install -y libavcodec-freeworld
sudo dnf group install -y multimedia

# Hardware acc Video playback
swap_amd() {
    echo "Swapping to AMD drivers..."
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
}

swap_intel() {
    echo "Installing Intel drivers..."
    sudo dnf install -y intel-media-driver
}

skip_swap() {
    echo "Skipping driver swaps."
}

# Display menu 
echo "Select an option:"
echo "1. AMD"
echo "2. Intel"
echo "3. None"
read -p "Enter your choice (1/2/3): " choice < /dev/tty

case $choice in
    1) swap_amd ;;
    2) swap_intel ;;
    3) skip_swap ;;
    *) echo "Invalid choice. Exiting." ; exit 1 ;;
esac

echo "Done."

# Other utils
sudo dnf install wget fastfetch fish htop nano papirus-icon-theme curl -y

# Core apps for me
sudo dnf install vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer -y
sudo dnf remove -y dragon juk elisa-player kmail khelpcenter

# Flatpak
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# NetworkManager connectivity check
sudo mkdir -p /etc/NetworkManager/conf.d
[[ -e /etc/NetworkManager/conf.d/20-connectivity-fedora.conf ]] && sudo cp -n /etc/NetworkManager/conf.d/20-connectivity-fedora.conf /etc/NetworkManager/conf.d/20-connectivity-fedora.conf.bak
printf "[connectivity]\nenabled=false\n" | sudo tee /etc/NetworkManager/conf.d/20-connectivity-fedora.conf >/dev/null
sudo systemctl restart NetworkManager

if rpm -q NetworkManager-wifi >/dev/null 2>&1; then
    echo "NetworkManager-wifi is already installed. Skipping installation."
else
    echo "NetworkManager-wifi is not installed. Installing now..."
    sudo dnf install -y NetworkManager-wifi
fi

# Installing Browsers
curl -fsS https://dl.brave.com/install.sh | sh
wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh
sudo bash make_brave_great_again.sh
sudo rm make_brave_great_again.sh

# VSCodium
sudo tee -a /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF
sudo dnf install -y codium

# Librewolf
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo
sudo dnf install -y librewolf

# Chromium & Tor
sudo dnf install -y chromium torbrowser-launcher

# Hostname Setup 
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use 'sudo'."
    exit 1
fi

read -p "Enter the new hostname for your Fedora system: " new_hostname < /dev/tty
hostnamectl set-hostname "$new_hostname"
echo "127.0.0.1   $new_hostname localhost localhost.localdomain localhost4 localhost4.localdomain4" > /etc/hosts
echo "::1         $new_hostname localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /etc/hosts
echo "Hostname changed to $new_hostname."

# Gaming Packages 
read -p "Do you want to install Gaming Packages? (yes/no): " choice < /dev/tty
if [[ "$choice" =~ ^[Yy](es)?$ ]]; then
    echo "Downloading and running the Gaming Packages script..."
    wget -q --show-progress https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming/Gaming.sh
    chmod +x Gaming.sh
    ./Gaming.sh
    rm Gaming.sh
else
    echo "Skipping Gaming Packages installation."
fi

# Flatpaks
wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Flatpak/flatpaks.sh
bash flatpaks.sh
rm flatpaks.sh

# Turn off OpenSSH Server
sudo systemctl stop sshd
sudo systemctl disable sshd 

sleep 15
sudo dnf autoremove -y
sleep 5
sudo reboot now
