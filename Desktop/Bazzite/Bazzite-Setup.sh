#!/bin/bash
echo "Setting Up Bazzite Machine"

# --- Repository locations ---------------------------------------------------
# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CODEBERG_RAW="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X27-Linux-Desktop-Toolbox/main"

_download() {
    # _download <url> <output-file>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        echo "ERROR: Neither curl nor wget is available." >&2
        return 1
    fi
}

fetch_repo_file() {
    # fetch_repo_file <relative/path> <output-file>
    # Downloads from Codeberg (primary); falls back to the GitHub mirror.
    local rel="$1" out="$2"

    echo "Fetching ${rel} from Codeberg..." >&2
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        return 0
    fi

    echo "Codeberg unreachable; falling back to GitHub mirror..." >&2
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        return 0
    fi

    echo "ERROR: Could not fetch ${rel} from Codeberg or GitHub." >&2
    return 1
}


echo "Disabling NetworkManager connectivity check..."
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"
mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
    cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak" || echo "WARN: Failed to back up NetworkManager config."
fi
printf '[connectivity]\nenabled=false\n' > "$NM_FILE_ETC"
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
fetch_repo_file "Browser/make_brave_great_again.sh" make_brave_great_again.sh
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
