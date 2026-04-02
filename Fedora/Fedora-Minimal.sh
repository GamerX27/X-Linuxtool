echo "Fedora post Setup"
#Update and refresh repos
sudo dnf update --refresh && sudo dnf upgrade -y

#add Desktop DE
sudo dnf group install -y kde-desktop
sudo systemctl enable sddm
sudo systemctl set-default graphical.target

#RPM Fussion Nonfree and Free
sudo dnf install -y \
https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

#Install RPMFussion and core utils
sudo dnf update -y @core
#sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
sudo dnf install -y libavcodec-freeworld
#sudo dnf install -y gstreamer1-libav gstreamer1-plugins-bad-freeworld
sudo dnf group install -y multimedia

#Hardware acc Video playback
#!/bin/bash

# Function to swap AMD drivers
swap_amd() {
    echo "Swapping to AMD drivers..."
    sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
    sudo dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    sudo dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    sudo dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
}

# Function to install Intel drivers
swap_intel() {
    echo "Installing Intel drivers..."
    sudo dnf install -y intel-media-driver
}

# Function to skip driver swaps
skip_swap() {
    echo "Skipping driver swaps."
}

# Display menu
echo "Select an option:"
echo "1. AMD"
echo "2. Intel"
echo "3. None"
read -p "Enter your choice (1/2/3): " choice

# Execute based on choice
case $choice in
    1)
        swap_amd
        ;;
    2)
        swap_intel
        ;;
    3)
        skip_swap
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo "Done."



#other utils
sudo dnf install wget fastfetch fish htop nano papirus-icon-theme curl -y

#core apps for me
sudo dnf install vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer -y
sudo dnf remove -y dragon juk elisa-player kmail khelpcenter

#Flatpak
sudo dnf install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# NetworkManager connectivity check remove some telementry in my opinion

sudo mkdir -p /etc/NetworkManager/conf.d
[[ -e /etc/NetworkManager/conf.d/20-connectivity-fedora.conf ]] && sudo cp -n /etc/NetworkManager/conf.d/20-connectivity-fedora.conf /etc/NetworkManager/conf.d/20-connectivity-fedora.conf.bak
printf "[connectivity]\nenabled=false\n" | sudo tee /etc/NetworkManager/conf.d/20-connectivity-fedora.conf >/dev/null
sudo systemctl restart NetworkManager

if rpm -q NetworkManager-wifi >/dev/null 2>&1; then
    echo "NetworkManager-wifi is already installed. Skipping installation."
else
    echo "NetworkManager-wifi is not installed. Installing now..."
    sudo dnf install -y NetworkManager-wifi
    if [ $? -eq 0 ]; then
        echo "NetworkManager-wifi installed successfully."
    else
        echo "Failed to install NetworkManager-wifi."
        exit 1
    fi
fi

#Installing some browsers

#Brave
#it runs the script from brave them selves verify yourself is recommended https://dl.brave.com/install.sh

curl -fsS https://dl.brave.com/install.sh | sh

#make Brave less bloated disables AI, better privacy out of the box and makes Qwant based in europe the default search using policy.
wget https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/browser/Brave/make_brave_great_again.sh
sudo bash make_brave_great_again.sh
sudo rm make_brave_great_again.sh


#Install VSCodium
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


#Librewolf Firefox fork
# add the repo
curl -fsSL https://repo.librewolf.net/librewolf.repo | pkexec tee /etc/yum.repos.d/librewolf.repo

# install the package
sudo dnf install -y librewolf



#Plain old Chromium
sudo dnf install -y chromium

#Tor the best privacy tool
sudo dnf install -y torbrowser-launcher

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Use 'sudo'."
    exit 1
fi

# Prompt for the new hostname
read -p "Enter the new hostname for your Fedora system: " new_hostname

# Set the new hostname
hostnamectl set-hostname "$new_hostname"

# Update the hosts file
echo "127.0.0.1   $new_hostname localhost localhost.localdomain localhost4 localhost4.localdomain4" > /etc/hosts
echo "::1         $new_hostname localhost localhost.localdomain localhost6 localhost6.localdomain6" >> /etc/hosts

# Inform the user
echo "Hostname changed to $new_hostname. You may need to restart your system or services for changes to take full effect."

# Ask the user if they want to install Gaming Packages
read -p "Do you want to install Gaming Packages? (yes/no): " choice

if [[ "$choice" =~ ^[Yy](es)?$ ]]; then
    echo "Downloading and running the Gaming Packages script..."

    # Download the script
    wget -q --show-progress https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/Gaming/Gaming.sh

    # Make the script executable
    chmod +x Gaming.sh

    # Run the script
    ./Gaming.sh

    # Delete the script after use
    rm Gaming.sh
    echo "Gaming Packages script has been executed and deleted."
else
    echo "Skipping Gaming Packages installation."
fi

#Flatpaks
wget https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/tools/flatpaks.sh

bash flatpaks.sh

rm flatpaks.sh

#Fastfetch Config Credit to https://github.com/harilvfs.
wget https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/tools/fsfetch.sh
sudo bash fsfetch.sh
sudo rm fsfetch.sh



#Turn off OpenSSH Server
sudo systemctl stop sshd
sudo systemctl disable sshd 

sleep 15


#cleaning
sudo dnf autoremove -y


sleep 5

sudo reboot now