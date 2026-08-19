#!/bin/bash

# Script to run X27-Scripts for servers

# --- Repository location -----------------------------------------------------
# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Homelab"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Homelab"

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
echo "1) Install Docker"
echo "2) Auto Update setup"
echo "3) Docker Compose Updater"
echo -n "Enter your choice (1, 2 or 3): "
read choice

case $choice in
    1)
        echo "Running Install Docker"
        fetch_repo_file "Scripts/Docker/Docker-Install.sh" Docker-Install.sh || exit 1
        sudo bash Docker-Install.sh
        sudo rm Docker-Install.sh
        ;;
    2)
        echo "Running Server-Updater.sh..."
        fetch_repo_file "Scripts/Server-Updater.sh" Server-Updater.sh || exit 1
        sudo bash Server-Updater.sh
        sudo rm Server-Updater.sh
        ;;
    3)
        echo "Running Docker-Updater.sh..."
        fetch_repo_file "Scripts/Docker/Docker-Updater.sh" Docker-Updater.sh || exit 1
        sudo bash Docker-Updater.sh
        sudo rm Docker-Updater.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
