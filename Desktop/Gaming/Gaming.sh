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

# --- Theme / colors ---------------------------------------------------------
# Same Nord palette as X-Linuxtool.sh, anchored on Polar Night #2e3440
# (base/border) and Aurora Red #bf616a (accent/selection).
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
            # Nearest 256-color approximations of the Nord palette.
            C_GREY=$'\033[38;5;244m'    # nord3  4c566a
            C_FG=$'\033[38;5;253m'      # nord4  d8dee9
            C_BLUE=$'\033[38;5;110m'    # nord9  81a1c1
            C_RED=$'\033[38;5;167m'     # nord11 bf616a
            C_YELLOW=$'\033[38;5;222m'  # nord13 ebcb8b
            C_GREEN=$'\033[38;5;150m'   # nord14 a3be8c
            C_MAGENTA=$'\033[38;5;139m' # nord15 b48ead
            C_ACCENT=$'\033[38;5;167m'  # nord11 bf616a
            ;;
        *)
            C_GREY=$'\033[38;2;76;86;106m'     # nord3  4c566a
            C_FG=$'\033[38;2;216;222;233m'     # nord4  d8dee9
            C_BLUE=$'\033[38;2;129;161;193m'   # nord9  81a1c1
            C_RED=$'\033[38;2;191;97;106m'     # nord11 bf616a
            C_YELLOW=$'\033[38;2;235;203;139m' # nord13 ebcb8b
            C_GREEN=$'\033[38;2;163;190;140m'  # nord14 a3be8c
            C_MAGENTA=$'\033[38;2;180;142;173m' # nord15 b48ead
            C_ACCENT=$'\033[38;2;191;97;106m'  # nord11 bf616a
            ;;
    esac
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_GREY="" C_FG="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_ACCENT=""
fi

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }
ui_rule()    { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM$C_GREY" "$C_RESET"; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    ui_err "Please run as root (e.g., sudo $0)"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_flatpak_and_flathub() {
  if ! have_cmd flatpak; then
    ui_info "Installing Flatpak…"
    if have_cmd dnf; then
      dnf install -y flatpak
    elif have_cmd apt; then
      apt update
      apt install -y flatpak
    elif have_cmd pacman; then
      pacman -Syu --noconfirm flatpak
    else
      ui_err "Could not install Flatpak on this system."
      return 1
    fi
  fi
  if ! flatpak remote-list | awk '{print $1}' | grep -q '^flathub$'; then
    ui_info "Adding Flathub…"
    flatlam remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

install_utilities() {
  if have_cmd dnf; then
    ui_info "Installing MangoHud, GameMode + nvtop (Fedora)…"
    dnf install -y mangohud gamemode nvtop
  elif have_cmd apt; then
    ui_info "Installing MangoHud + nvtop (Debian/Ubuntu - skipping GameMode)…"
    apt update
    apt install -y mangohud nvtop
    # Optional 32-bit MangoHud if multiarch enabled
    dpkg --print-foreign-architectures | grep -q '^i386$' && apt install -y mangohud:i386 || true
  elif have_cmd pacman; then
    ui_info "Installing MangoHud, GameMode + nvtop (Arch)…"
    pacman -S --noconfirm mangohud gamemode nvtop
  fi
}

########## Extra installers (Wine TkG + Proton CachyOS) ##########
# These scripts live in the repo's Gaming/ folder. Codeberg is primary, GitHub is fallback.
CODEBERG_RAW_BASE="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop/Gaming"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop/Gaming"

ensure_curl() {
  have_cmd curl && return 0
  ui_info "Installing curl (needed for extra installers)…"
  if have_cmd dnf; then
    dnf install -y curl
  elif have_cmd apt; then
    apt update
    apt install -y curl
  elif have_cmd pacman; then
    pacman -S --noconfirm curl
  else
    ui_err "Could not install curl on this system."
    return 1
  fi
}

fetch_script() {
  # fetch_script <script-name> <dest>; tries Codeberg first, then GitHub.
  local name="$1" dest="$2"
  ui_info "Fetching ${name} from Codeberg…"
  if curl -fsSL "${CODEBERG_RAW_BASE}/${name}" -o "$dest"; then
    return 0
  fi
  ui_warn "Codeberg fetch failed; trying GitHub…"
  if curl -fsSL "${GITHUB_RAW_BASE}/${name}" -o "$dest"; then
    return 0
  fi
  ui_err "Failed to fetch ${name} from both Codeberg and GitHub."
  return 1
}

run_extra_installers() {
  ensure_curl || { ui_warn "Skipping extra installers (curl unavailable)."; return 0; }

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
      ui_info "Running ${s} as ${USERNAME}…"
      # These installers must NOT run as root, so drop privileges.
      sudo -u "$USERNAME" -H bash "$tmpdir/$s" || ui_err "${s} exited with errors."
    fi
  done
}

########## Debian / Ubuntu family ##########
install_debian_like() {
  ui_step "Debian/Ubuntu family detected."

  # Enable i386 for Steam/Wine 32-bit libs
  if ! dpkg --print-foreign-architectures | grep -q '^i386$'; then
    ui_info "Enabling i386 multiarch…"
    dpkg --add-architecture i386
  fi
  apt update

  ui_info "Installing Steam (apt)…"
  if apt-cache policy steam-installer 2>/dev/null | grep -q Candidate; then
    apt install -y steam-installer
  elif apt-cache policy steam 2>/dev/null | grep -q Candidate; then
    apt install -y steam
  else
    ui_err "Steam package not found in your current repos."
    echo "    On Debian/Ubuntu you may need to enable non-free/multiverse."
    echo "    Aborting Steam install (per requirement: no Flatpak fallback)."
  fi

  ui_info "Installing Wine + Winetricks…"
  apt install -y wine winetricks

  ui_info "Installing Vulkan drivers (64-bit + 32-bit)…"
  apt install -y mesa-vulkan-drivers mesa-vulkan-drivers:i386 || true

  install_utilities

  ui_info "Installing Lutris (Flatpak) + Heroic (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub net.lutris.Lutris
  flatpak install -y flathub com.heroicgameslauncher.hgl

  ui_info "Installing Discord (Flatpak)…"
  flatpak install -y flathub com.discordapp.Discord
}

########## Fedora / RHEL family ##########
enable_rpmfusion_fedora() {
  if dnf repolist | grep -Eq 'rpmfusion-free|rpmfusion-nonfree'; then
    ui_warn "RPM Fusion repositories already enabled. Skipping."
    return 0
  fi

  ui_info "Enabling RPM Fusion (free + nonfree) for Fedora…"
  dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
}

install_fedora_like() {
  ui_step "Fedora/RHEL family detected."

  # Steam lives in RPM Fusion on Fedora proper
  if [ "${ID:-}" = "fedora" ]; then
    enable_rpmfusion_fedora
  else
    ui_info "On ${PRETTY_NAME:-this system}, Steam may require enabling appropriate repos (e.g., RPM Fusion for EL)."
    echo "    Proceeding to install; if it fails, enable the needed repos and re-run."
  fi

  ui_info "Installing Steam (dnf)…"
  dnf install -y steam || ui_err "Steam install failed. Enable RPM Fusion/EL repos and re-run."

  ui_info "Installing Wine + Winetricks…"
  dnf install -y wine winetricks

  ui_info "Installing Vulkan drivers (64-bit + 32-bit)…"
  dnf install -y mesa-vulkan-drivers vulkan-loader || true
  dnf install -y mesa-vulkan-drivers.i686 vulkan-loader.i686 || true

  install_utilities

  ui_info "Installing Lutris (dnf)…"
  dnf install -y lutris

  ui_info "Installing Heroic + Discord (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.heroicgameslauncher.hgl
  flatpak install -y flathub com.discordapp.Discord
}

########## Arch / Manjaro / EndeavourOS ##########
enable_arch_multilib() {
  if ! grep -Eq '^\[multilib\]' /etc/pacman.conf; then
    if grep -Eq '^\s*#\s*\[multilib\]' /etc/pacman.conf; then
      ui_info "Enabling multilib repo in /etc/pacman.conf…"
      sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
    fi
  fi
}

ensure_yay() {
  if have_cmd yay; then return 0; fi
  ui_info "yay not found—installing from AUR…"
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
  ui_step "Arch/Arch-based detected."
  enable_arch_multilib
  pacman -Syu --noconfirm

  ui_info "Installing Steam (pacman)…"
  pacman -S --noconfirm steam

  ui_info "Installing Wine + Winetricks…"
  pacman -S --noconfirm wine winetricks

  ui_info "Installing Vulkan loader (64-bit + 32-bit)…"
  pacman -S --noconfirm vulkan-icd-loader lib32-vulkan-icd-loader

  ui_info "Installing Lutris (pacman)…"
  pacman -S --noconfirm lutris

  install_utilities

  ui_info "Installing Heroic (AUR via yay)…"
  ensure_yay
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  sudo -u "$USERNAME" yay -S --noconfirm heroic-games-launcher-bin

  ui_info "Installing Discord (Flatpak)…"
  ensure_flatpak_and_flathub
  flatpak install -y flathub com.discordapp.Discord
}

########## Entry point ##########
main() {
  require_root
  [ -r /etc/os-release ] || { ui_err "Cannot detect distro (no /etc/os-release)."; exit 1; }
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
    ui_err "Unsupported or unrecognized distro: ${PRETTY_NAME:-unknown}"
    echo "Targets: Debian-based, Fedora-based, and Arch-based."
    exit 2
  fi

  ui_step "Running extra installers (Wine Staging TkG + Proton CachyOS)…"
  run_extra_installers

  echo
  ui_ok "Done. Reboot recommended."
  ui_info "Tips:"
  echo " - In Steam: enable Steam Play/Proton for all titles (Settings → Compatibility)."
  echo " - MangoHud: use launch option 'MANGOHUD=1 %command%'."
  echo " - GameMode: use launch option 'gamemoderun %command%' (if available)."
}

main "$@"
