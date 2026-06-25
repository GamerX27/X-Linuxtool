#!/usr/bin/env bash
# Docker-Install.sh
# Installs Docker CE from Docker's official repository on:
#   - RHEL/Fedora family (rhel, centos, rocky, almalinux, ol/oracle, fedora)
#   - Debian/Ubuntu family (debian, ubuntu, linuxmint, pop)
# Behavior:
#   - Detects and removes Docker packages installed from the distro's own repos
#   - Sets up the official Docker repository and installs the latest Docker CE
#   - Enables and starts the docker service
#   - Adds the invoking (non-root) user to the "docker" group so they can run
#     docker commands without sudo

set -euo pipefail

# The user who should be added to the docker group.
# When run via sudo this resolves to the original (non-root) user.
TARGET_USER="${SUDO_USER:-${USER:-}}"

is_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (e.g., sudo bash $0)" >&2
    exit 1
  fi
}

detect_family() {
  # Prefer /etc/os-release
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
    echo "[ERROR] Could not determine a supported distro family. Aborting." >&2
    exit 2
  fi

  echo "[INFO] Detected distro: ${PRETTY_NAME:-${ID:-unknown}} (family: $FAMILY)"
}

# ----------------------------------------------------------------------------
# Removal of distro-provided / old Docker packages
# ----------------------------------------------------------------------------

remove_old_docker_debian() {
  echo "[INFO] Checking for existing (distro-provided) Docker packages..."
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
    echo "[INFO] Removing conflicting packages: ${found[*]}"
    apt-get remove -y "${found[@]}" || true
    echo "[OK] Removed distro-provided Docker packages."
  else
    echo "[INFO] No conflicting distro-provided Docker packages found."
  fi
}

remove_old_docker_rhel() {
  echo "[INFO] Checking for existing (distro-provided) Docker packages..."

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
    echo "[INFO] Removing conflicting packages: ${found[*]}"
    "$mgr" remove -y "${found[@]}" || true
    echo "[OK] Removed distro-provided Docker packages."
  else
    echo "[INFO] No conflicting distro-provided Docker packages found."
  fi
}

# ----------------------------------------------------------------------------
# Installation from Docker's official repository
# ----------------------------------------------------------------------------

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
    echo "[ERROR] Could not determine the distribution codename for the Docker repo." >&2
    exit 3
  fi

  echo "[INFO] Setting up Docker's official APT repository (${repo_base}, ${codename})..."
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

  echo "[INFO] Installing Docker CE..."
  apt-get update -y
  apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  echo "[OK] Docker CE installed."
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

  echo "[INFO] Setting up Docker's official repository (${repo_base})..."

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

  echo "[INFO] Installing Docker CE..."
  "$mgr" install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  echo "[OK] Docker CE installed."
}

# ----------------------------------------------------------------------------
# Service + user group setup
# ----------------------------------------------------------------------------

enable_service() {
  echo "[INFO] Enabling and starting the docker service..."
  if is_cmd systemctl; then
    systemctl enable --now docker
    echo "[OK] docker service enabled and started."
  else
    echo "[WARN] systemctl not found; please start the docker service manually."
  fi
}

add_user_to_docker_group() {
  if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    echo "[WARN] No non-root user detected (TARGET_USER='$TARGET_USER')."
    echo "       Run this script with sudo as your normal user, or add a user manually:"
    echo "         sudo usermod -aG docker <username>"
    return 0
  fi

  if ! getent group docker >/dev/null 2>&1; then
    echo "[INFO] Creating 'docker' group..."
    groupadd docker
  fi

  echo "[INFO] Adding user '$TARGET_USER' to the 'docker' group..."
  usermod -aG docker "$TARGET_USER"
  echo "[OK] User '$TARGET_USER' added to the 'docker' group."
  echo "[INFO] Log out and back in (or run 'newgrp docker') for the group change to take effect."
}

verify_install() {
  echo
  echo "== Verification =="
  if is_cmd docker; then
    docker --version || true
    docker compose version 2>/dev/null || true
  else
    echo "[WARN] docker command not found on PATH."
  fi
}

main() {
  require_root
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

  echo
  echo "[OK] Docker installation complete."
}

main "$@"
