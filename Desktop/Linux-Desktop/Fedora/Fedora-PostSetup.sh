#!/usr/bin/env bash
#
# Run as your normal user, not with sudo — it caches its own sudo session
# after one password prompt. Idempotent; safe to re-run.

set -uo pipefail

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_MAGENTA=$'\033[35m'
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA=""
fi

log() {
    printf '\n%s==>%s %s%s%s\n' "$C_BLUE$C_BOLD" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
}

ok() {
    printf '%s  ✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

warn() {
    printf '%sWarning:%s %s\n' "$C_YELLOW$C_BOLD" "$C_RESET" "$1" >&2
}

err() {
    printf '\n%sError:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$1" >&2
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command '$1' not found."
        exit 1
    fi
}

# run_step <description> <shell command string>
# Runs a long-running command (dnf/flatpak/curl install, etc.) in the
# background and draws our own spinner + elapsed time in front of it,
# instead of relying on the command's own progress output — dnf's live
# download bar depends on stdout being a real tty at the exact moment it
# runs, which isn't reliable across every way this script gets launched
# (curl | bash, nested dispatchers, etc.). The command's actual output is
# captured and only shown if it fails, so a run still tells you what broke.
run_step() {
    local desc="$1" cmd="$2" logfile pid status i=0 elapsed start
    logfile="$(mktemp /tmp/x27-step.XXXXXX.log)"
    start=$(date +%s)

    bash -c "$cmd" >"$logfile" 2>&1 &
    pid=$!

    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start ))
        i=$(( (i + 1) % ${#spin} ))
        printf '\r%s%s%s %s (%ds) ' \
            "$C_BLUE" "${spin:i:1}" "$C_RESET" "$desc" "$elapsed"
        sleep 0.12
    done
    wait "$pid"
    status=$?

    printf '\r\033[K'
    if [ "$status" -eq 0 ]; then
        ok "$desc"
    else
        warn "${desc} — failed (exit ${status}, continuing)"
        sed 's/^/    /' "$logfile" >&2
    fi
    rm -f "$logfile"
    return "$status"
}

# Repository locations: Codeberg is primary, GitHub is a fallback mirror.
CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Desktop/Linux-Desktop"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Desktop/Linux-Desktop"

# When invoked by a local X-Linuxtool.sh clone, X27_LOCAL_ROOT points at
# the clone root; prefer the scripts already on disk over re-downloading.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Desktop/Linux-Desktop}"

_download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        err "Neither curl nor wget is available."
        return 1
    fi
}

fetch_repo_file() {
    local rel="$1" out="$2"

    if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE/$rel" ]; then
        log "Using local copy: ${rel}"
        cp "$LOCAL_BASE/$rel" "$out"
        return 0
    fi

    log "Fetching ${rel} from Codeberg"
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        return 0
    fi

    warn "Codeberg unreachable; falling back to GitHub mirror."
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        return 0
    fi

    err "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}

# Ask a yes/no question; returns 0 for yes, 1 for anything else (default no).
ask_yes_no() {
    local prompt="$1" answer
    printf '%s [y/N]: ' "$prompt"
    read -r answer
    case "${answer}" in
        [yY] | [yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

set_locale_time() {
    run_step "Setting LC_TIME to C.UTF-8" "sudo localectl set-locale LC_TIME=C.UTF-8"
}

if [[ "${EUID}" -eq 0 ]]; then
    err "Do not run this script with sudo or as root. Run it as your normal user; it will request sudo itself."
    exit 1
fi

require_cmd sudo
require_cmd dnf
require_cmd rpm

# Authenticate sudo once up front, then keep the timestamp alive in the
# background so the system (sudo) steps never re-prompt, while the per-user
# steps run as the normal user with no authentication at all.
log "Requesting administrator access (you will be asked for your password once)"
sudo -v

while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" 2>/dev/null || exit
done < /dev/null &> /dev/null &
SUDO_KEEPALIVE_PID=$!

cleanup() {
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
}
trap cleanup EXIT

FEDORA_VERSION="$(rpm -E %fedora)"
log "Detected Fedora ${FEDORA_VERSION}"
log "This will take a while — sit back and let it run."

log "Refreshing metadata and upgrading the system"
run_step "Refreshing metadata" "sudo dnf update --refresh -y" \
    && run_step "Upgrading system packages" "sudo dnf upgrade -y"

log "Enabling RPM Fusion (free + nonfree) repositories"
run_step "Enabling RPM Fusion" \
    "sudo dnf install -y \
        'https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm' \
        'https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm'"

log "Enabling the Cisco OpenH264 repository"
run_step "Enabling Cisco OpenH264 repository" "sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1"

log "Updating the @core package group"
run_step "Updating @core package group" "sudo dnf update -y @core"

log "Switching to the full ffmpeg build"
run_step "Switching to full ffmpeg build" "sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y"

log "Installing additional multimedia codecs"
run_step "Installing multimedia codecs" \
    "sudo dnf update -y @multimedia --setopt='install_weak_deps=False' --exclude=PackageKit-gstreamer-plugin"

log "Hardware-accelerated video codecs"

if [[ "$(systemd-detect-virt 2>/dev/null)" != "none" ]]; then
    warn "Running in a VM; skipping hardware-accelerated codec installation."
else

# Detects vendor keywords across all VGA/3D controller lines rather than just
# the first, so hybrid laptops (e.g. Intel iGPU + NVIDIA dGPU) still get the
# iGPU codec driver instead of being misdetected as NVIDIA-only.
detect_gpu_vendors() {
    lspci -nnk 2>/dev/null \
        | grep -Ei 'vga compatible controller|3d controller|display controller' \
        | grep -oiE 'intel|amd|ati|nvidia' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u
}

# Intel model numbers encode generation: a 4-digit number's first digit is the
# generation (gen 1-9), a 5-digit number's first two digits are (gen 10+).
# intel-media-driver (iHD) targets Broadwell/gen5 and newer; older chips need
# the legacy libva-intel-driver (i965).
detect_intel_generation() {
    local model
    model="$(grep -m1 '^model name' /proc/cpuinfo)"
    if [[ "$model" =~ i[3579]-([0-9]{4,5}) ]]; then
        local num="${BASH_REMATCH[1]}"
        if [[ ${#num} -eq 5 ]]; then
            echo "${num:0:2}"
        else
            echo "${num:0:1}"
        fi
    fi
}

gpu_vendors="$(detect_gpu_vendors)"
found_intel=0
found_amd=0
found_nvidia=0
while read -r v; do
    case "$v" in
        intel) found_intel=1 ;;
        amd | ati) found_amd=1 ;;
        nvidia) found_nvidia=1 ;;
    esac
done <<< "$gpu_vendors"

if [[ $found_intel -eq 1 ]]; then
    intel_gen="$(detect_intel_generation)"
    if [[ -n "$intel_gen" && "$intel_gen" -lt 5 ]]; then
        log "Detected Intel GPU (pre-Broadwell, gen ${intel_gen})"
        run_step "Installing Intel (older) codecs" "sudo dnf install -y libva-intel-driver"
    else
        log "Detected Intel GPU (Broadwell/5th-gen or newer)"
        run_step "Installing Intel (recent) codecs" "sudo dnf install -y intel-media-driver"
    fi
fi

if [[ $found_amd -eq 1 ]]; then
    log "Detected AMD GPU"
    run_step "Installing AMD codecs" "sudo dnf install -y mesa-va-drivers-freeworld mesa-va-drivers-freeworld.i686"
fi

if [[ $found_nvidia -eq 1 && $found_intel -eq 0 && $found_amd -eq 0 ]]; then
    warn "Detected NVIDIA GPU only — hardware-accelerated codec install for NVIDIA isn't automated yet, skipping."
fi

if [[ $found_intel -eq 0 && $found_amd -eq 0 && $found_nvidia -eq 0 ]]; then
    warn "Could not detect GPU vendor; skipping hardware-accelerated codec installation."
fi

fi

log "Removing unwanted default applications"
run_step "Removing unwanted default applications" \
    "sudo dnf remove -y \
        dragon juk elisa-player kmail khelpcenter kmahjongg kmines kpat firefox \
        kaddressbook korganizer kolourpaint kamoso neochat 'libreoffice*'"

log "Installing base command-line tools"
# Note: lspci ships in pciutils, sensors ships in lm_sensors.
run_step "Installing base command-line tools" \
    "sudo dnf install -y wget fastfetch fish htop nano papirus-icon-theme curl pciutils lm_sensors"

log "Setting Fish as the default login shell"
run_step "Setting Fish as the default login shell" "sudo chsh -s \"\$(command -v fish)\" \"$USER\""

log "Configuring Konsole (Fish default profile, hidden toolbars)"
mkdir -p ~/.local/share/konsole ~/.local/share/kxmlgui5/konsole

cat > ~/.local/share/konsole/Fish.profile <<'EOF'
[General]
Command=/usr/bin/fish
Name=Fish
Parent=FALLBACK/
EOF

cat > ~/.config/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=Fish.profile

[General]
ConfigVersion=1

[MainWindow]
MenuBar=Disabled

[SplitView]
SplitViewVisibility=AlwaysHideSplitHeader

[TabBar]
TabBarVisibility=AlwaysHideTabBar
EOF

# Minimal KXMLGUI override; Konsole merges "hidden" into its built-in toolbar defs on launch.
cat > ~/.local/share/kxmlgui5/konsole/konsoleui.rc <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="konsole" version="1">
    <ToolBar name="mainToolBar" hidden="true">
        <text>Main Toolbar</text>
    </ToolBar>
</gui>
EOF

cat > ~/.local/share/kxmlgui5/konsole/sessionui.rc <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE gui SYSTEM "kpartgui.dtd">
<gui name="session" version="1">
    <ToolBar name="sessionToolbar" hidden="true">
        <text>Session Toolbar</text>
    </ToolBar>
</gui>
EOF

ok "Konsole configured: Fish is the default profile, all toolbars/tab bar hidden."

log "Applying full dark mode and Papirus-Dark icons"
KICKOFF_CFG="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

read -r cont applet < <(awk '
    /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { path = $0; gsub(/[^0-9]/, " ", path) }
    /^plugin=org\.kde\.plasma\.kickoff$/ { print path; exit }
' "$KICKOFF_CFG")

run_step "Applying dark mode and Papirus-Dark icons" \
    "plasma-apply-lookandfeel -a org.kde.breezedark.desktop && kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark"

# Papirus ships a Fedora-branded "start-here-fedora" launcher icon; the
# theme changes above reset the launcher back to KDE's default, so reapply it.
if [ -n "${cont:-}" ] && [ -n "${applet:-}" ]; then
    kwriteconfig6 --file "$KICKOFF_CFG" \
        --group Containments --group "$cont" --group Applets --group "$applet" \
        --group Configuration --group General --key icon start-here-fedora
fi

kquitapp6 plasmashell 2>/dev/null && (kstart6 plasmashell >/dev/null 2>&1 &)

log "Installing base applications"
run_step "Installing base applications" \
    "sudo dnf install -y vlc nextcloud-client easyeffects gnome-disk-utility libreoffice-writer gwenview"

require_cmd flatpak

log "Adding the Flathub remote"
# Flatpaks are installed system-wide, so the remote must be configured
# system-wide too. This needs root: the cached sudo session covers it without
# triggering a polkit prompt (which would otherwise fail in a non-interactive
# context with "ConfigureRemote not allowed for user").
run_step "Adding the Flathub remote" \
    "sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"

log "Running the Flatpak app install script"
FLATPAKS_SCRIPT="$(mktemp /tmp/flatpaks.XXXXXX.sh)"
fetch_repo_file "Flatpak/flatpaks.sh" "${FLATPAKS_SCRIPT}"
run_step "Installing Flatpak apps" "sudo bash '${FLATPAKS_SCRIPT}'"
rm -f "${FLATPAKS_SCRIPT}"

log "Disabling the Fedora Flatpak remotes"
run_step "Disabling Fedora Flatpak remotes" \
    "sudo flatpak remote-modify fedora --disable && sudo flatpak remote-modify fedora-testing --disable"

log "Installing Vivaldi (Flatpak)"
run_step "Installing Vivaldi" "sudo flatpak install -y flathub com.vivaldi.Vivaldi"

log "Disabling the NetworkManager connectivity check"
# An empty connectivity URI disables the check. We write the override to /etc
# (the proper override location) so it persists across updates and survives the
# removal of the vendor connectivity config package below.
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/20-connectivity-fedora.conf >/dev/null <<'EOF'
[connectivity]
uri=
EOF

run_step "Disabling NetworkManager connectivity check" \
    "sudo dnf remove -y NetworkManager-config-connectivity-fedora; sudo systemctl restart NetworkManager"

log "Waiting 10 seconds for NetworkManager to settle"
sleep 10

log "Installing the Brave browser (origin flavor)"
run_step "Installing Brave browser" "curl -fsS https://dl.brave.com/install.sh | FLAVOR=origin sh"

log "Setting Brave as the default web browser"
xdg-settings set default-web-browser brave-origin.desktop \
    && ok "Brave set as the default web browser." \
    || warn "Failed to set Brave as the default web browser (continuing)."

log "Applying Brave policy configuration"
BRAVE_POLICY_SCRIPT="$(mktemp /tmp/make_brave_great_again.XXXXXX.sh)"
fetch_repo_file "Browser/make_brave_great_again.sh" "${BRAVE_POLICY_SCRIPT}"
run_step "Applying Brave policy configuration" "sudo bash '${BRAVE_POLICY_SCRIPT}'"
rm -f "${BRAVE_POLICY_SCRIPT}"

log "Installing LibreWolf"
# --overwrite keeps this idempotent so re-running the script doesn't error out.
sudo dnf config-manager addrepo --overwrite --from-repofile=https://repo.librewolf.net/librewolf.repo
run_step "Installing LibreWolf" "sudo dnf install -y librewolf"

log "Installing additional browsers (Chromium, Tor Browser Launcher)"
run_step "Installing Chromium and Tor Browser Launcher" "sudo dnf install -y chromium torbrowser-launcher"

log "Gaming setup"
if ask_yes_no "Would you like to run the gaming setup script?"; then
    log "Running the gaming setup script"
    GAMING_SCRIPT="$(mktemp /tmp/Gaming.XXXXXX.sh)"
    fetch_repo_file "Gaming/Gaming.sh" "${GAMING_SCRIPT}"
    run_step "Running gaming setup script" "sudo bash '${GAMING_SCRIPT}'"
    rm -f "${GAMING_SCRIPT}"
else
    log "Skipping gaming setup"
fi

set_locale_time

log "Zed editor"
if ask_yes_no "Would you like to install the Zed editor?"; then
    run_step "Installing Zed editor" "curl -f https://zed.dev/install.sh | sh"
else
    log "Skipping Zed editor installation"
fi

log "Removing orphaned packages"
run_step "Removing orphaned packages" "sudo dnf autoremove -y"

log "Fedora post-setup complete."

if ask_yes_no "Would you like to reboot now?"; then
    log "Rebooting in..."
    for count in 5 4 3 2 1; do
        echo "$count"
        sleep 1
    done
    sudo systemctl reboot
else
    log "Reboot skipped. Remember to reboot later to apply all changes."
fi
