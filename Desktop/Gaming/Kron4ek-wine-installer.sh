#!/usr/bin/env bash
# Install latest Wine Staging TkG (amd64) from Kron4ek/Wine-Builds
# Auto-detects Lutris (native/Flatpak), Heroic (native/Flatpak), Bottles (Flatpak)
# Removes older *-staging-tkg-amd64* installs. No renaming or symlinks.
# Source repo: https://github.com/Kron4ek/Wine-Builds

set -euo pipefail

REPO="Kron4ek/Wine-Builds"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# --- do not run as root
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not run as root. Run as your normal user." >&2
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' is required but missing." >&2; exit 1; }; }
need curl
need tar

AUTH_HEADER=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH_HEADER=(-H "Authorization: Bearer $GITHUB_TOKEN")

# --- Paths
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

# Lutris
LUTRIS_NATIVE_CFG="$HOME/.config/lutris"
LUTRIS_NATIVE_RUNNERS="$XDG_DATA_HOME/lutris/runners/wine"
LUTRIS_FLATPAK_CFG="$HOME/.var/app/net.lutris.Lutris/config/lutris"
LUTRIS_FLATPAK_RUNNERS="$HOME/.var/app/net.lutris.Lutris/data/lutris/runners/wine"

# Heroic
HEROIC_NATIVE_CFG="$HOME/.config/heroic"
HEROIC_FLATPAK_CFG="$HOME/.var/app/com.heroicgameslauncher.hgl/config/heroic"
HEROIC_NATIVE_TOOLS="$HEROIC_NATIVE_CFG/tools/wine"
HEROIC_FLATPAK_TOOLS="$HEROIC_FLATPAK_CFG/tools/wine"

# Bottles (Flatpak)
BOTTLES_FLATPAK_CFG="$HOME/.var/app/com.usebottles.bottles/config"
BOTTLES_FLATPAK_RUNNERS="$HOME/.var/app/com.usebottles.bottles/data/bottles/runners"

targets=()
detected=()

add_target() {
  local path="$1" label="$2"
  mkdir -p "$path"
  targets+=("$path")
  detected+=("$label")
}

# --- Detect (be liberal: create runners dir if missing)

# Lutris (native): always prepare runners dir so new users get it
add_target "$LUTRIS_NATIVE_RUNNERS" "Lutris (native)"

# Lutris (Flatpak): add if config or data dir exists (or runner dir exists already)
if [[ -d "$LUTRIS_FLATPAK_CFG" || -d "$LUTRIS_FLATPAK_RUNNERS" ]]; then
  add_target "$LUTRIS_FLATPAK_RUNNERS" "Lutris (Flatpak)"
fi

# Heroic
if [[ -d "$HEROIC_NATIVE_CFG" ]]; then
  add_target "$HEROIC_NATIVE_TOOLS" "Heroic (native)"
fi
if [[ -d "$HEROIC_FLATPAK_CFG" ]]; then
  add_target "$HEROIC_FLATPAK_TOOLS" "Heroic (Flatpak)"
fi

# Bottles (Flatpak)
if [[ -d "$BOTTLES_FLATPAK_CFG" || -d "$BOTTLES_FLATPAK_RUNNERS" ]]; then
  add_target "$BOTTLES_FLATPAK_RUNNERS" "Bottles (Flatpak)"
fi

# --- Optional: force install
[[ "${FORCE_LUTRIS_NATIVE:-}" == "1"      ]] && add_target "$LUTRIS_NATIVE_RUNNERS" "Lutris (native, forced)"
[[ "${FORCE_LUTRIS_FLATPAK:-}" == "1"     ]] && add_target "$LUTRIS_FLATPAK_RUNNERS" "Lutris (Flatpak, forced)"
[[ "${FORCE_BOTTLES_FLATPAK:-}" == "1"    ]] && add_target "$BOTTLES_FLATPAK_RUNNERS" "Bottles (Flatpak, forced)"

if [[ "${#targets[@]}" -eq 0 ]]; then
  echo "No compatible targets detected."
  echo "Tip: launch Lutris, Heroic, or Bottles (Flatpak) once so config dirs exist."
  echo "Or use FORCE_*=1 to force installation."
  exit 1
fi

echo "Detected targets:"
for d in "${detected[@]}"; do echo " - $d"; done
echo "Install paths:"
for t in "${targets[@]}"; do echo " - $t"; done
echo

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Querying latest release..."
JSON="$(curl -fsSL "${AUTH_HEADER[@]}" "$API_URL")"

# --- Select latest Wine Staging TkG amd64 asset
if command -v jq >/dev/null 2>&1; then
  TAG="$(echo "$JSON" | jq -r '.tag_name // empty')"
  mapfile -t CANDIDATES < <(echo "$JSON" | jq -r '.assets[].browser_download_url' \
    | grep -E 'wine-.*-staging-tkg-amd64.*\.tar\.(xz|zst|bz2|gz)$' || true)
  ASSET_URL=""
  for u in "${CANDIDATES[@]}"; do
    if [[ "$u" =~ staging-tkg-amd64 && ! "$u" =~ ntsync ]]; then
      ASSET_URL="$u"; break
    fi
  done
  [[ -z "$ASSET_URL" && ${#CANDIDATES[@]} -gt 0 ]] && ASSET_URL="${CANDIDATES[0]}"
  ASSET_NAME="$(basename "${ASSET_URL:-}")"
else
  readarray -t parsed < <(
    echo "$JSON" | python3 - <<'PY'
import sys, json, re
data=json.load(sys.stdin)
tag=data.get("tag_name","")
assets=[a.get("browser_download_url","") for a in data.get("assets",[])]
rx=re.compile(r'wine-.*-staging-tkg-amd64.*\.tar\.(?:xz|zst|bz2|gz)$', re.I)
cands=[u for u in assets if rx.search(u)]
sel=""
for u in cands:
    if "ntsync" not in u:
        sel=u; break
if not sel and cands:
    sel=cands[0]
print(tag)
print(sel)
PY
  )
  TAG="${parsed[0]:-}"
  ASSET_URL="${parsed[1]:-}"
  ASSET_NAME="$(basename "${ASSET_URL:-}")"
fi

if [[ -z "${ASSET_URL:-}" ]]; then
  echo "Error: no Wine Staging TkG amd64 asset found in latest release"
  exit 1
fi

echo "Latest release tag: $TAG"
echo "Downloading $ASSET_NAME..."
curl -fL --retry 3 "${AUTH_HEADER[@]}" -o "$TMP/$ASSET_NAME" "$ASSET_URL"

echo "Extracting..."
EXTRACT_DIR="$TMP/extract"
mkdir -p "$EXTRACT_DIR"

case "$ASSET_NAME" in
  *.tar.zst|*.tzst)
    if command -v unzstd >/dev/null; then
      tar --use-compress-program=unzstd -xf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    elif command -v zstd >/dev/null; then
      tar --use-compress-program='zstd -d --stdout' -xf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    else
      echo "Need zstd/unzstd to extract .tar.zst"; exit 1
    fi
    ;;
  *.tar.xz)  tar -xJf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *.tar.gz|*.tgz) tar -xzf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *.tar.bz2) tar -xjf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *) echo "Unknown archive format: $ASSET_NAME"; exit 1 ;;
esac

NEW_DIR_SRC="$(find "$EXTRACT_DIR" -type f -path '*/bin/wine' -printf '%h\n' -quit | sed 's#/bin$##')"
if [[ -z "$NEW_DIR_SRC" ]]; then
  echo "Error: no Wine directory found in archive"
  exit 1
fi

BASENAME="$(basename "$NEW_DIR_SRC")"
[[ -z "$BASENAME" ]] && BASENAME="wine-${TAG}-staging-tkg-amd64"

echo "Preparing to install: $BASENAME"

for dest in "${targets[@]}"; do
  INSTALL_PATH="$dest/$BASENAME"
  echo "Removing older Wine Staging TkG amd64 installs in: $dest"
  find "$dest" -mindepth 1 -maxdepth 1 -type d \
    \( -iname 'wine-*-staging-tkg-amd64*' -o -iname 'wine-*-tkg-staging-amd64*' \) \
    ! -path "$INSTALL_PATH" -exec rm -rf {} + 2>/dev/null || true

  echo "Installing to $INSTALL_PATH"
  rm -rf "$INSTALL_PATH"
  cp -a "$NEW_DIR_SRC" "$INSTALL_PATH"
done

echo
echo "Installed Wine Staging TkG (amd64) to:"
for dest in "${targets[@]}"; do
  echo " - $dest/$BASENAME"
done
echo
echo "No renaming or symlinks were created."
