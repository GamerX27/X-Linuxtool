#!/bin/bash
# QEMU/KVM + virt-manager installer for apt/dnf/pacman
# NAT networking only (no bridged setup)
# Adds current user to libvirt & kvm groups
# Debian fix: disable system dnsmasq to avoid libvirt conflicts

set -euo pipefail

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

detect_distro() {
  ui_info "Detecting Linux distribution..."
  if [[ -f /etc/os-release ]]; then . /etc/os-release; fi
  case "${ID:-unknown}" in
    ubuntu|debian) PKG_MGR="apt" ;;
    fedora)        PKG_MGR="dnf" ;;
    centos|rocky|almalinux|alma|rhel|ol) PKG_MGR="dnf" ;;
    arch|manjaro|endeavouros|arcolinux)  PKG_MGR="pacman" ;;
    *)
      case "${ID_LIKE:-}" in
        *debian*) PKG_MGR="apt" ;;
        *rhel*|*fedora*) PKG_MGR="dnf" ;;
        *arch*) PKG_MGR="pacman" ;;
        *) ui_err "Unsupported distribution."; exit 1 ;;
      esac
      ;;
  esac
  ui_info "Detected package manager: $PKG_MGR"
}

update_system() {
  ui_info "Updating package metadata..."
  case "$PKG_MGR" in
    apt)    apt-get update -y ;;
    dnf)    dnf -y update ;;
    pacman) pacman -Sy --noconfirm && pacman -Su --noconfirm ;;
  esac
}

install_packages() {
  ui_info "Installing QEMU/KVM, libvirt, and virt-manager..."
  case "$PKG_MGR" in
    apt)
      apt-get install -y \
        qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager \
        bridge-utils dnsmasq ebtables
      ;;
    dnf)
      if [[ "${ID:-}" =~ (centos|rocky|almalinux|alma|rhel|ol) ]]; then
        dnf install -y epel-release || true
      fi
      dnf install -y qemu-kvm qemu-img libvirt virt-install virt-manager \
        bridge-utils dnsmasq ebtables || true
      ;;
    pacman)
      pacman -S --needed --noconfirm qemu-full libvirt virt-manager dnsmasq bridge-utils ebtables
      ;;
  esac
  ui_ok "Package installation completed."
}

configure_default_network() {
  ui_info "Configuring default libvirt NAT network..."

  if [[ "$PKG_MGR" == "apt" ]]; then
    ui_info "Applying Debian/Ubuntu dnsmasq fix..."
    systemctl stop dnsmasq || true
    systemctl disable dnsmasq || true
  fi

  systemctl restart libvirtd || true
  if ! virsh net-info default &>/dev/null; then
    if [[ -f /usr/share/libvirt/networks/default.xml ]]; then
      virsh net-define /usr/share/libvirt/networks/default.xml || true
    else
      virsh net-define <(cat <<'EOF'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
) || true
    fi
  fi

  virsh net-start default 2>/dev/null || true
  virsh net-autostart default 2>/dev/null || true
  ui_ok "NAT network 'default' active on virbr0."
}

add_user_to_groups() {
  ui_info "Adding user to libvirt/kvm groups..."
  local GROUP_LIBVIRT="libvirt"
  getent group libvirt >/dev/null || { getent group libvirtd >/dev/null && GROUP_LIBVIRT="libvirtd"; }
  getent group "$GROUP_LIBVIRT" >/dev/null || groupadd "$GROUP_LIBVIRT"

  local USER_TO_ADD="${SUDO_USER:-$USER}"
  if [[ -n "$USER_TO_ADD" && "$USER_TO_ADD" != "root" ]]; then
    usermod -aG "$GROUP_LIBVIRT" "$USER_TO_ADD" || true
    if getent group kvm >/dev/null; then usermod -aG kvm "$USER_TO_ADD" || true; fi
    ui_ok "Added $USER_TO_ADD to groups: $GROUP_LIBVIRT $(getent group kvm >/dev/null && echo 'kvm')."
  else
    ui_warn "No non-root user detected; skipping group changes."
  fi
}

enable_libvirt_service() {
  ui_info "Enabling and starting libvirtd..."
  systemctl enable --now libvirtd.service || true
  systemctl enable --now libvirtd.socket || true
  ui_ok "libvirtd is enabled."
}

if [[ $EUID -ne 0 ]]; then
  ui_err "Run as root (sudo)."; exit 1
fi

detect_distro
update_system
install_packages
configure_default_network
enable_libvirt_service
add_user_to_groups

ui_step "All set. Launch 'virt-manager'."
ui_info "NAT network 'default' on virbr0 is active."
ui_warn "Log out/in if group changes don't take effect immediately."
