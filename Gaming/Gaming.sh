#!/usr/bin/env bash
set -euo pipefail

# Gaming stack installer (Steam via package manager; Lutris/Heroic per your rules)
# - Debian-based: Steam (apt), Wine/Winetricks/MangoHud/Vulkan/nvtop (apt),
#                 Lutris (Flatpak), Heroic (Flatpak)
# - Fedora-based: Steam (dnf), Wine/Winetricks/MangoHud/GameMode/Vulkan/nvtop (dnf),
#                 Lutris (dnf), Heroic (Flatpak)
# - Arch-based:   Steam (pacman), Wine/Winetricks/MangoHud/GameMode/Vulkan/nvtop (pacman),
#                 Lutris (pacman), Heroic (AUR via yay)
#
# Run with sudo: sudo ./gaming-setup.sh

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "Please run as root (e.g., sudo $0)"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_flatpak_and_flathub() {
  if ! have_cmd flatpak; then
    echo "[*] Installing Flatpak…"
    if have_cmd dnf; then
      dnf install -y flatpak
    elif have_cmd apt; then
      apt update
      apt install -y flatpak
    elif have_cmd pacman; then
      pacman -Syu --noconfirm flatpak
    else
      echo "[-] Could not install Flatpak on this system."
      return 1
    fi
  fi
  if ! flatpak remote-list | awk '{print $1}' | grep -q '^flathub$'; then
    echo "[*] Adding Flathub…"
    flatlam remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

install_utilities() {
  if have_cmd dnf; then
    echo "[*] Installing MangoHud, GameMode + nvtop (Fedora)…"
    dnf install -y mangohud gamemode nvtop
  elif have_cmd apt; then
    echo "[*] Installing MangoHud + nvtop (Debian/Ubuntu - skipping GameMode)…"
    apt update
    apt install -y mangohud nvtop
    # Optional 32-bit MangoHud if multiarch enabled
    dpkg --print-foreign-architectures | grep -q '^i386$' && apt install -y mangohud:i386 || true
  elif have_cmd pacman; then
    echo "[*] Installing MangoHud, GameMode + nvtop (Arch)…"
    pacman -S --noconfirm mangohud gamemode nvtop
  fi
}

########## Extra installers (Wine TkG + Proton CachyOS) ##########
# These scripts live in the repo's Gaming/ folder. Codeberg is primary, GitHub is fallback.
CODEBERG_RAW_BASE="https://codeberg.org/X27/X27-Linux-Desktop-Toolbox/raw/branch/main/Gaming"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/GamerX27/X27-Linux-Desktop-Toolbox/main/Gaming"

ensure_curl() {
  have_cmd curl && return 0
  echo "[*] Installing curl (needed for extra installers)…"
  if have_cmd dnf; then
    dnf install -y curl
  elif have_cmd apt; then
    apt update
    apt install -y curl
  elif have_cmd pacman; then
    pacman -S --noconfirm curl
  else
    echo "[-] Could not install curl on this system."
    return 1
  fi
}

fetch_script() {
  # fetch_script <script-name> <dest>; tries Codeberg first, then GitHub.
  local name="$1" dest="$2"
  echo "[*] Fetching ${name} from Codeberg…"
  if curl -fsSL "${CODEBERG_RAW_BASE}/${name}" -o "$dest"; then
    return 0
  fi
  echo "[!] Codeberg fetch failed; trying GitHub…"
  if curl -fsSL "${GITHUB_RAW_BASE}/${name}" -o "$dest"; then
    return 0
  fi
  echo "[-] Failed to fetch ${name} from both Codeberg and GitHub."
  return 1
}

run_extra_installers() {
  ensure_curl || { echo "[-] Skipping extra installers (curl unavailable)."; return 0; }

  local USERNAME tmpdir
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN
  # Allow the target (non-root) user to read the downloaded scripts.
  chmod 755 "$tmpdir"

  local scripts=("Kron4ek-wine-installer.sh" "proton-cachyos-installer.sh")
  local s
  for s in "${scripts[@]}"; do
    if fetch_script "$s" "$tmpdir/$s"; then
      chmod 755 "$tmpdir/$s"
      echo "[*] Running ${s} as ${USERNAME}…"
      # These installers must NOT run as root, so drop privileges.
      sudo -u "$USERNAME" -H bash "$tmpdir/$s" || echo "[-] ${s} exited with errors."
    fi
  done
}

########## Debian / Ubuntu family ##########
install_debian_like() {
  echo "[*] Debian/Ubuntu family detected."

  # Enable i386 for Steam/Wine 32-bit libs
  if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    echo "[*] Enabling i386 multiarch…"
    dpkg --add-architecture i386
  fi
  apt update

  echo "[*] Installing Steam (apt)…"
  if apt-cache policy steam-installer 2>/dev/null | grep -q Candidate; then
    apt install -y steam-installer
  elif apt-cache policy steam 2>/dev/null | grep -q Candidate; then
    apt install -y steam
  else
    echo "[-] Steam package not found in your current repos."
    echo "    On Debian/Ubuntu you may need to enable non-free/multiverse."
    echo "    Aborting Steam install (per requirement: no Flatpak fallback)."
  fi

  echo "[*] Installing Wine + Winetricks…"
  apt install -y wine winetricks

  echo "[*] Installing Vulkan drivers (64-bit + 32-bit)…"
  apt install -y mesa-vulkan-drivers mesa-vulkan-drivers:i386 || true

  install_utilities

  echo "[*] Installing Lutris (Flatpak) + Heroic (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub net.lutris.Lutris
  flatpak install -y flathub com.heroicgameslauncher.hgl

  echo "[*] Installing Discord (Flatpak)…"
  flatpak install -y flathub com.discordapp.Discord
}

########## Fedora / RHEL family ##########
enable_rpmfusion_fedora() {
  if dnf repolist | grep -Eq 'rpmfusion-free|rpmfusion-nonfree'; then
    echo "[*] RPM Fusion repositories already enabled. Skipping."
    return 0
  fi

  echo "[*] Enabling RPM Fusion (free + nonfree) for Fedora…"
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
}

install_fedora_like() {
  echo "[*] Fedora/RHEL family detected."

  # Steam lives in RPM Fusion on Fedora proper
  if [ "${ID:-}" = "fedora" ]; then
    enable_rpmfusion_fedora
  else
    echo "[i] On ${PRETTY_NAME:-this system}, Steam may require enabling appropriate repos (e.g., RPM Fusion for EL)."
    echo "    Proceeding to install; if it fails, enable the needed repos and re-run."
  fi

  echo "[*] Installing Steam (dnf)…"
  dnf install -y steam || echo "[-] Steam install failed. Enable RPM Fusion/EL repos and re-run."

  echo "[*] Installing Wine + Winetricks…"
  dnf install -y wine winetricks

  echo "[*] Installing Vulkan drivers (64-bit + 32-bit)…"
  dnf install -y mesa-vulkan-drivers vulkan-loader || true
  dnf install -y mesa-vulkan-drivers.i686 vulkan-loader.i686 || true

  install_utilities

  echo "[*] Installing Lutris (dnf)…"
  dnf install -y lutris

  echo "[*] Installing Heroic + Discord (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.heroicgameslauncher.hgl
  flatpak install -y flathub com.discordapp.Discord
}

########## Arch / Manjaro / EndeavourOS ##########
enable_arch_multilib() {
  if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    if grep -Eq '^\s*#\s*\[multilib\]' /etc/pacman.conf; then
      echo "[*] Enabling multilib repo in /etc/pacman.conf…"
      sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
    fi
  fi
}

ensure_yay() {
  if have_cmd yay; then return 0; fi
  echo "[*] yay not found—installing from AUR…"
  pacman -Syu --needed --noconfirm git base-devel
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USERNAME" bash -c '
    set -e
    cd "$HOME"
    [ -d yay ] || git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
  '
}

install_arch_like() {
  echo "[*] Arch/Arch-based detected."
  enable_arch_multilib
  pacman -Syu --noconfirm

  echo "[*] Installing Steam (pacman)…"
  pacman -S --noconfirm steam

  echo "[*] Installing Wine + Winetricks…"
  pacman -S --noconfirm wine winetricks

  echo "[*] Installing Vulkan loader (64-bit + 32-bit)…"
  pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader

  echo "[*] Installing Lutris (pacman)…"
  pacman -S --noconfirm lutris

  install_utilities

  echo "[*] Installing Heroic (AUR via yay)…"
  ensure_yay
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USERNAME" yay -S --noconfirm heroic-games-launcher-bin

  echo "[*] Installing Discord (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.discordapp.Discord
}

########## Entry point ##########
main() {
  require_root
  [ -r /etc/os-release ] || { echo "Cannot detect distro (no /etc/os-release)."; exit 1; }
  . /etc/os-release
  id_like=$(echo "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')
  id=$(echo "${ID:-}" | tr '[:upper:]' '[:lower:]')

  if echo "$id $id_like" | grep -Eq 'debian|ubuntu|linuxmint|pop|elementary|mx|zorin|kali|raspbian'; then
    install_debian_like
  elif echo "$id $id_like" | grep -Eq 'fedora|rhel|centos|nobara|rocky|alma'; then
    install_fedora_like
  elif echo "$id $id_like" | grep -Eq 'arch|manjaro|endeavouros|garuda|arco|rebornos'; then
    install_arch_like
  else
    echo "Unsupported or unrecognized distro: ${PRETTY_NAME:-unknown}"
    echo "Targets: Debian-based, Fedora-based, and Arch-based."
    exit 2
  fi

  echo
  echo "[*] Running extra installers (Wine Staging TkG + Proton CachyOS)…"
  run_extra_installers

  echo
  echo "[✓] Done. Reboot recommended."
  echo "Tips:"
  echo " - In Steam: enable Steam Play/Proton for all titles (Settings → Compatibility)."
  echo " - MangoHud: use launch option 'MANGOHUD=1 %command%'."
  echo " - GameMode: use launch option 'gamemoderun %command%' (if available)."
}

main "$@"
