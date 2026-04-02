#!/usr/bin/env bash
# Fedora setup helper
# Origin: XDora-inspired script, hardened & cleaned

# Require sudo (do not auto-escalate)
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "This script must be run with sudo." >&2
  exit 1
fi

if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
  echo "Run this script via sudo from a non-root user to configure user-scoped settings." >&2
  exit 1
fi

echo "Running with elevated privileges for ${SUDO_USER}!"
must "System upgrade and repo refresh" $SUDO dnf -y upgrade --refresh


# -------------------------
# Safety & helpers
# -------------------------
set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
LOG_TS() { date +"%Y-%m-%d %H:%M:%S"; }
info()  { echo "[INFO  $(LOG_TS)] $*"; }
warn()  { echo "[WARN  $(LOG_TS)] $*" >&2; }
error() { echo "[ERROR $(LOG_TS)] $*" >&2; }
die()   { error "$*"; exit 1; }

# If root, no sudo. If not root, need sudo.
SUDO=""
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "This script needs root or 'sudo' installed."
  fi
fi

TARGET_USER="${SUDO_USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || die "Unable to determine home directory for ${TARGET_USER}."
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null)"
[[ -n "$TARGET_GROUP" ]] || die "Unable to determine primary group for ${TARGET_USER}."

command_exists() { command -v "$1" >/dev/null 2>&1; }

# try: run and continue on failure
try() {
  local desc="$1"; shift
  info "$desc"
  if "$@"; then
    info "OK: $desc"
    return 0
  else
    warn "FAILED (continuing): $desc"
    return 1
  fi
}

# must: run and abort on failure
must() {
  local desc="$1"; shift
  info "$desc"
  "$@" && { info "OK: $desc"; return 0; }
  die "FAILED: $desc"
}

# -------------------------
# Pre-flight checks
# -------------------------
info "Starting ${SCRIPT_NAME}"

# Basic tools
for bin in dnf rpm curl wget sed awk; do
  command_exists "$bin" || die "Required tool missing: $bin"
done

# Wallpaper credit: https://www.pixiv.net/en/artworks/82028519 by https://www.pixiv.net/en/users/15919563 (aka Tsuchiya)
try "Download Tsuchiya wallpaper for ${TARGET_USER}" \
  runuser -u "${TARGET_USER}" -- wget --directory-prefix="${TARGET_HOME}" "https://rare-gallery.com/uploads/posts/341250-Sunset-Starry-Night-Sky-Moon-Stars-Anime-Scenery.jpg"

# Fedora release number
FEDORA_VER="$(rpm -E %fedora 2>/dev/null || echo "")"
[[ -n "$FEDORA_VER" ]] || die "Unable to resolve %fedora macro."

# -------------------------
# System update & RPM Fusion
# -------------------------
must "Refreshing DNF metadata" $SUDO dnf -y makecache --refresh
must "Updating system packages" $SUDO dnf -y update

must "adding RPM Fussion nonfree and free to system" $SUDO dnf install -y \
https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

$SUDO dnf update --refresh


try "Update @core group" $SUDO dnf -y update @core


# -------------------------
# Brave Browser (install script is not critical)
# -------------------------
if ! command_exists brave-browser; then
  if curl -fsS https://dl.brave.com/install.sh >/dev/null 2>&1; then
    try "Installing Brave via upstream script" bash -c 'curl -fsS https://dl.brave.com/install.sh | sh'
  else
    warn "Brave install script unreachable. Skipping Brave."
  fi
else
  info "Brave already installed. Skipping."
fi

# -------------------------
# Multimedia stack & codecs
# -------------------------
try "Swap ffmpeg-free -> ffmpeg (may remove conflicting packages)" \
  $SUDO dnf -y swap ffmpeg-free ffmpeg --allowerasing

try "Install multimedia group (no weak deps, exclude PackageKit plugin)" \
  $SUDO dnf -y update @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin

# -------------------------
# GPU/Media drivers (interactive, with default)
# -------------------------
echo "Select your option:"
echo "  1) Intel"
echo "  2) AMD GPUs"
echo "  3) VM / Skip GPU driver setup"
echo "  4) NVIDIA"
read -rp "Enter 1, 2, 3, 4 [default: 3]: " choice
choice="${choice:-3}"

case "$choice" in
  1)
    try "Installing libva-intel-media-driver" \
      $SUDO dnf -y install libva-intel-media-driver
    ;;
  2)
    try "Swap mesa-va-drivers -> mesa-va-drivers-freeworld" \
      $SUDO dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld
    try "Swap mesa-vdpau-drivers -> mesa-vdpau-drivers-freeworld" \
      $SUDO dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
    try "Swap mesa-va-drivers.i686 -> mesa-va-drivers-freeworld.i686" \
      $SUDO dnf -y swap mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
    try "Swap mesa-vdpau-drivers.i686 -> mesa-vdpau-drivers-freeworld.i686" \
      $SUDO dnf -y swap mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
    ;;
  3)
    info "Skipping GPU/media driver installation."
    ;;
  4)
    try "Installing NVIDIA VA-API driver" \
      $SUDO dnf -y install libva-nvidia-driver
    try "Installing NVIDIA VA-API multilib packages" \
      $SUDO dnf -y install libva-nvidia-driver.{i686,x86_64}
    ;;
  *)
    warn "Invalid choice '$choice'. Skipping GPU/media drivers."
    ;;
esac

# -------------------------
# Flatpak & apps
# -------------------------
if command_exists flatpak; then
  try "Add Flathub (if missing)" flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
  warn "Flatpak is not installed. Skipping Flatpak steps."
fi

#Removes Fedora Flatpak repo
sudo flatpak remote-delete fedora


# Remove unwanted packages (ignore if not installed)
try "Removing selected packages (LibreOffice*, dragon, juk, elisa-player, kmail)" \
  $SUDO dnf remove -y 'libreoffice*' dragon juk elisa-player kmail

# Common tools
try "Installing base tools (fish, papirus-icon-theme, vlc, fastfetch, qdbus)" \
  $SUDO dnf -y install fish papirus-icon-theme vlc fastfetch qdbus

# Optional extras
read -rp "Install all extras (Cryptomator, Bitwarden, LocalSend, Syncthing, Jellyfin Meida Player, Finamp)? (y/N): " answer
answer="${answer,,}"
if [[ "$answer" =~ ^(y|yes)$ ]]; then
  if command_exists flatpak; then
    try "Installing extras via Flatpak" \
      flatpak install -y flathub \
        org.cryptomator.Cryptomator \
        com.bitwarden.desktop \
        org.localsend.localsend_app \
        com.github.zocker_160.SyncThingy \
        com.github.iwalton3.jellyfin-media-player \
        com.unicornsonlsd.finamp
  else
    warn "Flatpak not available; cannot install extras."
  fi
else
  info "Skipping extras."
fi

# ------------------------------------------------------------
# Nextcloud Apps for Syncing
# ------------------------------------------------------------

# Install the Nextcloud desktop client (Fedora package)
try "Installing Nextcloud desktop client" $SUDO dnf -y install nextcloud-client

# Install Iotas (Nextcloud-compatible notes app) via Flatpak
flatpak install -y flathub org.gnome.World.Iotas

# ----------------------------------------------------------------------
# === REMOVE GOOGLE CHROME COMPLETELY (Fedora) =========================
# ----------------------------------------------------------------------
remove_google_chrome() {
    echo "=== Removing Google Chrome packages ==="
    sudo dnf remove google-chrome-stable google-chrome-beta google-chrome-unstable -y

    echo "=== Removing Google Chrome repository ==="
    sudo dnf config-manager --set-disabled google-chrome 2>/dev/null || true
    sudo rm -f /etc/yum.repos.d/google-chrome.repo

    echo "=== Removing GPG key ==="
    sudo rpm --erase $(rpm -qa | grep -i 'gpg-pubkey.*7fac5991' | tr '\n' ' ') 2>/dev/null || true

    echo "=== Removing user configuration and cache ==="
    rm -rf ~/.config/google-chrome ~/.cache/google-chrome
    rm -f ~/.pki/nssdb/*chrome* 2>/dev/null || true

    echo "=== Removing desktop entries and icons ==="
    sudo rm -f /usr/share/applications/google-chrome*.desktop
    sudo rm -rf /usr/share/icons/hicolor/*/*/google-chrome* 2>/dev/null || true

    echo "=== Cleaning orphaned packages ==="
    sudo dnf autoremove -y

    echo "=== Verification ==="
    if rpm -qa | grep -qi chrome; then
        echo "Warning: Some Chrome-related RPMs still present!"
    else
        echo "No Chrome RPMs found."
    fi
    [ ! -f /etc/yum.repos.d/google-chrome.repo ] && echo "Repo file removed."
    [ ! -d ~/.config/google-chrome ] && echo "User config removed."
    echo "Google Chrome removal complete."
}

# Call the function (uncomment to run when script executes)
# remove_google_chrome

# -------------------------
# NetworkManager connectivity check (safer override)
# -------------------------
# Prefer a drop-in in /etc over modifying vendor file in /usr/lib
NM_DIR_ETC="/etc/NetworkManager/conf.d"
NM_FILE_ETC="${NM_DIR_ETC}/20-connectivity-fedora.conf"

info "Disabling NetworkManager connectivity check via /etc override..."
try "Create NetworkManager conf.d directory" $SUDO mkdir -p "$NM_DIR_ETC"
if [[ -e "$NM_FILE_ETC" ]]; then
  try "Backing up existing ${NM_FILE_ETC}" \
    $SUDO cp -n "$NM_FILE_ETC" "${NM_FILE_ETC}.bak"
fi
try "Writing override config" bash -c "cat <<'EOF' | $SUDO tee '$NM_FILE_ETC' >/dev/null
[connectivity]
enabled=false
EOF"

try "Reloading NetworkManager"  $SUDO systemctl reload NetworkManager
try "Restarting NetworkManager" $SUDO systemctl restart NetworkManager
info "Connectivity check disabled."

# -------------------------
# Brave enhancement script (best-effort)
# -------------------------
info "Starting Brave enhancement process (best-effort)..."
TMP_SCRIPT="./make_brave_great_again.sh"

if curl -fsSL https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/browser/Brave/make_brave_great_again.sh -o "$TMP_SCRIPT"; then
  try "chmod +x $TMP_SCRIPT" chmod +x "$TMP_SCRIPT"
  try "Run Brave enhancement script" "$TMP_SCRIPT"
  try "Cleanup Brave enhancement script" rm -f "$TMP_SCRIPT"
else
  warn "Could not download Brave enhancement script. Skipping."
fi

# -------------------------
# Optional gaming setup
# -------------------------
read -rp "Would you like to install the optional gaming packages? [y/N]: " INSTALL_GAMING
if [[ "$INSTALL_GAMING" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]; then
  GAMING_SCRIPT="$(mktemp /tmp/gaming-setup.XXXXXX.sh)" || die "Unable to create temp file for gaming script."
  info "Downloading gaming setup script..."
  if wget -q https://codeberg.org/X27/X-Linuxtools/raw/branch/main/Scripts/Gaming/Gaming.sh -O "$GAMING_SCRIPT"; then
    try "Run gaming setup script" $SUDO bash "$GAMING_SCRIPT"
  else
    warn "Could not download gaming setup script. Skipping."
  fi
  info "Cleaning up gaming setup script."
  rm -f "$GAMING_SCRIPT"
else
  info "Skipping gaming package installation."
fi

# -------------------------
# Finish
# -------------------------
info "All done. Some steps may have been skipped if they failed."
# Small pause for readability if run interactively
sleep 2