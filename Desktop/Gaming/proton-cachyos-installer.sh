#!/usr/bin/env bash
# Source https://github.com/CachyOS/proton-cachyos
set -euo pipefail

REPO="CachyOS/proton-cachyos"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# --- don't run as root (but gracefully drop sudo if used)
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "Detected sudo; re-running as ${SUDO_USER} without root..."
    exec sudo -u "$SUDO_USER" -H env GITHUB_TOKEN="${GITHUB_TOKEN:-}" "$0" "$@"
  fi
  echo "Do not run as root. Run as your normal user so Steam can see it." >&2
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required but missing." >&2
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
echo "Steam compatibility tools directory: $COMPAT_DIR"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Querying latest release..."
JSON="$(curl -fsSL "${AUTH_HEADER[@]}" "$API_URL")"

# Parse latest asset with the specific pattern
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

[[ -z "${ASSET_URL:-}" ]] && { echo "Error: no matching asset found"; exit 1; }

echo "Latest version: $TAG"
echo "Downloading $ASSET_NAME..."
curl -fL --retry 3 "${AUTH_HEADER[@]}" -o "$TMP/$ASSET_NAME" "$ASSET_URL"

echo "Extracting..."
EXTRACT_DIR="$TMP/extract"
mkdir -p "$EXTRACT_DIR"

case "$ASSET_NAME" in
  *.tar.zst|*.tzst)
    if ! command -v unzstd >/dev/null 2>&1; then
      echo "Need zstd to extract .tar.zst/.tzst archives (package 'zstd')." >&2
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
    echo "Unknown archive format: $ASSET_NAME" >&2
    exit 1
    ;;
esac

NEW_DIR_SRC="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 3 -type d -name 'files' -prune -o -type f -name 'compatibilitytool.vdf' -printf '%h\n' | head -n1)"
[[ -z "${NEW_DIR_SRC:-}" ]] && { echo "Error: no Proton tool found"; exit 1; }

INSTALL_PATH="$COMPAT_DIR/proton-cachyos-$TAG"

echo "Removing older Proton CachyOS installs..."
find "$COMPAT_DIR" -mindepth 1 -maxdepth 1 -type d -iname 'proton-cachyos-*' -exec rm -rf {} +

echo "Installing to $INSTALL_PATH"
cp -a "$NEW_DIR_SRC" "$INSTALL_PATH"

# --- Overwrite the compatibilitytool.vdf so Steam shows "Proton-CachyOS"
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

# --- Symlink for convenience
ln -sfn "$INSTALL_PATH" "$COMPAT_DIR/proton-cachyos"

echo
echo "✅ Installed Proton-CachyOS ($TAG)"
echo "📁 Path: $INSTALL_PATH"
echo "🔗 Symlink: $COMPAT_DIR/proton-cachyos"
echo
echo "Restart Steam. You’ll see 'Proton-CachyOS' in the Compatibility dropdown."
