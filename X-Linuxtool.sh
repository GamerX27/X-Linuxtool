#!/bin/bash

# --- Piped execution support ------------------------------------------------
# This script is designed to be run directly from the web, e.g.:
#   curl -fsSL https://raw.githubusercontent.com/GamerX27/X-Linuxtool/refs/heads/main/X-Linuxtool.sh | bash
#   curl -fsSL https://codeberg.org/X27/X-Linuxtool/raw/branch/main/X-Linuxtool.sh | bash
#
# When piped into bash, stdin is the script stream rather than the keyboard,
# which would break the interactive menu and any sub-scripts that prompt for
# input. Reconnect stdin to the controlling terminal so prompts work normally.
if [ ! -t 0 ] && [ -r /dev/tty ]; then
    exec < /dev/tty
fi

# --- Repository locations ---------------------------------------------------
# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CB_TOOLBOX="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main"
GH_TOOLBOX="https://raw.githubusercontent.com/GamerX27/X27-Linux-Desktop-Toolbox/main"

CB_HOMELAB="https://codeberg.org/X27/X27-Homelab-ToolBox/raw/branch/main"
GH_HOMELAB="https://raw.githubusercontent.com/GamerX27/X27-Homelab-ToolBox/main"

CB_YTDLP="https://codeberg.org/X27/YTDLP-Easy-Script/raw/branch/main"
GH_YTDLP="https://raw.githubusercontent.com/GamerX27/YTDLP-Easy-Script/main"

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

fetch_file() {
    # fetch_file <codeberg-url> <github-url> <output-file>
    # Downloads from Codeberg (primary); falls back to the GitHub mirror.
    local cb="$1" gh="$2" out="$3"

    echo "Fetching from Codeberg..." >&2
    if _download "$cb" "$out"; then
        return 0
    fi

    echo "Codeberg unreachable; falling back to GitHub mirror..." >&2
    if _download "$gh" "$out"; then
        return 0
    fi

    echo "ERROR: Could not download from Codeberg or GitHub." >&2
    return 1
}

check_and_install_dependencies() {
    local dependencies=("wget" "git" "curl")
    local pkg_manager=""

    if command -v apt &> /dev/null; then
        pkg_manager="apt"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    fi

    if [ -z "$pkg_manager" ]; then
        echo "Unsupported package manager. Please ensure wget, git, and curl are installed manually."
        return 0
    fi

    echo "Checking dependencies: ${dependencies[*]}..."
    local missing_deps=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "Missing dependencies: ${missing_deps[*]}. Attempting to install via $pkg_manager..."
        sudo $pkg_manager update -y &> /dev/null
        sudo $pkg_manager install -y "${missing_deps[@]}"
        if [ $? -eq 0 ]; then
            echo "Dependencies installed successfully."
        else
            echo "Failed to install dependencies. Please install them manually."
            exit 1
        fi
    else
        echo "All dependencies are already installed."
    fi
}

# Run dependency check before showing choices
check_and_install_dependencies

echo "Choose a script to download and run:"
echo "1) Fedora Desktop"
echo "2) HomeLab"
echo "3) Brave Debloat"
echo "4) YT-DLP-Easy Installer"
echo "5) Kron4ek Wine Installer"
echo "6) Proton CachyOS Installer"
echo "7) Gigabyte Sleep Fix"
echo "8) Custom Fastfetch Config"
echo "9) Virtualization Setup"
read -p "Enter your choice (1, 2, 3, 4, 5, 6, 7, 8, or 9): " choice

case $choice in
    1)
        echo "Downloading and running Fedora Desktop..."
        fetch_file "${CB_TOOLBOX}/Fedora.sh" "${GH_TOOLBOX}/Fedora.sh" /tmp/Fedora.sh || exit 1
        sudo bash /tmp/Fedora.sh
        sudo rm -f /tmp/Fedora.sh
        ;;
    2)
        echo "Downloading and running for HomeLab..."
        fetch_file "${CB_HOMELAB}/X27-Homelab.sh" "${GH_HOMELAB}/X27-Homelab.sh" /tmp/X27-Homelab.sh || exit 1
        sudo bash /tmp/X27-Homelab.sh
        sudo rm -f /tmp/X27-Homelab.sh
        ;;
    3)
        echo "Downloading and running Brave Debloat..."
        fetch_file "${CB_TOOLBOX}/Browser/make_brave_great_again.sh" "${GH_TOOLBOX}/Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh || exit 1
        sudo bash /tmp/make_brave_great_again.sh
        sudo rm -f /tmp/make_brave_great_again.sh
        ;;
    4)
        echo "Downloading and running YT-DLP-Easy Installer..."
        fetch_file "${CB_YTDLP}/Install-YT-DLP-Easy.sh" "${GH_YTDLP}/Install-YT-DLP-Easy.sh" /tmp/Install-YT-DLP-Easy.sh || exit 1
        bash /tmp/Install-YT-DLP-Easy.sh
        sudo rm -f /tmp/Install-YT-DLP-Easy.sh
        ;;
    5)
        echo "Downloading and running Kron4ek Wine Installer..."
        fetch_file "${CB_TOOLBOX}/Gaming/Kron4ek-wine-installer.sh" "${GH_TOOLBOX}/Gaming/Kron4ek-wine-installer.sh" /tmp/Kron4ek-wine-installer.sh || exit 1
        bash /tmp/Kron4ek-wine-installer.sh
        rm -f /tmp/Kron4ek-wine-installer.sh
        ;;
    6)
        echo "Downloading and running Proton CachyOS Installer..."
        fetch_file "${CB_TOOLBOX}/Gaming/proton-cachyos-installer.sh" "${GH_TOOLBOX}/Gaming/proton-cachyos-installer.sh" /tmp/proton-cachyos-installer.sh || exit 1
        bash /tmp/proton-cachyos-installer.sh
        rm -f /tmp/proton-cachyos-installer.sh
        ;;
    7)
        echo "Downloading and running Gigabyte Sleep Fix..."
        fetch_file "${CB_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" "${GH_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" /tmp/GigabyteSleep-Fix.sh || exit 1
        sudo bash /tmp/GigabyteSleep-Fix.sh
        sudo rm -f /tmp/GigabyteSleep-Fix.sh
        ;;
    8)
        echo "Downloading and running Fastfetch Config Update..."
        fetch_file "${CB_TOOLBOX}/Tools/fsfetch.sh" "${GH_TOOLBOX}/Tools/fsfetch.sh" /tmp/fsfetch.sh || exit 1
        bash /tmp/fsfetch.sh
        rm -f /tmp/fsfetch.sh
        ;;
    9)
        echo "Downloading and running Virtualization Setup..."
        fetch_file "${CB_TOOLBOX}/Tools/Virtualization_Setup.sh" "${GH_TOOLBOX}/Tools/Virtualization_Setup.sh" /tmp/Virtualization_Setup.sh || exit 1
        sudo bash /tmp/Virtualization_Setup.sh
        sudo rm -f /tmp/Virtualization_Setup.sh
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac
