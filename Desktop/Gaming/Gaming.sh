#!/usr/bin/env bash
set -euo pipefail

ui_info()    { printf '  › %s\n' "$1"; }
ui_ok()      { printf '  ✔ %s\n' "$1"; }
ui_warn()    { printf '  ▲ %s\n' "$1"; }
ui_err()     { printf '  ✖ %s\n' "$1" >&2; }
ui_step()    { printf '\n  ➤ %s\n' "$1"; }
ui_rule()    { printf '──────────────────────────────────────────────────────\n'; }

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
    else
      ui_err "Could not install Flatpak on this system."
      return 1
    fi
  fi
  if ! flatpak remote-list | awk '{print $1}' | grep -q '^flathub$'; then
    ui_info "Adding Flathub…"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

install_flatpak_apps() {
  ensure_flatpak_and_flathub || return 1
  local app
  for app in "$@"; do
    ui_info "Installing ${app} (Flatpak)…"
    flatpak install -y flathub "$app"
  done
}

install_utilities() {
  if have_cmd dnf; then
    ui_info "Installing MangoHud, GameMode + nvtop (Fedora)…"
    dnf install -y mangohud gamemode nvtop
  elif have_cmd apt; then
    ui_info "Installing MangoHud + nvtop (Debian/Ubuntu - skipping GameMode)…"
    apt update
    apt install -y mangohud nvtop
    dpkg --print-foreign-architectures | grep -q '^i386$' && apt install -y mangohud:i386 || true
  fi
}

# These scripts live in the repo's Gaming/ folder. Codeberg is primary, GitHub is fallback.
CODEBERG_RAW_BASE="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop/Gaming"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop/Gaming"

# When invoked by a local X-Linuxtool.sh clone, X27_LOCAL_ROOT points at
# the clone root; prefer the scripts already on disk over re-downloading.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Desktop/Gaming}"

ensure_curl() {
  have_cmd curl && return 0
  ui_info "Installing curl (needed for extra installers)…"
  if have_cmd dnf; then
    dnf install -y curl
  elif have_cmd apt; then
    apt update
    apt install -y curl
  else
    ui_err "Could not install curl on this system."
    return 1
  fi
}

fetch_script() {
  local name="$1" dest="$2"

  if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE/$name" ]; then
    ui_info "Using local copy: ${name}"
    cp "$LOCAL_BASE/$name" "$dest"
    return 0
  fi

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

install_proton_update_command() {
  local USERNAME USER_HOME bindir
  USERNAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
  USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
  bindir="$USER_HOME/.local/bin"

  ui_info "Installing 'proton-cachyos-update' command to ${bindir}…"
  sudo -u "$USERNAME" mkdir -p "$bindir"

  cat > "$bindir/proton-cachyos-update" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LOCAL_BASE="${LOCAL_BASE}"
CODEBERG_RAW_BASE="${CODEBERG_RAW_BASE}"
GITHUB_RAW_BASE="${GITHUB_RAW_BASE}"
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
if [ -n "\$LOCAL_BASE" ] && [ -f "\$LOCAL_BASE/proton-cachyos-installer.sh" ]; then
  cp "\$LOCAL_BASE/proton-cachyos-installer.sh" "\$tmp/proton-cachyos-installer.sh"
elif ! curl -fsSL "\$CODEBERG_RAW_BASE/proton-cachyos-installer.sh" -o "\$tmp/proton-cachyos-installer.sh"; then
  curl -fsSL "\$GITHUB_RAW_BASE/proton-cachyos-installer.sh" -o "\$tmp/proton-cachyos-installer.sh"
fi
bash "\$tmp/proton-cachyos-installer.sh"
EOF
  chown "$USERNAME:$USERNAME" "$bindir/proton-cachyos-update"
  chmod 755 "$bindir/proton-cachyos-update"
  ui_ok "Run 'proton-cachyos-update' anytime to check for and install Proton-CachyOS updates."
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
      [[ "$s" == "proton-cachyos-installer.sh" ]] && install_proton_update_command
    fi
  done
}

install_debian_like() {
  ui_step "Debian/Ubuntu family detected."

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

  install_flatpak_apps net.lutris.Lutris com.heroicgameslauncher.hgl com.discordapp.Discord
}

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

  install_flatpak_apps com.heroicgameslauncher.hgl com.discordapp.Discord
}

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
  else
    ui_err "Unsupported or unrecognized distro: ${PRETTY_NAME:-unknown}"
    echo "Targets: Debian-based and Fedora-based."
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
