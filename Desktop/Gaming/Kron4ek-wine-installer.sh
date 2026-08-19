#!/usr/bin/env bash
# Install latest Wine Staging TkG (amd64) from Kron4ek/Wine-Builds
# Auto-detects Lutris (native/Flatpak), Heroic (native/Flatpak), Bottles (Flatpak)
# Removes older *-staging-tkg-amd64* installs. No renaming or symlinks.
# Source repo: https://github.com/Kron4ek/Wine-Builds

set -euo pipefail

# --- Theme / colors ---------------------------------------------------------
# Same Nord palette as X-Linuxtool.sh, anchored on Polar Night #2e3440
# (base/border) and Aurora Red #bf616a (accent/selection).
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

REPO="Kron4ek/Wine-Builds"
API_URL="https://api.github.com/repos/${REPO}/releases/latest"

# --- do not run as root
if [[ "$(id -u)" -eq 0 ]]; then
  ui_err "Do not run as root. Run as your normal user."
  exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { ui_err "'$1' is required but missing."; exit 1; }; }
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
  ui_err "No compatible targets detected."
  ui_info "Tip: launch Lutris, Heroic, or Bottles (Flatpak) once so config dirs exist."
  ui_info "Or use FORCE_*=1 to force installation."
  exit 1
fi

ui_info "Detected targets:"
for d in "${detected[@]}"; do echo " - $d"; done
ui_info "Install paths:"
for t in "${targets[@]}"; do echo " - $t"; done
echo

ui_step "Querying latest release..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

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
  ui_err "no Wine Staging TkG amd64 asset found in latest release"
  exit 1
fi

ui_info "Latest release tag: $TAG"
ui_info "Downloading $ASSET_NAME..."
curl -fL --retry 3 "${AUTH_HEADER[@]}" -o "$TMP/$ASSET_NAME" "$ASSET_URL"

ui_info "Extracting..."
EXTRACT_DIR="$TMP/extract"
mkdir -p "$EXTRACT_DIR"

case "$ASSET_NAME" in
  *.tar.zst|*.tzst)
    if command -v unzstd >/dev/null; then
      tar --use-compress-program=unzstd -xf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    elif command -v zstd >/dev/null; then
      tar --use-compress-program='zstd -d --stdout' -xf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR"
    else
      ui_err "Need zstd/unzstd to extract .tar.zst"; exit 1
    fi
    ;;
  *.tar.xz)  tar -xJf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *.tar.gz|*.tgz) tar -xzf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *.tar.bz2) tar -xjf "$TMP/$ASSET_NAME" -C "$EXTRACT_DIR" ;;
  *) ui_err "Unknown archive format: $ASSET_NAME"; exit 1 ;;
esac

NEW_DIR_SRC="$(find "$EXTRACT_DIR" -type f -path '*/bin/wine' -printf '%h\n' -quit | sed 's#/bin$##')"
if [[ -z "$NEW_DIR_SRC" ]]; then
  ui_err "no Wine directory found in archive"
  exit 1
fi

BASENAME="$(basename "$NEW_DIR_SRC")"
[[ -z "$BASENAME" ]] && BASENAME="wine-${TAG}-staging-tkg-amd64"

ui_step "Preparing to install: $BASENAME"

for dest in "${targets[@]}"; do
  INSTALL_PATH="$dest/$BASENAME"
  ui_info "Removing older Wine Staging TkG amd64 installs in: $dest"
  find "$dest" -mindepth 1 -maxdepth 1 -type d \
    \( -iname 'wine-*-staging-tkg-amd64*' -o -iname 'wine-*-tkg-staging-amd64*' \) \
    ! -path "$INSTALL_PATH" -exec rm -rf {} + 2>/dev/null || true

  ui_info "Installing to $INSTALL_PATH"
  rm -rf "$INSTALL_PATH"
  cp -a "$NEW_DIR_SRC" "$INSTALL_PATH"
done

echo
ui_ok "Installed Wine Staging TkG (amd64) to:"
for dest in "${targets[@]}"; do
  echo " - $dest/$BASENAME"
done
echo
ui_info "No renaming or symlinks were created."
