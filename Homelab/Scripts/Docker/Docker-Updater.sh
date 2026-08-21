#!/usr/bin/env bash

set -uo pipefail

# Priority: CLI arg > COMPOSE_ROOT env > this value > auto-detected <home>/<COMPOSE_SUBDIR>, else prompted.
COMPOSE_ROOT=""
COMPOSE_SUBDIR="docker"

if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  case "${TERM:-}" in
    linux|screen|screen-*|tmux-*)
      C_GREY=$'\e[38;5;244m'     # nord3  4c566a
      C_FG=$'\e[38;5;253m'       # nord4  d8dee9
      C_CYAN=$'\e[38;5;116m'     # nord8  88c0d0
      C_BLUE=$'\e[38;5;110m'     # nord9  81a1c1
      C_RED=$'\e[38;5;167m'      # nord11 bf616a
      C_YELLOW=$'\e[38;5;222m'   # nord13 ebcb8b
      C_GREEN=$'\e[38;5;150m'    # nord14 a3be8c
      C_MAGENTA=$'\e[38;5;139m'  # nord15 b48ead
      C_ACCENT=$'\e[38;5;167m'   # nord11 bf616a
      BG_ACCENT=$'\e[48;5;167m'  # nord11 bf616a
      FG_ONACCENT=$'\e[38;5;236m' # nord0  2e3440
      ;;
    *)
      C_GREY=$'\e[38;2;76;86;106m'      # nord3  4c566a
      C_FG=$'\e[38;2;216;222;233m'      # nord4  d8dee9
      C_CYAN=$'\e[38;2;136;192;208m'    # nord8  88c0d0
      C_BLUE=$'\e[38;2;129;161;193m'    # nord9  81a1c1
      C_RED=$'\e[38;2;191;97;106m'      # nord11 bf616a
      C_YELLOW=$'\e[38;2;235;203;139m'  # nord13 ebcb8b
      C_GREEN=$'\e[38;2;163;190;140m'   # nord14 a3be8c
      C_MAGENTA=$'\e[38;2;180;142;173m' # nord15 b48ead
      C_ACCENT=$'\e[38;2;191;97;106m'   # nord11 bf616a
      BG_ACCENT=$'\e[48;2;191;97;106m'  # nord11 bf616a
      FG_ONACCENT=$'\e[38;2;46;52;64m'  # nord0  2e3440
      ;;
  esac
else
  C_RESET="" C_BOLD="" C_DIM="" C_GREY="" C_FG=""
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN="" C_MAGENTA="" C_ACCENT=""
  BG_ACCENT="" FG_ONACCENT=""
fi

CHECK="${C_GREEN}✔${C_RESET}"
CROSS="${C_RED}✘${C_RESET}"
BOX_ON="${C_GREEN}[x]${C_RESET}"
BOX_OFF="${C_DIM}[ ]${C_RESET}"

ui_info()  { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()    { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()  { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()   { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()  { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }
ui_rule()  { printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM$C_GREY" "$C_RESET"; }
die()      { ui_err "$*"; exit 1; }
have()     { command -v "$1" >/dev/null 2>&1; }

abspath() {
  if have realpath; then realpath -m "$1" 2>/dev/null
  else readlink -f "$1" 2>/dev/null || echo "$1"; fi
}

pad_trunc() {
  local s="$1" n="$2" len pad
  len=${#s}
  if (( len > n )); then
    s="${s:0:n-1}…"; len=$n
  fi
  pad=$(( n - len )); (( pad < 0 )) && pad=0
  printf '%s%*s' "$s" "$pad" ''
}

user_home() {
  # Nested sudo (e.g. from X27-Homelab.sh) resets SUDO_USER to "root", so
  # loginuid is tried first (mirrors Docker-Install.sh).
  local candidate=""

  local login_uid
  login_uid="$(cat /proc/self/loginuid 2>/dev/null || true)"
  if [[ -n "$login_uid" && "$login_uid" != "4294967295" && "$login_uid" != "0" ]]; then
    candidate="$(id -un "$login_uid" 2>/dev/null || true)"
  fi

  if [[ -z "$candidate" ]] && have logname; then
    local ln; ln="$(logname 2>/dev/null || true)"
    [[ -n "$ln" && "$ln" != "root" ]] && candidate="$ln"
  fi

  if [[ -z "$candidate" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    candidate="$SUDO_USER"
  fi

  if [[ -z "$candidate" && -n "${USER:-}" && "$USER" != "root" ]]; then
    candidate="$USER"
  fi

  if [[ -n "$candidate" ]]; then
    local h; h=$(getent passwd "$candidate" 2>/dev/null | cut -d: -f6)
    [[ -n "$h" ]] && { printf '%s' "$h"; return; }
  fi

  printf '%s' "${HOME:-/root}"
}

COMPOSE_CMD=()
detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif have docker-compose; then
    COMPOSE_CMD=(docker-compose)
  else
    COMPOSE_CMD=()
  fi
}

require_deps() {
  have docker || die "docker is not installed or not in PATH."
  docker info >/dev/null 2>&1 || \
    die "Cannot talk to the Docker daemon. Are you in the 'docker' group / is the daemon running?"
  detect_compose
}

compose_images() {
  local file="$1"
  [[ ${#COMPOSE_CMD[@]} -gt 0 ]] || return 0
  "${COMPOSE_CMD[@]}" -f "$file" config --images 2>/dev/null | sed '/^$/d'
}

container_label() {
  local name="$1" label="$2" val
  val=$(docker inspect -f "{{index .Config.Labels \"$label\"}}" "$name" 2>/dev/null)
  [[ "$val" == "<no value>" ]] && val=""
  printf '%s' "$val"
}

local_digest() {
  docker image inspect "$1" --format '{{range .RepoDigests}}{{println .}}{{end}}' 2>/dev/null \
    | sed -n 's/.*@//p' | head -n1
}

remote_digest() {
  local image="$1" d=""
  if docker buildx version >/dev/null 2>&1; then
    d=$(docker buildx imagetools inspect "$image" --format '{{.Manifest.Digest}}' 2>/dev/null) || d=""
    [[ -n "$d" ]] && { printf '%s\n' "$d"; return 0; }
  fi
  if have skopeo; then
    d=$(skopeo inspect --format '{{.Digest}}' "docker://$image" 2>/dev/null) || d=""
    [[ -n "$d" ]] && { printf '%s\n' "$d"; return 0; }
  fi
  d=$(docker manifest inspect "$image" 2>/dev/null | grep -m1 -oE 'sha256:[0-9a-f]{64}') || d=""
  [[ -n "$d" ]] && { printf '%s\n' "$d"; return 0; }
  return 1
}

declare -a U_IMAGE=()     # image reference
declare -a U_CAT=()       # compose | compose-ext | external | standalone
declare -a U_FILE=()      # compose file (compose/compose-ext) else ""
declare -a U_CONTAINER=() # container name (running containers) else ""
declare -a U_STATE=()     # update | new
declare -a U_SEL=()       # 1 = selected, 0 = ignored

declare -A CHK_CACHE=()    # image -> state
declare -A CAND_SEEN=()    # dedupe key -> 1
declare -A SCANNED_FILES=() # abs path -> 1

declare -a CT_NAME=() CT_IMAGE=() CT_PROJ=() CT_CFG=()
declare -A CN_BY_KEY=()    # "<absfile>|<image>" -> container name
declare -A CN_BY_IMAGE=()  # image -> container name (fallback)

CAT_ORDER=(compose compose-ext external standalone)

cat_label() {
  case "$1" in
    compose)     printf '%s' "Compose files (scanned directory)" ;;
    compose-ext) printf '%s' "Compose (other files on this host)" ;;
    external)    printf '%s' "External / Portainer-managed stacks" ;;
    standalone)  printf '%s' "Standalone containers (docker run)" ;;
    *)           printf '%s' "$1" ;;
  esac
}

classify_state() {
  local image="$1"
  if [[ -n "${CHK_CACHE[$image]:-}" ]]; then printf '%s' "${CHK_CACHE[$image]}"; return; fi
  local ld rd state
  ld=$(local_digest "$image")
  if ! rd=$(remote_digest "$image"); then state="unreachable"
  elif [[ -z "$ld" ]]; then state="new"
  elif [[ "$ld" != "$rd" ]]; then state="update"
  else state="uptodate"; fi
  CHK_CACHE[$image]="$state"
  printf '%s' "$state"
}

SPIN='|/-\'; SI=0
add_candidate() {
  local image="$1" cat="$2" file="$3" container="$4"
  [[ -z "$image" || "$image" == sha256:* ]] && return 0

  local key="$cat|$file|$image|$container"
  [[ -n "${CAND_SEEN[$key]:-}" ]] && return 0
  CAND_SEEN[$key]=1

  local label="${container:-$image}"
  printf '  %s%s%s checking %s ...' "$C_DIM" "${SPIN:SI++%${#SPIN}:1}" "$C_RESET" "$label"

  local st; st=$(classify_state "$image")
  case "$st" in
    update)
      printf '\r\e[2K  %b %s  %supdate available%s\n' "$CHECK" "$label" "$C_GREEN" "$C_RESET"
      U_IMAGE+=("$image"); U_CAT+=("$cat"); U_FILE+=("$file"); U_CONTAINER+=("$container")
      U_STATE+=("update"); U_SEL+=("1") ;;
    new)
      printf '\r\e[2K  %b %s  %snot pulled yet%s\n' "$CHECK" "$label" "$C_YELLOW" "$C_RESET"
      U_IMAGE+=("$image"); U_CAT+=("$cat"); U_FILE+=("$file"); U_CONTAINER+=("$container")
      U_STATE+=("new"); U_SEL+=("1") ;;
    unreachable)
      printf '\r\e[2K  %b %s  %s(registry unreachable, skipped)%s\n' "$CROSS" "$label" "$C_DIM" "$C_RESET" ;;
    *)
      printf '\r\e[2K  %b %s  %sup to date%s\n' "$CHECK" "$label" "$C_DIM" "$C_RESET" ;;
  esac
}

build_container_index() {
  local -a names=()
  mapfile -t names < <(docker ps --format '{{.Names}}' 2>/dev/null | sort)
  [[ ${#names[@]} -gt 0 ]] || return 0

  local name image proj cfg first abs
  for name in "${names[@]}"; do
    image=$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null) || continue
    proj=$(container_label "$name" "com.docker.compose.project")
    cfg=$(container_label "$name" "com.docker.compose.project.config_files")

    CT_NAME+=("$name"); CT_IMAGE+=("$image"); CT_PROJ+=("$proj"); CT_CFG+=("$cfg")

    if [[ -n "$proj" ]]; then
      first="${cfg%%,*}"
      if [[ -n "$first" ]]; then
        abs=$(abspath "$first")
        CN_BY_KEY["$abs|$image"]="$name"
      fi
    fi
    CN_BY_IMAGE["$image"]="$name"
  done
}

lookup_container() {
  local abs="$1" image="$2"
  if [[ -n "${CN_BY_KEY["$abs|$image"]:-}" ]]; then printf '%s' "${CN_BY_KEY["$abs|$image"]}"; return; fi
  printf '%s' "${CN_BY_IMAGE["$image"]:-}"
}

collect_compose() {
  local root="$1"
  local -a files=()
  mapfile -t files < <(
    find "$root" -type f \
      \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \
         -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null | sort
  )

  if [[ ${#files[@]} -eq 0 ]]; then
    ui_warn "No docker-compose.yml / compose.yml files found under: $root"
    return 0
  fi
  if [[ ${#COMPOSE_CMD[@]} -eq 0 ]]; then
    ui_warn "Found compose files but no 'docker compose' binary; skipping compose scan."
    return 0
  fi

  ui_info "Scanning ${C_BOLD}${#files[@]}${C_RESET} compose file(s) under ${C_BOLD}$root${C_RESET}"
  local file image abs
  for file in "${files[@]}"; do
    abs=$(abspath "$file"); SCANNED_FILES[$abs]=1
    echo "${C_BLUE}›${C_RESET} ${C_BOLD}$file${C_RESET}"
    local -a imgs=(); mapfile -t imgs < <(compose_images "$file")
    if [[ ${#imgs[@]} -eq 0 ]]; then
      echo "  ${C_DIM}(no resolvable images)${C_RESET}"; continue
    fi
    for image in "${imgs[@]}"; do
      add_candidate "$image" "compose" "$abs" ""
    done
  done
  echo
}

collect_containers() {
  [[ ${#CT_NAME[@]} -gt 0 ]] || return 0

  ui_info "Inspecting ${C_BOLD}${#CT_NAME[@]}${C_RESET} running container(s) deployed on this host"
  local i name image proj cfg first abs
  for i in "${!CT_NAME[@]}"; do
    name="${CT_NAME[$i]}"; image="${CT_IMAGE[$i]}"
    proj="${CT_PROJ[$i]}"; cfg="${CT_CFG[$i]}"

    if [[ -n "$proj" ]]; then
      first="${cfg%%,*}"
      if [[ -n "$first" && -r "$first" ]]; then
        abs=$(abspath "$first")
        if [[ -n "${SCANNED_FILES[$abs]:-}" ]]; then
          continue   # already covered by the directory scan
        fi
        add_candidate "$image" "compose-ext" "$abs" "$name"
      else
        # compose-labelled but unreachable here, typical of Portainer stacks.
        add_candidate "$image" "external" "" "$name"
      fi
    else
      add_candidate "$image" "standalone" "" "$name"
    fi
  done
  echo
}

reorder_by_category() {
  local -a I=() C=() F=() N=() S=() L=()
  local cat i
  for cat in "${CAT_ORDER[@]}"; do
    for i in "${!U_IMAGE[@]}"; do
      [[ "${U_CAT[$i]}" == "$cat" ]] || continue
      I+=("${U_IMAGE[$i]}"); C+=("${U_CAT[$i]}"); F+=("${U_FILE[$i]}")
      N+=("${U_CONTAINER[$i]}"); S+=("${U_STATE[$i]}"); L+=("${U_SEL[$i]}")
    done
  done
  U_IMAGE=("${I[@]}"); U_CAT=("${C[@]}"); U_FILE=("${F[@]}")
  U_CONTAINER=("${N[@]}"); U_STATE=("${S[@]}"); U_SEL=("${L[@]}")
}

cursor_hide() { [[ -t 1 ]] && printf '\e[?25l'; }
cursor_show() { [[ -t 1 ]] && printf '\e[?25h'; }

on_interrupt() {
  cursor_show
  printf '\n'
  ui_warn "Interrupted (Ctrl+C) — aborting. No further changes will be made." >&2
  exit 130
}
trap on_interrupt INT TERM
trap cursor_show EXIT

draw_menu() {
  local cursor="$1"
  local NAME_W=22 IMG_W=40 SRC_W=14
  clear
  echo "${C_GREY}${C_BOLD}╔════════════════════════════════════════════════════════════════════════╗${C_RESET}"
  echo "${C_GREY}${C_BOLD}║${C_RESET}  ${C_ACCENT}${C_BOLD}Docker Updater${C_RESET}  ${C_DIM}${C_GREY}— choose which images to update${C_RESET}                        ${C_GREY}${C_BOLD}║${C_RESET}"
  echo "${C_GREY}${C_BOLD}╚════════════════════════════════════════════════════════════════════════╝${C_RESET}"
  echo
  echo "  ${C_ACCENT}${C_BOLD}↑/↓${C_RESET} move    ${C_ACCENT}${C_BOLD}Space${C_RESET} toggle    ${C_ACCENT}${C_BOLD}a${C_RESET} all    ${C_GREEN}${C_BOLD}Enter${C_RESET} update    ${C_ACCENT}${C_BOLD}q / Ctrl+C${C_RESET} quit"

  local count=0 i
  for i in "${!U_IMAGE[@]}"; do [[ "${U_SEL[$i]}" == "1" ]] && ((count++)); done

  echo
  printf '    %-4s %-8s %-*s %-*s %s\n' "SEL" "STATE" "$NAME_W" "CONTAINER" "$IMG_W" "IMAGE" "SOURCE"
  printf '    %s\n' "${C_DIM}${C_GREY}────────────────────────────────────────────────────────────────────────────────${C_RESET}"

  local last_cat=""
  for i in "${!U_IMAGE[@]}"; do
    if [[ "${U_CAT[$i]}" != "$last_cat" ]]; then
      last_cat="${U_CAT[$i]}"
      local cnt=0 j
      for j in "${!U_CAT[@]}"; do [[ "${U_CAT[$j]}" == "$last_cat" ]] && ((cnt++)); done
      echo
      echo "  ${C_BOLD}${C_BLUE}$(cat_label "$last_cat")${C_RESET} ${C_DIM}(${cnt})${C_RESET}"
    fi

    local cb_str state_str name_str img_str src_str name src
    if [[ "${U_SEL[$i]}" == "1" ]]; then cb_str="${C_GREEN}[x]${C_RESET}"; else cb_str="${C_DIM}[ ]${C_RESET}"; fi
    if [[ "${U_STATE[$i]}" == "new" ]]; then
      state_str="${C_YELLOW}$(printf '%-8s' 'new')${C_RESET}"
    else
      state_str="${C_GREEN}$(printf '%-8s' 'update')${C_RESET}"
    fi

    name="${U_CONTAINER[$i]:--}"
    if [[ -n "${U_FILE[$i]}" ]]; then src="${U_FILE[$i]##*/}"; else src="-"; fi

    name_str=$(pad_trunc "$name" "$NAME_W")
    img_str=$(pad_trunc "${U_IMAGE[$i]}" "$IMG_W")
    src_str=$(pad_trunc "$src" "$SRC_W")

    if [[ "$i" -eq "$cursor" ]]; then
      local cb_txt sel_txt
      [[ "${U_SEL[$i]}" == "1" ]] && cb_txt="[x]" || cb_txt="[ ]"
      if [[ "${U_STATE[$i]}" == "new" ]]; then sel_txt=$(printf '%-8s' 'new')
      else sel_txt=$(printf '%-8s' 'update'); fi
      printf '  %s❯ %s %s  %s %s  %s%s\n' \
        "$BG_ACCENT$FG_ONACCENT$C_BOLD" "$cb_txt" "$sel_txt" "$name_str" "$img_str" "$src_str" "$C_RESET"
    else
      printf '    %b %b  %b%b%b %s  %b\n' \
        "$cb_str" "$state_str" "${C_CYAN}" "$name_str" "$C_RESET" "$img_str" "${C_DIM}${src_str}${C_RESET}"
    fi
  done

  echo
  printf '  %bupdate%b = newer image available    %bnew%b = not pulled yet\n' "$C_GREEN" "$C_RESET" "$C_YELLOW" "$C_RESET"
  echo "  ${C_BOLD}${C_GREEN}${count}${C_RESET} of ${C_BOLD}${#U_IMAGE[@]}${C_RESET} image(s) selected for update"
}

select_images() {
  local cursor=0 key key2 n="${#U_IMAGE[@]}"
  cursor_hide
  while true; do
    draw_menu "$cursor"
    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\x1b')
        read -rsn2 -t 0.0005 key2 || key2=""
        case "$key2" in
          '[A') ((cursor = (cursor - 1 + n) % n)) ;;
          '[B') ((cursor = (cursor + 1) % n)) ;;
          '')   cursor_show; return 1 ;;
        esac ;;
      'k') ((cursor = (cursor - 1 + n) % n)) ;;
      'j') ((cursor = (cursor + 1) % n)) ;;
      ' ') [[ "${U_SEL[$cursor]}" == "1" ]] && U_SEL[$cursor]=0 || U_SEL[$cursor]=1 ;;
      'a')
        local all=1 i
        for i in "${!U_SEL[@]}"; do [[ "${U_SEL[$i]}" == "1" ]] || { all=0; break; }; done
        for i in "${!U_SEL[@]}"; do [[ "$all" -eq 1 ]] && U_SEL[$i]=0 || U_SEL[$i]=1; done ;;
      'q') cursor_show; return 1 ;;
      '')  cursor_show; return 0 ;;
    esac
  done
}

ensure_runlike() {
  docker image inspect assaflavie/runlike >/dev/null 2>&1 && return 0
  ui_info "Pulling helper image assaflavie/runlike (used to rebuild the run command)"
  docker pull assaflavie/runlike >/dev/null 2>&1
}

recreate_standalone() {
  local name="$1" cmd ts backup
  cmd=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock assaflavie/runlike "$name" 2>/dev/null)
  if [[ "$cmd" != docker\ run* ]]; then
    ui_warn "Could not rebuild run command for '$name'; image pulled, recreate it manually."
    return 1
  fi

  ts=$(date +%s); backup="${name}__old_${ts}"
  docker stop "$name" >/dev/null 2>&1 || true
  docker rename "$name" "$backup" >/dev/null 2>&1 || { ui_warn "Could not back up '$name'."; return 1; }

  if eval "$cmd" >/dev/null 2>&1; then
    ui_ok "Recreated '$name' on the new image."
    docker rm "$backup" >/dev/null 2>&1 || true
    return 0
  fi

  ui_warn "Recreate failed for '$name'; restoring the previous container."
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker rename "$backup" "$name" >/dev/null 2>&1 || true
  docker start "$name" >/dev/null 2>&1 || true
  return 1
}

apply_updates() {
  local -a sel=()
  local i
  for i in "${!U_IMAGE[@]}"; do [[ "${U_SEL[$i]}" == "1" ]] && sel+=("$i"); done
  if [[ ${#sel[@]} -eq 0 ]]; then ui_warn "Nothing selected. No changes made."; return 0; fi

  clear
  ui_step "The following images will be updated:"
  echo
  local last_cat=""
  for i in "${sel[@]}"; do
    if [[ "${U_CAT[$i]}" != "$last_cat" ]]; then
      last_cat="${U_CAT[$i]}"; echo "  ${C_BOLD}${C_BLUE}$(cat_label "$last_cat")${C_RESET}"
    fi
    local origin="${U_CONTAINER[$i]:-${U_FILE[$i]}}"
    echo "    ${CHECK} ${U_IMAGE[$i]}  ${C_DIM}${origin}${C_RESET}"
  done
  echo
  printf '%s  ❯%s Proceed? %s[y/N]%s ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET"
  read -r ans
  [[ "${ans,,}" == "y" ]] || { ui_warn "Aborted by user."; return 0; }
  echo

  local -A pulled=()
  for i in "${sel[@]}"; do
    [[ -n "${pulled[${U_IMAGE[$i]}]:-}" ]] && continue
    pulled[${U_IMAGE[$i]}]=1
    ui_info "Pulling ${C_BOLD}${U_IMAGE[$i]}${C_RESET}"
    docker pull "${U_IMAGE[$i]}" || ui_warn "Failed to pull ${U_IMAGE[$i]}"
  done
  echo

  local -A files=()
  for i in "${sel[@]}"; do
    case "${U_CAT[$i]}" in compose|compose-ext) [[ -n "${U_FILE[$i]}" ]] && files["${U_FILE[$i]}"]=1 ;; esac
  done
  local f
  for f in "${!files[@]}"; do
    ui_info "Recreating affected services from ${C_BOLD}$f${C_RESET}"
    "${COMPOSE_CMD[@]}" -f "$f" up -d && ui_ok "Updated services in $f" || ui_warn "compose up failed for $f"
  done

  local -a ext=()
  for i in "${sel[@]}"; do [[ "${U_CAT[$i]}" == "external" ]] && ext+=("$i"); done
  if [[ ${#ext[@]} -gt 0 ]]; then
    echo
    ui_warn "External / Portainer-managed stacks — new images pulled, but they must be"
    ui_warn "redeployed in their manager to take effect (Portainer: 'Re-pull & redeploy'):"
    for i in "${ext[@]}"; do echo "    • ${U_CONTAINER[$i]}  ${C_DIM}(${U_IMAGE[$i]})${C_RESET}"; done
  fi

  local -a standalone=()
  for i in "${sel[@]}"; do [[ "${U_CAT[$i]}" == "standalone" ]] && standalone+=("$i"); done
  if [[ ${#standalone[@]} -gt 0 ]]; then
    echo
    ui_warn "Standalone containers were created with 'docker run'. The new image is pulled,"
    ui_warn "but the container must be recreated to use it."
    printf '%s  ❯%s Recreate %d standalone container(s) now? (best-effort) %s[y/N]%s ' \
      "$C_ACCENT$C_BOLD" "$C_RESET" "${#standalone[@]}" "$C_GREY" "$C_RESET"
    read -r rec
    if [[ "${rec,,}" == "y" ]]; then
      if ensure_runlike; then
        for i in "${standalone[@]}"; do
          ui_info "Recreating ${C_BOLD}${U_CONTAINER[$i]}${C_RESET}"
          recreate_standalone "${U_CONTAINER[$i]}"
        done
      else
        ui_warn "Could not obtain the runlike helper; recreate the containers manually."
      fi
    else
      echo "  ${C_DIM}Left as-is. Recreate them yourself to apply the new image.${C_RESET}"
    fi
  fi

  echo
  printf '%s  ❯%s Remove old dangling images to reclaim space? %s[y/N]%s ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET"
  read -r prune
  if [[ "${prune,,}" == "y" ]]; then
    docker image prune -f >/dev/null && ui_ok "Pruned dangling images."
  fi
  echo
  ui_ok "Done."
}

main() {
  require_deps

  local root="${1:-${COMPOSE_ROOT:-}}"
  if [[ -z "$root" ]]; then
    root="$(user_home)/${COMPOSE_SUBDIR:-docker}"
    ui_info "Auto-detected compose path: ${C_BOLD}$root${C_RESET}"
  fi
  if [[ -n "$root" && ! -d "$root" ]]; then
    ui_warn "Compose path does not exist: $root"
    root=""
  fi
  if [[ -z "$root" ]]; then
    printf '%s  ❯%s Directory to scan for compose files %s[.]%s: ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY" "$C_RESET"
    read -r root
    root="${root:-.}"
  fi
  root="${root%/}"
  [[ -d "$root" ]] || die "Not a directory: $root"
  ui_info "Using compose path: ${C_BOLD}$root${C_RESET}"

  build_container_index
  collect_compose "$root"
  collect_containers

  if [[ ${#U_IMAGE[@]} -eq 0 ]]; then
    ui_ok "Everything is already up to date."
    exit 0
  fi

  reorder_by_category

  if select_images; then
    apply_updates
  else
    clear
    ui_warn "Quit — no images were updated."
  fi
}

main "$@"
