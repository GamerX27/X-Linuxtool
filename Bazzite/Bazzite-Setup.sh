#!/bin/bash
echo "Setting Up Bazzite Machine"


echo "Configuring NetworkManager privacy settings..."
mkdir -p /etc/NetworkManager/conf.d
[[ -e /etc/NetworkManager/conf.d/20-connectivity-fedora.conf ]] && cp -n /etc/NetworkManager/conf.d/20-connectivity-fedora.conf /etc/NetworkManager/conf.d/20-connectivity-fedora.conf.bak
printf "[connectivity]\nenabled=false\n" | tee /etc/Network/Manager/conf.d/20-connectivity-fedora.conf >/dev/null
systemctl restart NetworkManager

echo "Replacing Firefox with Brave Browser..."
if flatpak list --app | grep -q "org.mozilla.firefox"; then
    echo "Firefox Flatpak found, removing..."
    flatpak uninstall -y org.mozilla.firefox
else
    echo "Firefox Flatpak not found, skipping removal."
fi
echo "Installing Brave Browser from Flathub..."
flatpak install -y flathub com.brave.Browser com.brave.Browser



echo "Running Make Brave Great Again Tweak..."
wget https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Browser/make_brave_great_again.sh
bash make_brave_great_again.sh
rm -f make_brave_great_again.sh



echo "Running a update..."
ujust update

echo "Setup complete! Reboot recommended."
read -p "Reboot now? (y/n): " reboot_choice
if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
    echo "Rebooting in..."
    for count in 10 9 8 7 6 5 4 3 2 1 0; do
        echo "$count"
        sleep 1
    done
    reboot
else
    echo "Skipping reboot. Don't forget to restart when ready!"
fi
