#!/usr/bin/env bash

# Gaming Stack Installer
# Supports: Debian-based, Fedora-based, and Arch-based distributions.
# Features: Steam, Wine, Winetricks, MangoHud, GameMode, NVTop, Lutris, Heroic, Discord.

set -euo pipefail

# --- Colors for better UI ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Configuration ---
# Packages that should be installed on every supported distro via native package manager
CORE_PKGS=("wine" "winetricks" "mangohud" "gamemode" "nvtop")

# --- Helper Functions ---
log_info()    { echo -e "${BLUE}[*]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_error "Please run as root (e.g., sudo $0)"
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_flatpak_and_flathub() {
  if ! have_cmd flatpak; then
    log_info "Installing Flatpak..."
    if have_cmd dnf; then dnf install -y flatpak
    elif have_cmd apt; then apt update && apt install -y flatpak
    elif have_cmd pacman; then pacman -Syu --noconfirm flatpak
    fi
  fi

  if ! flatpak remote-list | grep -q '^flathub$'; then
    log_info "Adding Flathub repository..."
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

# --- Distro Specific Logic ---

install_debian_like() {
  log_info "Detected Debian/Ubuntu family."
  
  if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    log_info "Enabling i386 multiarch..."
    dpkg --add-architecture i386
    apt update
  fi

  log_info "Installing core gaming packages via apt..."
  apt update
  apt install -y "${CORE_PKGS[@]}" mesa-vulkan-drivers mesa-vulkan-drivers:i386 || true

  if apt-cache policy steam-installer 2>/dev/． | grep -q Candidate; then
    apt install -y steam-installer
  elif apt-cache policy steam 2>/dev/null | grep -q Candidate; then
    apt install -y steam
  else
    log_warn "Steam package not found. Ensure 'non-free' or 'multiverse' repos are enabled."
  fi

  log_info "Setting up Flatpaks..."
  ensure_flatpak_and_flathub
  flatpak install -y flathub net.lutris.Lutris com.heroicgameslauncher.hgl com.discordapp.Discord
}

install_fedora_like() {
  log_info "Detected Fedora/RHEL family."

  # Check if RPM Fusion is already enabled before trying to install it
  if dnf repolist | grep -qi "rpmfusion"; then
    log_success "RPM Fusion repositories are already enabled. Skipping."
  else
    log_info "Enabling RPM Fusion (free + nonfree) for Fedora..."
    dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
  fi

  log_info "Installing core gaming packages via dnf..."
  dnf install -y "${CORE_PKGS[@]}" steam lutris mesa-vulkan-drivers vulkan-loader \
    mesa-vulkan-drivers.i686 vulkan-loader.i686 || true

  log_info "Setting up Flatpaks..."
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.heroicgameslauncher.hgl com.discordapp.Discord
}

install_arch_like() {
  log_info "Detected Arch/Arch-based family."

  if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    log_info "Enabling multilib repo..."
    sed -i '/\[multilbc\]/,/Include/s/^#//' /etc/pacman.conf
  fi

  pacman -Syu --noconfirm
  log_info "Installing core gaming packages via pacman..."
  pacman -S --noconfirm "${CORE_PKGS[@]}" steam lutris vulkan-icd-loader lib32-vulkan-icd-loader

  if ! have_cmd yay; then
    log_warn "yay not found. Attempting to install from AUR..."
    pacman -S --needed --noconfirm git base-devel
    USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    sudo -u "$USER_NAME" bash -c 'cd "$HOME" && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm'
  fi
  
  USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USER_NAME" yay -S --noconfirm heroic-gameslauncher-bin

  log_info "Setting up Flatpaks..."
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.discordapp.Discord
}

# --- Main Entry Point ---

main() {
  require_root
  
  [ -r /etc/os-release ] || log_error "Cannot detect distro (no /etc/os-release)."
  . /etc/os-release
  
  ID_STR="${ID:-} ${ID_LIKE:-}"
  ID_STR=$(echo "$ID_STR" | tr '[:upper:]' '[:lower:]')

  case "$ID_STR" in
    *debian*|*ubuntu*|*linuxmint*|*pop*|*elementary*|*mx*|*zorin*|*kali*)
      install_debian_like
      ;;
    *fedora*|*rhel*|*centos*|*nobara*|*rocky*|*alma*)
      install_fedora_like
      ;;
    *arch*|*manjaro*|*endeavouros*|*garuda*|*arco*)
      install_arch_like
      ;;
    *)
      log_error "Unsupported distro: $PRETTY_NAME"
      ;;
  esac

  echo -e "\n${GREEN}[✓] Installation Complete!${NC}"
  echo -e "${YELLOW}Recommended Action:${NC} Reboot your system."
  echo -e "\n${BLUE}Gaming Tips:${NC}"
  echo " - Steam: Enable 'Steam Play/Proton' in Settings > Compatibility."
  echo " - MangoHud: Use launch option \`MANGOHUD=1 %command%\`."
  echo " - GameMode: Use launch option \`gamemoderun %command%\`."
  echo " - NVTop: Run \`nvtop\` in terminal to monitor GPU usage."
}

main "$@"
