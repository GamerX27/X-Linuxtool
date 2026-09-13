#!/bin/bash

# curl | bash consumes stdin, so interactive reads use $INPUT (/dev/tty) instead.
if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

# OUTPUT forces a real tty so dnf's progress bar renders through the whole dispatch chain.
if [ -w /dev/tty ]; then
    OUTPUT=/dev/tty
else
    OUTPUT=/dev/stdout
fi

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
    C_CYAN=$'\033[36m'
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

# Dash pool sliced down to CONTENT_W each redraw (90 = widest terminal we scale for).
printf -v DASH_POOL '─%.0s' {1..90}

calc_margin() {
    MARGIN="" CONTENT_W=44 RULE_DASH="${DASH_POOL:0:44}"
    [ -t 1 ] || return
    local cols
    cols="$(tput cols 2>/dev/null)"
    [ -z "$cols" ] && cols="${COLUMNS:-80}"
    CONTENT_W=$(( cols * 40 / 100 ))
    [ "$CONTENT_W" -lt 44 ] && CONTENT_W=44
    [ "$CONTENT_W" -gt 90 ] && CONTENT_W=90
    RULE_DASH="${DASH_POOL:0:$CONTENT_W}"
    local pad=$(( (cols - CONTENT_W) / 2 ))
    [ "$pad" -lt 0 ] && pad=0
    printf -v MARGIN '%*s' "$pad" ''
}

ui_banner() {
    calc_margin
    printf '\n%s%s%sX 2 7   T O O L B O X%s\n' "$MARGIN" "$C_BOLD" "$C_CYAN" "$C_RESET"
    printf '%s%sLinux desktop · homelab · gaming%s\n\n' "$MARGIN" "$C_DIM" "$C_RESET"
}

ui_rule()    { calc_margin; printf '%s%s%s%s\n' "$MARGIN" "$C_DIM" "$RULE_DASH" "$C_RESET"; }
ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step() {
    calc_margin
    printf '\n%s%s%s%s%s\n' "$MARGIN" "$C_BOLD" "$C_RED" "$1" "$C_RESET"
    printf '%s%s%s%s\n' "$MARGIN" "$C_DIM" "$RULE_DASH" "$C_RESET"
}

ui_menu_item() {
    calc_margin
    printf '%s   %s%s)%s %s\n' "$MARGIN" "$C_BOLD" "$1" "$C_RESET" "$2"
}

ui_pick() {
    # ui_pick <title> <item...>; $'\x01'-prefixed items start a category. Sets PICK_INDEX, returns 0/1/2 (pick/cancel/no-tty).
    local title="$1"
    shift
    local -a raw=("$@")
    local -a item_raw_idx=()
    local -A k_of_raw=()
    local -a cat_names=()
    local -A cat_of_k=()
    local i cur_cat=-1

    if [ "$INPUT" != "/dev/tty" ]; then
        return 2
    fi

    for i in "${!raw[@]}"; do
        if [[ "${raw[$i]}" == $'\x01'* ]]; then
            cat_names+=("${raw[$i]#$'\x01'}")
            cur_cat=$((${#cat_names[@]} - 1))
        else
            k_of_raw[$i]=${#item_raw_idx[@]}
            item_raw_idx+=("$i")
            cat_of_k[${k_of_raw[$i]}]=$cur_cat
        fi
    done
    local has_categories=0
    [ "${#cat_names[@]}" -gt 0 ] && has_categories=1

    local old_stty
    old_stty="$( { stty -g < "$INPUT"; } 2>/dev/null )" || return 2
    { stty -echo -icanon min 1 time 0 < "$INPUT"; } 2>/dev/null
    trap '{ stty "$old_stty" < "$INPUT"; } 2>/dev/null; printf "\n"; exit 130' INT

    local filter="" selected=0 key rest k c needle entry n result=1
    local view="cats"
    [ "$has_categories" -eq 0 ] && view="items"
    local current_cat=0 back_row=0

    local -a nav_labels=() nav_k=() filtered=()

    while true; do
        needle="${filter,,}"
        filtered=()
        for k in "${!item_raw_idx[@]}"; do
            entry="$((k+1))) ${raw[${item_raw_idx[$k]}]}"
            if [ -z "$needle" ] || [[ "${entry,,}" == *"$needle"* ]]; then
                filtered+=("$k")
            fi
        done

        if [ -n "$filter" ]; then
            view="search"
        elif [ "$view" = "search" ]; then
            view="cats"
            [ "$has_categories" -eq 0 ] && view="items"
        fi

        nav_labels=()
        nav_k=()
        back_row=0
        case "$view" in
            cats)
                for c in "${!cat_names[@]}"; do
                    nav_labels+=("${cat_names[$c]}")
                    nav_k+=(-1)
                done
                ;;
            items)
                if [ "$has_categories" -eq 1 ]; then
                    nav_labels+=("← Back")
                    nav_k+=(-1)
                    back_row=1
                fi
                for k in "${!item_raw_idx[@]}"; do
                    if [ "$has_categories" -eq 0 ] || [ "${cat_of_k[$k]}" -eq "$current_cat" ]; then
                        nav_labels+=("${raw[${item_raw_idx[$k]}]}")
                        nav_k+=("$k")
                    fi
                done
                ;;
            search)
                for k in "${filtered[@]}"; do
                    if [ "$has_categories" -eq 1 ]; then
                        nav_labels+=("${C_DIM}[${cat_names[${cat_of_k[$k]}]}]${C_RESET} ${raw[${item_raw_idx[$k]}]}")
                    else
                        nav_labels+=("${raw[${item_raw_idx[$k]}]}")
                    fi
                    nav_k+=("$k")
                done
                ;;
        esac

        n=${#nav_labels[@]}
        if [ "$n" -eq 0 ]; then
            selected=0
        elif [ "$selected" -ge "$n" ]; then
            selected=$((n - 1))
        fi

        clear 2>/dev/null
        case "$view" in
            cats) ui_step "$title" ;;
            items)
                if [ "$has_categories" -eq 1 ]; then
                    ui_step "${cat_names[$current_cat]}"
                else
                    ui_step "$title"
                fi
                ;;
            search) ui_step "$title — search" ;;
        esac
        printf '%s%s  Search:%s %s\n\n' "$MARGIN" "$C_BOLD" "$C_RESET" "$filter"

        if [ "$n" -eq 0 ]; then
            printf '%s  %s(no matches)%s\n' "$MARGIN" "$C_DIM" "$C_RESET"
        else
            for i in "${!nav_labels[@]}"; do
                if [ "$i" -ne "$selected" ]; then
                    printf '%s    %s\n' "$MARGIN" "${nav_labels[$i]}"
                else
                    # Re-apply the highlight color after any reset embedded
                    # in the label (e.g. a search-view category tag), so the
                    # whole selected row stays blue.
                    printf '%s  %s%s❯ %s%s\n' "$MARGIN" "$C_BOLD" "$C_BLUE" "${nav_labels[$i]//$C_RESET/$C_RESET$C_BOLD$C_BLUE}" "$C_RESET"
                fi
            done
        fi

        printf '\n%s%s  ↑/↓ move · Enter select · Esc back · type to search%s\n' "$MARGIN" "$C_DIM" "$C_RESET"

        IFS= read -rsn1 key < "$INPUT" || { result=1; break; }
        case "$key" in
            $'\x1b')
                rest=""
                IFS= read -rsn2 -t 0.05 rest < "$INPUT"
                case "$rest" in
                    '[A') [ "$n" -gt 0 ] && selected=$(( (selected - 1 + n) % n )) ;;
                    '[B') [ "$n" -gt 0 ] && selected=$(( (selected + 1) % n )) ;;
                    '')
                        if [ -n "$filter" ]; then
                            filter=""
                            selected=0
                        elif [ "$view" = "items" ] && [ "$has_categories" -eq 1 ]; then
                            view="cats"
                            selected=0
                        else
                            result=1
                            break
                        fi
                        ;;
                    *) result=1; break ;;
                esac
                ;;
            ''|$'\n'|$'\r')
                if [ "$n" -eq 0 ]; then
                    :
                elif [ "$view" = "cats" ]; then
                    current_cat=$selected
                    view="items"
                    selected=0
                elif [ "$view" = "items" ] && [ "$back_row" -eq 1 ] && [ "$selected" -eq 0 ]; then
                    view="cats"
                    selected=0
                else
                    PICK_INDEX=${nav_k[$selected]}
                    result=0
                    break
                fi
                ;;
            $'\x7f'|$'\x08')
                filter="${filter%?}"
                selected=0
                ;;
            *)
                filter+="$key"
                selected=0
                ;;
        esac
    done

    { stty "$old_stty" < "$INPUT"; } 2>/dev/null
    trap - INT
    return "$result"
}

# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CB_BASE="https://codeberg.org/X27/X-Linuxtool/raw/branch/main"
GH_BASE="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main"

CB_TOOLBOX="${CB_BASE}/Desktop"
GH_TOOLBOX="${GH_BASE}/Desktop"

CB_TOOLS="${CB_BASE}/Tools"
GH_TOOLS="${GH_BASE}/Tools"

CB_HOMELAB="${CB_BASE}/Homelab"
GH_HOMELAB="${GH_BASE}/Homelab"

CB_YTDLP="https://codeberg.org/X27/YTDLP-Easy-Script/raw/branch/main"
GH_YTDLP="https://raw.githubusercontent.com/GamerX27/YTDLP-Easy-Script/main"

# When run from a local clone (not `curl | bash`), use the scripts already on
# disk instead of re-downloading them. Exported so the sub-scripts we spawn
# below (which run from /tmp and can't find local files via their own path)
# know where the clone lives too.
LOCAL_ROOT=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    [ -d "$LOCAL_ROOT/Desktop" ] && [ -d "$LOCAL_ROOT/Homelab" ] || LOCAL_ROOT=""
fi
export X27_LOCAL_ROOT="$LOCAL_ROOT"

_download() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$1" -o "$2"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        ui_err "Neither curl nor wget is available."
        return 1
    fi
}

fetch_file() {
    local cb="$1" gh="$2" out="$3" local_rel="$4"

    if [ -n "$LOCAL_ROOT" ] && [ -n "$local_rel" ] && [ -f "$LOCAL_ROOT/$local_rel" ]; then
        ui_info "Using local copy: ${local_rel}" >&2
        cp "$LOCAL_ROOT/$local_rel" "$out"
        return 0
    fi

    ui_info "Fetching from Codeberg…" >&2
    if _download "$cb" "$out"; then
        ui_ok "Downloaded from Codeberg." >&2
        return 0
    fi

    ui_warn "Codeberg unreachable; falling back to GitHub mirror…" >&2
    if _download "$gh" "$out"; then
        ui_ok "Downloaded from GitHub mirror." >&2
        return 0
    fi

    ui_err "Could not download from Codeberg or GitHub."
    return 1
}

check_and_install_dependencies() {
    local dependencies=("wget" "git" "curl")
    local pkg_manager=""

    if command -v apt &> /dev/null; then
        pkg_manager="apt"
    elif command -v dnf &> /dev/null; then
        pkg_manager="dnf"
    fi

    if [ -z "$pkg_manager" ]; then
        ui_warn "Unsupported package manager. Ensure wget, git, and curl are installed manually."
        return 0
    fi

    ui_step "Checking dependencies"
    ui_info "Required: ${dependencies[*]}"
    local missing_deps=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        ui_warn "Missing: ${missing_deps[*]} — installing via $pkg_manager…"
        sudo $pkg_manager install -y "${missing_deps[@]}"
        if [ $? -eq 0 ]; then
            ui_ok "Dependencies installed successfully."
        else
            ui_err "Failed to install dependencies. Please install them manually."
            exit 1
        fi
    else
        ui_ok "All dependencies are already installed."
    fi
}

say_goodbye_and_exit() {
    clear 2>/dev/null
    ui_ok "Goodbye."
    exit 0
}

run_desktop_linux_hop() {
    ui_step "Desktop-Linux"
    # Run as the normal user (NOT with sudo): Fedora.sh dispatches to
    # per-option sub-scripts that each handle privilege escalation
    # themselves as needed (Fedora-PostSetup.sh requests sudo internally
    # for its per-user steps; most other sub-scripts are invoked by
    # Fedora.sh with sudo directly).
    fetch_file "${CB_TOOLBOX}/Scripts/Fedora.sh" "${GH_TOOLBOX}/Scripts/Fedora.sh" /tmp/Fedora.sh "Desktop/Scripts/Fedora.sh" || exit 1
    bash /tmp/Fedora.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/Fedora.sh
}

run_homelab_hop() {
    ui_step "HomeLab"
    fetch_file "${CB_HOMELAB}/X27-Homelab.sh" "${GH_HOMELAB}/X27-Homelab.sh" /tmp/X27-Homelab.sh "Homelab/X27-Homelab.sh" || exit 1
    sudo bash /tmp/X27-Homelab.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/X27-Homelab.sh
}

run_ytdlp() {
    ui_step "YT-DLP"
    fetch_file "${CB_YTDLP}/Install-YT-DLP-Easy.sh" "${GH_YTDLP}/Install-YT-DLP-Easy.sh" /tmp/Install-YT-DLP-Easy.sh || exit 1
    bash /tmp/Install-YT-DLP-Easy.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Install-YT-DLP-Easy.sh
}

run_fastfetch() {
    ui_step "Fastfetch"
    fetch_file "${CB_TOOLS}/fsfetch.sh" "${GH_TOOLS}/fsfetch.sh" /tmp/fsfetch.sh "Tools/fsfetch.sh" || exit 1
    bash /tmp/fsfetch.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/fsfetch.sh
}

run_virtualization() {
    ui_step "Virtualization"
    fetch_file "${CB_TOOLS}/Virtualization_Setup.sh" "${GH_TOOLS}/Virtualization_Setup.sh" /tmp/Virtualization_Setup.sh "Tools/Virtualization_Setup.sh" || exit 1
    sudo bash /tmp/Virtualization_Setup.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Virtualization_Setup.sh
}

run_fedora_postsetup() {
    ui_step "Fedora Post-Setup"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Fedora/Fedora-PostSetup.sh" "${GH_TOOLBOX}/Linux-Desktop/Fedora/Fedora-PostSetup.sh" /tmp/Fedora-PostSetup.sh "Desktop/Linux-Desktop/Fedora/Fedora-PostSetup.sh" || exit 1
    bash /tmp/Fedora-PostSetup.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/Fedora-PostSetup.sh
}

run_fedora_kinoite() {
    ui_step "Fedora-Kinoite-Setup"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Fedora/Fedora-Kionite-Setup.sh" "${GH_TOOLBOX}/Linux-Desktop/Fedora/Fedora-Kionite-Setup.sh" /tmp/Fedora-Kionite-Setup.sh "Desktop/Linux-Desktop/Fedora/Fedora-Kionite-Setup.sh" || exit 1
    sudo bash /tmp/Fedora-Kionite-Setup.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Fedora-Kionite-Setup.sh
}

run_bazzite() {
    ui_step "Bazzite Setup"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Bazzite/Bazzite-Setup.sh" "${GH_TOOLBOX}/Linux-Desktop/Bazzite/Bazzite-Setup.sh" /tmp/Bazzite-Setup.sh "Desktop/Linux-Desktop/Bazzite/Bazzite-Setup.sh" || exit 1
    sudo bash /tmp/Bazzite-Setup.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Bazzite-Setup.sh
}

run_brave() {
    ui_step "Brave"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Browser/make_brave_great_again.sh" "${GH_TOOLBOX}/Linux-Desktop/Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh "Desktop/Linux-Desktop/Browser/make_brave_great_again.sh" || exit 1
    sudo bash /tmp/make_brave_great_again.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/make_brave_great_again.sh
}

run_proton_cachyos() {
    ui_step "Proton-CachyOS"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Gaming/proton-cachyos-installer.sh" "${GH_TOOLBOX}/Linux-Desktop/Gaming/proton-cachyos-installer.sh" /tmp/proton-cachyos-installer.sh "Desktop/Linux-Desktop/Gaming/proton-cachyos-installer.sh" || exit 1
    bash /tmp/proton-cachyos-installer.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/proton-cachyos-installer.sh
}

run_wine_kron4ek() {
    ui_step "Wine (Kron4ek)"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Gaming/Kron4ek-wine-installer.sh" "${GH_TOOLBOX}/Linux-Desktop/Gaming/Kron4ek-wine-installer.sh" /tmp/Kron4ek-wine-installer.sh "Desktop/Linux-Desktop/Gaming/Kron4ek-wine-installer.sh" || exit 1
    bash /tmp/Kron4ek-wine-installer.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/Kron4ek-wine-installer.sh
}

run_gaming_setup() {
    ui_step "Gaming Setup"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Gaming/Gaming.sh" "${GH_TOOLBOX}/Linux-Desktop/Gaming/Gaming.sh" /tmp/Gaming.sh "Desktop/Linux-Desktop/Gaming/Gaming.sh" || exit 1
    sudo bash /tmp/Gaming.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Gaming.sh
}

run_sleep_fix() {
    ui_step "Sleep Fix"
    fetch_file "${CB_TOOLS}/GigabyteSleep-Fix.sh" "${GH_TOOLS}/GigabyteSleep-Fix.sh" /tmp/GigabyteSleep-Fix.sh "Tools/GigabyteSleep-Fix.sh" || exit 1
    sudo bash /tmp/GigabyteSleep-Fix.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/GigabyteSleep-Fix.sh
}

run_flatpak_apps() {
    ui_step "Flatpak Apps"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Flatpak/flatpaks.sh" "${GH_TOOLBOX}/Linux-Desktop/Flatpak/flatpaks.sh" /tmp/flatpaks.sh "Desktop/Linux-Desktop/Flatpak/flatpaks.sh" || exit 1
    bash /tmp/flatpaks.sh < "$INPUT" > "$OUTPUT"
    rm -f /tmp/flatpaks.sh
}

run_flatpak_updates() {
    ui_step "Flatpak Updates"
    fetch_file "${CB_TOOLBOX}/Linux-Desktop/Flatpak/Flatpak-AutoUpdate-Setup.sh" "${GH_TOOLBOX}/Linux-Desktop/Flatpak/Flatpak-AutoUpdate-Setup.sh" /tmp/Flatpak-AutoUpdate-Setup.sh "Desktop/Linux-Desktop/Flatpak/Flatpak-AutoUpdate-Setup.sh" || exit 1
    sudo bash /tmp/Flatpak-AutoUpdate-Setup.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Flatpak-AutoUpdate-Setup.sh
}

run_docker_install() {
    ui_step "Install Docker"
    fetch_file "${CB_HOMELAB}/Scripts/Docker/Docker-Install.sh" "${GH_HOMELAB}/Scripts/Docker/Docker-Install.sh" /tmp/Docker-Install.sh "Homelab/Scripts/Docker/Docker-Install.sh" || exit 1
    sudo bash /tmp/Docker-Install.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Docker-Install.sh
}

run_server_updater() {
    ui_step "Auto Update setup"
    fetch_file "${CB_HOMELAB}/Scripts/Server-Updater.sh" "${GH_HOMELAB}/Scripts/Server-Updater.sh" /tmp/Server-Updater.sh "Homelab/Scripts/Server-Updater.sh" || exit 1
    sudo bash /tmp/Server-Updater.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Server-Updater.sh
}

run_docker_updater() {
    ui_step "Docker Compose Updater"
    fetch_file "${CB_HOMELAB}/Scripts/Docker/Docker-Updater.sh" "${GH_HOMELAB}/Scripts/Docker/Docker-Updater.sh" /tmp/Docker-Updater.sh "Homelab/Scripts/Docker/Docker-Updater.sh" || exit 1
    sudo bash /tmp/Docker-Updater.sh < "$INPUT" > "$OUTPUT"
    sudo rm -f /tmp/Docker-Updater.sh
}

clear 2>/dev/null
ui_banner

check_and_install_dependencies

# Arrow-pick pool: grouped by category (left pane), flattened to plain leaf
# names (no breadcrumbs — the category label already gives that context).
# Picking any item runs it directly; there's no separate "open the
# Desktop-Linux/HomeLab submenu" entry anymore since browsing a category
# here already reaches every item in it directly.
MENU_LABELS=(
    $'\x01Desktop-Linux'
    "Fedora Post-Setup"
    "Fedora-Kinoite-Setup"
    "Bazzite Setup"
    "Brave"
    "Proton-CachyOS"
    "Wine (Kron4ek)"
    "Gaming Setup"
    "Sleep Fix"
    "Flatpak Apps"
    "Flatpak Updates"
    $'\x01HomeLab'
    "Install Docker"
    "Auto Update setup"
    "Docker Compose Updater"
    $'\x01Tools'
    "YT-DLP"
    "Fastfetch"
    "Virtualization"
    "Exit"
)
LAST_MENU_INDEX=$(( ${#MENU_LABELS[@]} - 1 ))

while true; do
    clear 2>/dev/null
    ui_banner

    if [ "$INPUT" = "/dev/tty" ]; then
        if ! ui_pick "Choose a script to download and run" "${MENU_LABELS[@]}"; then
            say_goodbye_and_exit
        fi
        [ "$PICK_INDEX" -eq "$LAST_MENU_INDEX" ] && say_goodbye_and_exit

        clear 2>/dev/null
        case $PICK_INDEX in
            0)  run_fedora_postsetup ;;
            1)  run_fedora_kinoite ;;
            2)  run_bazzite ;;
            3)  run_brave ;;
            4)  run_proton_cachyos ;;
            5)  run_wine_kron4ek ;;
            6)  run_gaming_setup ;;
            7)  run_sleep_fix ;;
            8)  run_flatpak_apps ;;
            9)  run_flatpak_updates ;;
            10) run_docker_install ;;
            11) run_server_updater ;;
            12) run_docker_updater ;;
            13) run_ytdlp ;;
            14) run_fastfetch ;;
            15) run_virtualization ;;
        esac
    else
        ui_step "Choose a script to download and run"
        ui_rule
        ui_menu_item 1  "Desktop-Linux"
        ui_menu_item 2  "HomeLab"
        ui_menu_item 3  "YT-DLP"
        ui_menu_item 4  "Fastfetch"
        ui_menu_item 5  "Virtualization"
        ui_menu_item 0  "Exit"
        printf '%s  ❯%s Enter your choice [0-5]: ' "$C_BOLD" "$C_RESET"
        read -r choice < "$INPUT"

        if [ -z "$choice" ] || [ "$choice" -eq 0 ] 2>/dev/null; then
            say_goodbye_and_exit
        fi

        clear 2>/dev/null
        case $choice in
            1) run_desktop_linux_hop ;;
            2) run_homelab_hop ;;
            3) run_ytdlp ;;
            4) run_fastfetch ;;
            5) run_virtualization ;;
            *) ui_err "Invalid choice." ;;
        esac
    fi

    printf '\n'
    printf '%s  ❯%s Press Enter to return to the main menu… ' "$C_BOLD" "$C_RESET"
    read -r _ < "$INPUT"
    printf '%s' "$C_RESET"
done
