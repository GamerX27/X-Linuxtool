#!/usr/bin/env bash
# Source https://github.com/CachyOS/proton-cachyos
set -euo pipefail

ui_info()    { printf '  › %s\n' "$1"; }
ui_ok()      { printf '  ✔ %s\n' "$1"; }
ui_warn()    { printf '  ▲ %s\n' "$1"; }
ui_err()     { printf '  ✖ %s\n' "$1" >&2; }
ui_step()    { printf '\n  ➤ %s\n' "$1"; }
ui_rule()    { printf '──────────────────────────────────────────────────────\n'; }

REPO="CachyOS/proton-cachyos"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    ui_info "Detected sudo; re-running as ${SUDO_USER} without root..."
    exec sudo -u "$SUDO_USER" -H env GITHUB_TOKEN="${GITHUB_TOKEN:-}" "$0" "$@"
  fi
  ui_err "Do not run as root. Run as your normal user so Steam can see it."
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    ui_err "'$1' is required but missing."
    exit 1
  fi
}
need curl
need tar

AUTH_HEADER=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")

find_compat_dir() {
  local candidates=(
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.steam/root/compatibilitytools.d"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"
  )
  for d in "${candidates[@]}"; do [[ -d "$d" ]] && { echo "$d"; return; }; done
  local d="$HOME/.local/share/Steam/compatibilitytools.d"
  mkdir -p "$d"
  echo "$d"
}

COMPAT_DIR="$(find_compat_dir)"
ui_info "Steam compatibility tools directory: $COMPAT_DIR"

CURRENT_LINK="$COMPAT_DIR/proton-cachyos"
CURRENT_TAG=""
if [[ -L "$CURRENT_LINK" ]]; then
  CURRENT_TAG="$(basename "$(readlink -f "$CURRENT_LINK")")"
  CURRENT_TAG="${CURRENT_TAG#proton-cachyos-}"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ui_step "Querying latest release..."
JSON="$(curl -fsSL "${AUTH_HEADER[@]}" "$API_URL")"

if command -v jq >/dev/null 2>&1; then
  TAG="$(echo "$JSON" | jq -r '.tag_name // empty')"
  ASSET_URL="$(echo "$JSON" | jq -r '[.assets[] | select(.name|test("slr-x86_64_v3\\.tar\\.xz$"))][0].browser_download_url // empty')"
  ASSET_NAME="$(basename "$ASSET_URL")"
else
  readarray -t parsed < <(python3 - <<'PY'
import sys, json, re
data=json.load(sys.stdin)
tag=data.get("tag_name","")
rx=re.compile(r'slr-x86_64_v3\.tar\.xz$',re.I)
asset=next((a for a in data.get("assets",[]) if rx.search(a.get("name",""))),{})
print(tag)
print(asset.get("browser_download_url",""))
PY
  <<<"$JSON")
  TAG="${parsed[0]}"
  ASSET_URL="${parsed[1]}"
  ASSET_NAME="$(basename "$ASSET_URL")"
fi

[[ -z "${ASSET_URL:-}" ]] && { ui_err "no matching asset found"; exit 1; }

if [[ -n "$CURRENT_TAG" && "$CURRENT_TAG" == "$TAG" ]]; then
  ui_ok "Proton-CachyOS is already up to date ($TAG)"
  exit 0
fi

ui_info "Latest version: $TAG"
ui_info "Downloading $ASSET_NAME..."
curl -fL --retry 3 "${AUTH_HEADER[@]}" -o "$TMP/$ASSET_NAME" "$ASSET_URL"

ui_info "Extracting..."
EXTRACT_DIR="$TMP/extract"
mkdir -p "$EXTRACT_DIR"

case "$ASSET_NAME" in
  *.tar.zst|*.tzst)
    if ! command -v unzstd >/dev/null 2>&1; then
      ui_err "Need zstd to extract .tar.zst/.tzst archives (package 'zstd')."
      exit 1
    fi
    tar --use-compress-program=unzstd -xf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    ;;
  *.tar.xz)
    tar -xJf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    ;;
  *.tar.bz2)
    tar -xjf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    ;;
  *)
    ui_err "Unknown archive format: $ASSET_NAME"
    exit 1
    ;;
esac

NEW_DIR_SRC="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 3 -type d -name 'files' -prune -o -type f -name 'compatibilitytool.vdf' -printf '%h\n' | head -n1)"
[[ -z "${NEW_DIR_SRC:-}" ]] && { ui_err "no Proton tool found"; exit 1; }

INSTALL_PATH="$COMPAT_DIR/proton-cachyos-$TAG"

ui_info "Removing older Proton CachyOS installs..."
find "$COMPAT_DIR" -mindepth 1 -maxdepth 1 -type d -iname 'proton-cachyos-*' -exec rm -rf {} +

ui_info "Installing to $INSTALL_PATH"
cp -a "$NEW_DIR_SRC" "$INSTALL_PATH"

# Overwrite compatibilitytool.vdf so Steam shows "Proton-CachyOS"
cat > "$INSTALL_PATH/compatibilitytool.vdf" <<'VDF'
"compatibilitytools"
{
    "compat_tools"
    {
        "proton-cachyos"
        {
            "display_name" "Proton-CachyOS"
            "from_oslist"  "windows"
            "to_oslist"    "linux"
            "install_path" "."
        }
    }
}
VDF

ln -sfn "$INSTALL_PATH" "$COMPAT_DIR/proton-cachyos"

echo
ui_ok "Installed Proton-CachyOS ($TAG)"
ui_info "Path: $INSTALL_PATH"
ui_info "Symlink: $COMPAT_DIR/proton-cachyos"
echo
ui_info "Restart Steam. You’ll see 'Proton-CachyOS' in the Compatibility dropdown."
