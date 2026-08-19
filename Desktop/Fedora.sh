#!/bin/bash

# --- Repository locations ---------------------------------------------------
# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop"

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

echo "Choose a script to run:"
echo "1) Fedora Post-Setup"
echo "2) Fedora-Kionite-Setup"
echo "3) Bazzite Setup"
echo -n "Enter your choice (1, 2, or 3): "
read choice

case $choice in
    1)
        echo "Downloading and running Fedora-PostSetup.sh..."
        fetch_repo_file "Fedora/Fedora-PostSetup.sh" /tmp/Fedora-PostSetup.sh
        chmod +x /tmp/Fedora-PostSetup.sh
        bash /tmp/Fedora-PostSetup.sh
        rm -f /tmp/Fedora-PostSetup.sh
        ;;
    2)
        echo "Downloading and running Fedora-Kionite-Setup.sh..."
        fetch_repo_file "Fedora/Fedora-Kionite-Setup.sh" /tmp/Fedora-Kionite-Setup.sh
        chmod +x /tmp/Fedora-Kionite-Setup.sh
        sudo /tmp/Fedora-Kionite-Setup.sh
        sudo rm -f /tmp/Fedora-Kionite-Setup.sh
        ;;
    3)
        echo "Downloading and running Bazzite-Setup.sh..."
        fetch_repo_file "Bazzite/Bazzite-Setup.sh" /tmp/Bazzite-Setup.sh
        chmod +x /tmp/Bazzite-Setup.sh
        sudo /tmp/Bazzite-Setup.sh
        sudo rm -f /tmp/Bazzite-Setup.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
