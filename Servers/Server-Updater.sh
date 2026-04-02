#!/usr/bin/env bash
# setup-auto-updates.sh
# Installs a cross-distro updater and schedules it via cron.
# - Creates /usr/local/sbin/os_update.sh
# - Adds /usr/local/bin/update-system (wrapper)
# - Prompts for monthly or weekly schedule + time (HH:MM or morning/afternoon/evening/night)
# - Sets /etc/cron.d/os_auto_update
# - Logs to /var/log/os_update.log
# - Supports --dry-run and optional auto-reboot
# - Optional Gotify integration for notifications

set -euo pipefail

# Initialize schedule globals to satisfy set -u before prompts
CRON_MIN=""
CRON_HR=""
CRON_DOM="*"
CRON_MON="*"
CRON_DOW="*"
SCHEDULE_DESC=""
AUTO_REBOOT="0"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root (e.g., sudo bash $0)" >&2
    exit 1
  fi
}

reset_existing_installation() {
  local removed=0
  local paths=(
    "/etc/cron.d/os_auto_update"
    "/usr/local/bin/update-system"
    "/usr/local/sbin/os_update.sh"
  )

  for target in "${paths[@]}"; do
    if [[ -e "$target" ]]; then
      rm -f "$target"
      echo "[INFO] Removed previous configuration: $target"
      removed=1
    fi
  done

  if (( removed )); then
    echo "[OK] Existing auto-update configuration reset."
  fi
}

install_updater_script() {
  local target="/usr/local/sbin/os_update.sh"
  cat > "$target" <<"EOF"
#!/usr/bin/env bash
# /usr/local/sbin/os_update.sh
# Cross-distro, non-interactive system updater with logging, dry-run, and optional Gotify notifications.

set -euo pipefail

LOGFILE="/var/log/os_update.log"

# Load optional Gotify configuration
GOTIFY_CONF="/etc/os_update_gotify.conf"
if [[ -r "$GOTIFY_CONF" ]]; then
  # shellcheck disable=SC1091
  . "$GOTIFY_CONF"
fi
GOTIFY_ENABLED="${GOTIFY_ENABLED:-0}"
GOTIFY_PRIORITY="${GOTIFY_PRIORITY:-5}"

# Default family (used in notifications)
family="unknown"

# If interactive TTY, mirror output to screen + log; otherwise log only
if [[ -t 1 ]]; then
  exec > >(tee -a "$LOGFILE") 2>&1
else
  exec >>"$LOGFILE" 2>&1
fi

# Support "--dry-run" argument or DRY_RUN=1 env
DRY_RUN=${DRY_RUN:-0}
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

echo "===== $(date -Is) : Starting system update (dry-run=$DRY_RUN) ====="

# Prefer /etc/os-release
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release || true
fi

is_cmd() { command -v "$1" >/dev/null 2>&1; }

# Gotify notification helper
gotify_notify() {
  local exit_code="$1"

  # Do nothing if Gotify is not configured/enabled
  if [[ "$GOTIFY_ENABLED" != "1" ]]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "[WARN] Gotify enabled but curl not found; skipping notification."
    return 0
  fi

  local status="SUCCESS"
  if [[ "$exit_code" -ne 0 ]]; then
    status="FAILURE (exit=$exit_code)"
  fi

  local log_tail=""
  if [[ -r "$LOGFILE" ]]; then
    set +e
    log_tail=$(tail -n 40 "$LOGFILE" 2>/dev/null)
    set -e
  fi

  local host
  host=$(hostname 2>/dev/null || echo "unknown-host")

  local title="os_update.sh on ${host} - ${status}"
  local msg="System update completed with status: ${status}
Host: ${host}
Distro family: ${family}
Dry-run: ${DRY_RUN}
Log tail:
${log_tail}"

  local base_url="${GOTIFY_URL:-}"
  local token="${GOTIFY_TOKEN:-}"

  if [[ -z "$base_url" || -z "$token" ]]; then
    echo "[WARN] Gotify enabled but GOTIFY_URL or GOTIFY_TOKEN not set; skipping notification."
    return 0
  fi

  base_url="${base_url%/}"
  local endpoint="${base_url}/message?token=${token}"

  set +e
  curl -s -X POST "$endpoint" \
    -F "title=${title}" \
    -F "message=${msg}" \
    -F "priority=${GOTIFY_PRIORITY}" >/dev/null 2>&1
  set -e
}

# Always notify on exit with final status (if Gotify is enabled)
trap 'gotify_notify "$?"' EXIT

update_debian() {
  echo "[INFO] Updating Debian/Ubuntu system..."
  if (( DRY_RUN )); then
    echo "[DRY] apt-get update -y"
    echo "[DRY] apt-get -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" dist-upgrade"
    echo "[DRY] apt-get -y autoremove --purge"
    echo "[DRY] apt-get -y autoclean"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade
  apt-get -y autoremove --purge
  apt-get -y autoclean
  if [[ "${AUTO_REBOOT:-0}" == "1" ]] && [[ -f /var/run/reboot-required ]]; then
    echo "[INFO] Reboot required. Rebooting in 1 minute..."
    /sbin/shutdown -r +1 "Auto-reboot after updates"
  fi
  echo "[INFO] Debian/Ubuntu update complete."
}

update_rhel() {
  local mgr=""
  if is_cmd dnf; then
    mgr="dnf"
    echo "[INFO] Updating RHEL/Fedora/CentOS system with dnf..."
    if (( DRY_RUN )); then
      echo "[DRY] dnf -y upgrade --refresh || dnf -y distro-sync --refresh"
      echo "[DRY] dnf -y autoremove"
      echo "[DRY] dnf -y clean all"
      return 0
    fi
    dnf -y upgrade --refresh || dnf -y distro-sync --refresh
    dnf -y autoremove || true
    dnf -y clean all || true
    if [[ "${AUTO_REBOOT:-0}" == "1" ]] && is_cmd needs-restarting; then
      if ! needs-restarting -r >/dev/null 2>&1; then
        echo "[INFO] Reboot required. Rebooting in 1 minute..."
        /sbin/shutdown -r +1 "Auto-reboot after updates"
      fi
    fi
    echo "[INFO] RHEL/Fedora/CentOS update complete (dnf)."
  elif is_cmd yum; then
    mgr="yum"
    echo "[INFO] Updating RHEL/Fedora/CentOS system with yum..."
    if (( DRY_RUN )); then
      echo "[DRY] yum -y update"
      echo "[DRY] yum -y autoremove"
      echo "[DRY] yum -y clean all"
      return 0
    fi
    yum -y update
    yum -y autoremove || true
    yum -y clean all || true
    if [[ "${AUTO_REBOOT:-0}" == "1" ]] && is_cmd needs-restarting; then
      if ! needs-restarting -r >/dev/null 2>&1; then
        echo "[INFO] Reboot required. Rebooting in 1 minute..."
        /sbin/shutdown -r +1 "Auto-reboot after updates"
      fi
    fi
    echo "[INFO] RHEL/Fedora/CentOS update complete (yum)."
  else
    echo "[ERROR] Neither dnf nor yum found." >&2
    exit 2
  fi
}

# Detect family
if [[ "${ID_LIKE:-}" =~ debian ]] || [[ "${ID:-}" =~ (debian|ubuntu|linuxmint|pop) ]]; then
  family="debian"
elif [[ "${ID_LIKE:-}" =~ (rhel|fedora) ]] || [[ "${ID:-}" =~ (rhel|centos|rocky|almalinux|ol|fedora|oracle) ]]; then
  family="rhel"
else
  if is_cmd apt-get; then
    family="debian"
  elif is_cmd dnf || is_cmd yum; then
    family="rhel"
  fi
fi

if [[ -z "$family" ]]; then
  echo "[ERROR] Could not determine distro. Aborting." >&2
  exit 3
fi

if [[ "$family" == "debian" ]]; then
  update_debian
else
  update_rhel
fi

echo "[INFO] Kernel: $(uname -r)"
echo "===== $(date -Is) : Update finished (dry-run=$DRY_RUN) ====="
EOF

  chmod 0755 "$target"
  echo "[OK] Installed updater: $target"
}

install_update_command() {
  local bin="/usr/local/bin/update-system"
  cat > "$bin" <<"EOF"
#!/usr/bin/env bash
# One-shot convenience wrapper to run the updater now.
args=("$@")
if [[ $EUID -ne 0 ]]; then
  exec sudo /usr/local/sbin/os_update.sh "${args[@]}"
else
  exec /usr/local/sbin/os_update.sh "${args[@]}"
fi
EOF
  chmod 0755 "$bin"
  echo "[OK] Installed command: $bin"
}

configure_gotify() {
  echo
  echo "== Gotify Notifications (optional) =="
  read -r -p "Configure Gotify notifications for update runs? [y/N] " GOTIFY_ANS || true
  if [[ "${GOTIFY_ANS,,}" != "y" ]]; then
    echo "[INFO] Gotify notifications not configured."
    return 0
  fi

  # Ensure curl exists before allowing configuration
  if ! command -v curl >/dev/null 2>&1; then
    echo "[WARN] curl is required for Gotify notifications but is not installed."
    read -r -p "Install curl now? [y/N] " CURL_ANS || true

    if [[ "${CURL_ANS,,}" == "y" ]]; then
      echo "[INFO] Installing curl..."
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y curl
      elif command -v dnf >/dev/null 2>&1; then
        dnf -y install curl
      elif command -v yum >/dev/null 2>&1; then
        yum -y install curl
      else
        echo "[ERROR] Could not determine package manager to install curl."
        exit 1
      fi

      if ! command -v curl >/dev/null 2>&1; then
        echo "[ERROR] Failed to install curl; cannot enable Gotify."
        return 0
      fi
    else
      echo "[INFO] Gotify cannot be enabled without curl. Skipping Gotify setup."
      return 0
    fi
  fi

  local url token priority
  while true; do
    read -r -p "Gotify base URL (e.g. https://gotify.example.com): " url
    [[ -n "$url" ]] && break
    echo "URL cannot be empty."
  done

  while true; do
    read -r -p "Gotify application token: " token
    [[ -n "$token" ]] && break
    echo "Token cannot be empty."
  done

  read -r -p "Default Gotify priority [1-10, default 5]: " priority || true
  if [[ -z "$priority" ]]; then
    priority=5
  elif ! [[ "$priority" =~ ^([1-9]|10)$ ]]; then
    echo "Invalid priority, using default 5."
    priority=5
  fi

  local conf="/etc/os_update_gotify.conf"
  cat > "$conf" <<EOF
# Gotify settings for /usr/local/sbin/os_update.sh
GOTIFY_ENABLED=1
GOTIFY_URL="$url"
GOTIFY_TOKEN="$token"
GOTIFY_PRIORITY="$priority"
EOF

  chown root:root "$conf"
  chmod 600 "$conf"
  echo "[OK] Gotify configuration saved to $conf"
}

read_schedule() {
  echo
  echo "== Auto-Update Schedule =="

  local MODE=""
  while true; do
    read -r -p "Schedule monthly or weekly updates? [m/w] " MODE || true
    case "${MODE,,}" in
      m|monthly)
        MODE="monthly"
        break
        ;;
      w|weekly|"")
        MODE="weekly"
        break
        ;;
      *)
        echo "Enter 'm' for monthly or 'w' for weekly."
        ;;
    esac
  done

  local SUMMARY=""
  if [[ "$MODE" == "weekly" ]]; then
    echo "Enter the day of the week (mon,tue,wed,thu,fri,sat,sun or 0-6; 0/7=Sun):"
    read -r DOW_IN

    local DNUM
    local DNAME=""
    case "${DOW_IN,,}" in
      0|7|sun|sunday) DNUM=0; DNAME="Sunday" ;;
      1|mon|monday)   DNUM=1; DNAME="Monday" ;;
      2|tue|tuesday)  DNUM=2; DNAME="Tuesday" ;;
      3|wed|wednesday) DNUM=3; DNAME="Wednesday" ;;
      4|thu|thursday) DNUM=4; DNAME="Thursday" ;;
      5|fri|friday)   DNUM=5; DNAME="Friday" ;;
      6|sat|saturday) DNUM=6; DNAME="Saturday" ;;
      *)
        echo "Invalid day. Try again."
        exit 10
        ;;
    esac
    CRON_DOM="*"
    CRON_MON="*"
    CRON_DOW="$DNUM"
    SUMMARY="$DNAME"
  else
    echo "Enter the day of the month (1-31) for the update run:"
    read -r DOM_IN
    if ! [[ "$DOM_IN" =~ ^([1-9]|[12][0-9]|3[01])$ ]]; then
      echo "Invalid day of month." >&2
      exit 12
    fi
    CRON_DOM="$DOM_IN"
    CRON_MON="*"
    CRON_DOW="*"
    SUMMARY="day $DOM_IN of each month"
  fi

  echo
  echo "Enter a time in 24h format **HH:MM**, or one of: morning / afternoon / evening / night"
  echo "  morning=09:00, afternoon=14:00, evening=19:00, night=02:00"
  read -r WHEN

  local HH=""
  local MM=""
  case "${WHEN,,}" in
    morning)   HH=09; MM=00 ;;
    afternoon) HH=14; MM=00 ;;
    evening)   HH=19; MM=00 ;;
    night)     HH=02; MM=00 ;;
    *)
      if [[ "$WHEN" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        HH="${WHEN%:*}"
        MM="${WHEN#*:}"
      else
        echo "Invalid time. Use HH:MM or a named period." >&2
        exit 11
      fi
      ;;
  esac

  CRON_MIN="$(printf '%02d' "$MM")"
  CRON_HR="$(printf '%02d' "$HH")"
  SCHEDULE_DESC="$SUMMARY at $CRON_HR:$CRON_MIN"

  echo
  read -r -p "Auto-reboot if required packages update? [y/N] " REBOOT_ANS || true
  if [[ "${REBOOT_ANS,,}" == "y" ]]; then
    AUTO_REBOOT="1"
  else
    AUTO_REBOOT="0"
  fi
}

install_cron() {
  local cronfile="/etc/cron.d/os_auto_update"

  # Ensure log file exists and is writable
  touch /var/log/os_update.log
  chmod 0644 /var/log/os_update.log

  # Export AUTO_REBOOT in the cron environment
  cat > "$cronfile" <<EOF
# Auto system updates (managed by setup-auto-updates.sh)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
AUTO_REBOOT=$AUTO_REBOOT

$CRON_MIN $CRON_HR $CRON_DOM $CRON_MON $CRON_DOW root /usr/local/sbin/os_update.sh
EOF

  chown root:root "$cronfile"
  chmod 0644 "$cronfile"
  echo "[OK] Cron installed: $cronfile"
  if [[ -n "$SCHEDULE_DESC" ]]; then
    echo "[OK] Will run $SCHEDULE_DESC."
  else
    echo "[OK] Will run at $CRON_HR:$CRON_MIN with cron DOM=$CRON_DOM MON=$CRON_MON DOW=$CRON_DOW."
  fi
  if [[ "$AUTO_REBOOT" == "1" ]]; then
    echo "[OK] Auto-reboot: ENABLED"
  else
    echo "[OK] Auto-reboot: disabled"
  fi
  echo "    Log: /var/log/os_update.log"
}

maybe_offer_run() {
  echo
  read -r -p "Run an update now? [y/N] " RUNNOW || true
  if [[ "${RUNNOW,,}" == "y" ]]; then
    /usr/local/bin/update-system
  fi

  echo
  echo "To uninstall:"
  echo "  sudo rm -f /etc/cron.d/os_auto_update /usr/local/bin/update-system /usr/local/sbin/os_update.sh /etc/os_update_gotify.conf"
  echo "  sudo systemctl restart cron 2>/dev/null || sudo systemctl restart crond 2>/dev/null || true"
}

main() {
  require_root
  reset_existing_installation
  install_updater_script
  install_update_command
  configure_gotify     # optional, checks curl if enabling Gotify
  read_schedule
  install_cron
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  maybe_offer_run
}

main "$@"
