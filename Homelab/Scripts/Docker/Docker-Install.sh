#!/usr/bin/env bash

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

TARGET_USER=""

is_cmd() { command -v "$1" >/dev/null 2>&1; }

# SUDO_USER alone is unreliable here: this script is often invoked via a
# nested `sudo` call made by a process that is already root (e.g.
# X27-Homelab.sh), which resets SUDO_USER to "root" instead of the real
# login user. /proc/self/loginuid survives nested su/sudo, so it's tried
# first.
detect_target_user() {
  local candidate=""

  if [[ -z "$candidate" ]]; then
    local login_uid
    login_uid="$(cat /proc/self/loginuid 2>/dev/null || true)"
    # 4294967295 (-1 unsigned) means "no login uid recorded"
    if [[ -n "$login_uid" && "$login_uid" != "4294967295" && "$login_uid" != "0" ]]; then
      candidate="$(id -un "$login_uid" 2>/dev/null || true)"
    fi
  fi

  if [[ -z "$candidate" ]] && is_cmd logname; then
    local ln
    ln="$(logname 2>/dev/null || true)"
    [[ -n "$ln" && "$ln" != "root" ]] && candidate="$ln"
  fi

  if [[ -z "$candidate" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    candidate="$SUDO_USER"
  fi

  if [[ -z "$candidate" && -n "${PKEXEC_UID:-}" ]]; then
    candidate="$(id -un "$PKEXEC_UID" 2>/dev/null || true)"
  fi

  if [[ -z "$candidate" && -n "${USER:-}" && "$USER" != "root" ]]; then
    candidate="$USER"
  fi

  if [[ -n "$candidate" ]] && ! getent passwd "$candidate" >/dev/null 2>&1; then
    ui_warn "Detected user '$candidate' does not exist on this system; ignoring."
    candidate=""
  fi

  TARGET_USER="$candidate"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    ui_err "Please run as root (e.g., sudo bash $0)"
    exit 1
  fi
}

detect_family() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release || true
  fi

  FAMILY=""
  if [[ "${ID_LIKE:-}" =~ debian ]] || [[ "${ID:-}" =~ (debian|ubuntu|linuxmint|pop) ]]; then
    FAMILY="debian"
  elif [[ "${ID_LIKE:-}" =~ (rhel|fedora) ]] || [[ "${ID:-}" =~ (rhel|centos|rocky|almalinux|ol|oracle|fedora) ]]; then
    FAMILY="rhel"
  else
    if is_cmd apt-get; then
      FAMILY="debian"
    elif is_cmd dnf || is_cmd yum; then
      FAMILY="rhel"
    fi
  fi

  if [[ -z "$FAMILY" ]]; then
    ui_err "Could not determine a supported distro family. Aborting."
    exit 2
  fi

  ui_info "Detected distro: ${PRETTY_NAME:-${ID:-unknown}} (family: $FAMILY)"
}

remove_old_docker_debian() {
  ui_info "Checking for existing (distro-provided) Docker packages..."
  export DEBIAN_FRONTEND=noninteractive

  local pkgs=(
    docker.io
    docker-doc
    docker-compose
    docker-compose-v2
    podman-docker
    containerd
    runc
  )

  local found=()
  local p
  for p in "${pkgs[@]}"; do
    if dpkg -s "$p" >/dev/null 2>&1; then
      found+=("$p")
    fi
  done

  if (( ${#found[@]} )); then
    ui_info "Removing conflicting packages: ${found[*]}"
    apt-get remove -y "${found[@]}" || true
    ui_ok "Removed distro-provided Docker packages."
  else
    ui_info "No conflicting distro-provided Docker packages found."
  fi
}

remove_old_docker_rhel() {
  ui_info "Checking for existing (distro-provided) Docker packages..."

  local mgr="dnf"
  is_cmd dnf || mgr="yum"

  local pkgs=(
    docker
    docker-client
    docker-client-latest
    docker-common
    docker-latest
    docker-latest-logrotate
    docker-logrotate
    docker-engine
    podman-docker
    runc
  )

  local found=()
  local p
  for p in "${pkgs[@]}"; do
    if rpm -q "$p" >/dev/null 2>&1; then
      found+=("$p")
    fi
  done

  if (( ${#found[@]} )); then
    ui_info "Removing conflicting packages: ${found[*]}"
    "$mgr" remove -y "${found[@]}" || true
    ui_ok "Removed distro-provided Docker packages."
  else
    ui_info "No conflicting distro-provided Docker packages found."
  fi
}

install_docker_debian() {
  export DEBIAN_FRONTEND=noninteractive

  local distro_id="${ID:-debian}"
  local repo_base="https://download.docker.com/linux/${distro_id}"

  # Ubuntu derivatives (e.g. linuxmint, pop) use the Ubuntu repo + codename
  local codename="${VERSION_CODENAME:-}"
  case "$distro_id" in
    ubuntu|linuxmint|pop)
      repo_base="https://download.docker.com/linux/ubuntu"
      # UBUNTU_CODENAME is set on Ubuntu-based derivatives
      codename="${UBUNTU_CODENAME:-$codename}"
      ;;
  esac

  if [[ -z "$codename" ]]; then
    ui_err "Could not determine the distribution codename for the Docker repo."
    exit 3
  fi

  ui_info "Setting up Docker's official APT repository (${repo_base}, ${codename})..."
  apt-get update -y
  apt-get install -y ca-certificates curl

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "${repo_base}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  local arch
  arch="$(dpkg --print-architecture)"

  cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] ${repo_base} ${codename} stable
EOF

  ui_info "Installing Docker CE..."
  apt-get update -y
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  ui_ok "Docker CE installed."
}

install_docker_rhel() {
  local mgr="dnf"
  is_cmd dnf || mgr="yum"

  local distro_id="${ID:-rhel}"
  local repo_base="https://download.docker.com/linux/centos"

  case "$distro_id" in
    fedora)
      repo_base="https://download.docker.com/linux/fedora"
      ;;
    rhel|centos|rocky|almalinux|ol|oracle)
      repo_base="https://download.docker.com/linux/centos"
      ;;
  esac

  ui_info "Setting up Docker's official repository (${repo_base})..."

  # Ensure config-manager plugin is available for adding repos
  if [[ "$mgr" == "dnf" ]]; then
    "$mgr" -y install dnf-plugins-core || true
    if "$mgr" config-manager --help 2>&1 | grep -q -- '--add-repo'; then
      "$mgr" config-manager --add-repo "${repo_base}/docker-ce.repo"
    else
      # Newer dnf5 syntax
      "$mgr" config-manager addrepo --from-repofile="${repo_base}/docker-ce.repo"
    fi
  else
    "$mgr" -y install yum-utils || true
    yum-config-manager --add-repo "${repo_base}/docker-ce.repo"
  fi

  ui_info "Installing Docker CE..."
  "$mgr" install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  ui_ok "Docker CE installed."
}

enable_service() {
  ui_info "Enabling and starting the docker service..."
  if is_cmd systemctl; then
    systemctl enable --now docker
    ui_ok "docker service enabled and started."
  else
    ui_warn "systemctl not found; please start the docker service manually."
  fi
}

add_user_to_docker_group() {
  if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    ui_warn "Could not auto-detect a non-root user to add to the 'docker' group."

    if [[ -t 0 && -t 1 ]]; then
      local reply
      printf '%s       Enter the username to add to the docker group (blank to skip): %s' "$C_GREY$C_DIM" "$C_RESET"
      read -r reply || reply=""
      if [[ -n "$reply" ]] && getent passwd "$reply" >/dev/null 2>&1; then
        TARGET_USER="$reply"
      elif [[ -n "$reply" ]]; then
        ui_warn "No such user '$reply'; skipping."
      fi
    fi

    if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
      printf '%s       Add a user manually with:%s\n' "$C_GREY$C_DIM" "$C_RESET"
      printf '%s         sudo usermod -aG docker <username>%s\n' "$C_GREY$C_DIM" "$C_RESET"
      return 0
    fi
  fi

  if ! getent group docker >/dev/null 2>&1; then
    ui_info "Creating 'docker' group..."
    groupadd docker
  fi

  ui_info "Adding user '$TARGET_USER' to the 'docker' group..."
  usermod -aG docker "$TARGET_USER"
  ui_ok "User '$TARGET_USER' added to the 'docker' group."
  ui_info "Log out and back in (or run 'newgrp docker') for the group change to take effect."
}

verify_install() {
  ui_step "Verification"
  if is_cmd docker; then
    docker --version || true
    docker compose version 2>/dev/null || true
  else
    ui_warn "docker command not found on PATH."
  fi
}

main() {
  require_root
  detect_target_user
  detect_family

  if [[ "$FAMILY" == "debian" ]]; then
    remove_old_docker_debian
    install_docker_debian
  else
    remove_old_docker_rhel
    install_docker_rhel
  fi

  enable_service
  add_user_to_docker_group
  verify_install

  ui_ok "Docker installation complete."
}

main "$@"
