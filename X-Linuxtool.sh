#!/bin/bash

# Designed to run via `curl | bash`, which means bash reads THIS script from
# stdin — so we can't redirect stdin away from it wholesale. Interactive
# commands (menu + sub-scripts) instead read from $INPUT, which points at
# the controlling terminal when one exists.
if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

# Nord palette (https://www.nordtheme.com). Only enabled on an actual
# terminal, so piped/redirected output stays clean.
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_REV=$'\033[7m'

    case "${TERM:-}" in
        linux|screen|screen-*|tmux-*)
            # Nearest 256-color approximations of the Nord palette.
            C_BASE=$'\033[38;5;236m'    # nord0  2e3440
            C_SURFACE=$'\033[38;5;237m' # nord1  3b4252
            C_GREY=$'\033[38;5;244m'    # nord3  4c566a
            C_FG=$'\033[38;5;253m'      # nord4  d8dee9
            C_CYAN=$'\033[38;5;116m'    # nord8  88c0d0
            C_BLUE=$'\033[38;5;110m'    # nord9  81a1c1
            C_RED=$'\033[38;5;167m'     # nord11 bf616a
            C_YELLOW=$'\033[38;5;222m'  # nord13 ebcb8b
            C_GREEN=$'\033[38;5;150m'   # nord14 a3be8c
            C_MAGENTA=$'\033[38;5;139m' # nord15 b48ead
            C_ACCENT=$'\033[38;5;167m'  # nord11 bf616a
            BG_ACCENT=$'\033[48;5;167m' # nord11 bf616a
            FG_ONACCENT=$'\033[38;5;236m' # nord0 2e3440
            ;;
        *)
            C_BASE=$'\033[38;2;46;52;64m'      # nord0  2e3440
            C_SURFACE=$'\033[38;2;59;66;82m'   # nord1  3b4252
            C_GREY=$'\033[38;2;76;86;106m'     # nord3  4c566a
            C_FG=$'\033[38;2;216;222;233m'     # nord4  d8dee9
            C_CYAN=$'\033[38;2;136;192;208m'   # nord8  88c0d0
            C_BLUE=$'\033[38;2;129;161;193m'   # nord9  81a1c1
            C_RED=$'\033[38;2;191;97;106m'     # nord11 bf616a
            C_YELLOW=$'\033[38;2;235;203;139m' # nord13 ebcb8b
            C_GREEN=$'\033[38;2;163;190;140m'  # nord14 a3be8c
            C_MAGENTA=$'\033[38;2;180;142;173m' # nord15 b48ead
            C_ACCENT=$'\033[38;2;191;97;106m'  # nord11 bf616a
            BG_ACCENT=$'\033[48;2;191;97;106m' # nord11 bf616a
            FG_ONACCENT=$'\033[38;2;46;52;64m' # nord0  2e3440
            ;;
    esac
else
    C_RESET="" C_BOLD="" C_DIM="" C_REV=""
    C_BASE="" C_SURFACE="" C_GREY="" C_FG=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_MAGENTA="" C_CYAN="" C_ACCENT=""
    BG_ACCENT="" FG_ONACCENT=""
fi

ui_banner() {
    local width=46
    # Center a plain (ASCII) string inside the box and print it as a row.
    _bline() {
        local text="$1" color="$2" len pad_l pad_r
        len=${#text}
        pad_l=$(( (width - len) / 2 ))
        pad_r=$(( width - len - pad_l ))
        printf '%s║%s%*s%s%s%s%*s%s║%s\n' \
            "$C_GREY$C_BOLD" "$C_RESET" "$pad_l" "" \
            "$color" "$text" "$C_RESET" "$pad_r" "" \
            "$C_GREY$C_BOLD" "$C_RESET"
    }
    local bar
    bar=$(printf '═%.0s' $(seq 1 "$width"))

    printf '\n'
    printf '%s╔%s╗%s\n' "$C_GREY$C_BOLD" "$bar" "$C_RESET"
    _bline "" ""
    _bline "X 2 7   T O O L B O X" "$C_ACCENT$C_BOLD"
    _bline "Linux desktop · homelab · gaming" "$C_CYAN"
    _bline "" ""
    printf '%s╚%s╝%s\n' "$C_GREY$C_BOLD" "$bar" "$C_RESET"
    printf '%s          all-in-one installer & setup tool%s\n\n' "$C_GREY" "$C_RESET"
}

ui_rule() {
    printf '%s──────────────────────────────────────────────────────%s\n' "$C_DIM$C_GREY" "$C_RESET"
}

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step()    { printf '\n%s  ➤ %s%s\n' "$C_MAGENTA$C_BOLD" "$1" "$C_RESET"; }

ui_menu_item() {
    # ui_menu_item <number> <icon> <label>
    printf '   %s%s)%s %s  %s%s%s\n' \
        "$C_ACCENT$C_BOLD" "$1" "$C_RESET" "$2" "$C_BOLD" "$3" "$C_RESET"
}

# ui_select_menu <result-var> <label1>$'\x1f'<desc1> [label2$'\x1f'desc2 ...]
# Interactive picker: type to live-filter items by name/description/number,
# Up/Down to move within the filtered results (the description of the
# highlighted item is shown below the list), Enter to confirm, Esc/Ctrl-C
# to cancel. Falls back to a plain numeric prompt when there's no
# controlling TTY to read raw keys from (e.g. a non-interactive pipe).
ui_select_menu() {
    local __resultvar=$1; shift
    local -a raw=("$@")
    local count=${#raw[@]}
    local -a labels=() descs=() filtered=()
    local i
    for ((i = 0; i < count; i++)); do
        labels+=("${raw[i]%%$'\x1f'*}")
        descs+=("${raw[i]#*$'\x1f'}")
    done
    local query="" sel=0 fcount=0 key rest n row_width=52

    # Only the interactive picker needs a real controlling terminal to read
    # raw keys from. `-r /dev/tty` can be true even without one (the device
    # node is world-readable), so actually try to open it before committing;
    # fall back to a plain numeric prompt on failure.
    if ! exec 3<"$INPUT" 2>/dev/null; then
        for ((i = 0; i < count; i++)); do
            ui_menu_item "$((i + 1))" "" "${labels[i]}"
            printf '        %s%s%s\n' "$C_GREY$C_DIM" "${descs[i]}" "$C_RESET"
        done
        printf '%s  ❯%s Enter your choice %s[1-%d]%s: ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY" "$count" "$C_RESET"
        read -r n < "$INPUT"
        eval "$__resultvar=\$n"
        return
    fi

    _ui_select_filter() {
        local i lc_hay lc_query=${query,,}
        filtered=()
        for ((i = 0; i < count; i++)); do
            lc_hay="${labels[i],,} ${descs[i],,}"
            if [[ -z "$query" || "$lc_hay" == *"$lc_query"* ]]; then
                filtered+=("$i")
            elif [[ "$query" =~ ^[0-9]+$ ]] && [[ "$((i + 1))" == "$query"* ]]; then
                filtered+=("$i")
            fi
        done
        fcount=${#filtered[@]}
        [ "$sel" -ge "$fcount" ] && sel=$(( fcount > 0 ? fcount - 1 : 0 ))
    }

    _ui_select_draw() {
        printf '\r\033[2K'
        if [ -n "$query" ]; then
            printf '  %s🔍%s %s%s%s%s▏%s\n' "$C_CYAN" "$C_RESET" "$C_FG$C_BOLD" "$query" "$C_RESET" "$C_DIM" "$C_RESET"
        else
            printf '  %s🔍%s %stype to search…%s\n' "$C_CYAN" "$C_RESET" "$C_DIM$C_GREY" "$C_RESET"
        fi
        local j idx label
        for ((j = 0; j < count; j++)); do
            printf '\r\033[2K'
            if [ "$j" -lt "$fcount" ]; then
                idx=${filtered[j]}
                label=$(printf '%2d) %s' "$((idx + 1))" "${labels[idx]}")
                if [ "$j" -eq "$sel" ]; then
                    printf '  %s ❯ %-*s%s\n' "$BG_ACCENT$FG_ONACCENT$C_BOLD" "$row_width" "$label" "$C_RESET"
                else
                    printf '  %s   %-*s%s\n' "$C_FG" "$row_width" "$label" "$C_RESET"
                fi
            elif [ "$j" -eq 0 ]; then
                printf '  %s   no matches%s\n' "$C_GREY$C_DIM" "$C_RESET"
            else
                printf '\n'
            fi
        done
        printf '\r\033[2K'
        if [ "$fcount" -gt 0 ]; then
            printf '  %s   %s%s\n' "$C_GREY$C_DIM" "${descs[${filtered[$sel]}]}" "$C_RESET"
        else
            printf '\n'
        fi
    }

    _ui_select_filter
    tput civis 2>/dev/null
    _ui_select_draw
    while true; do
        IFS= read -rsn1 key <&3
        if [[ $key == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.01 rest <&3
            key+="$rest"
            case "$key" in
                $'\x1b[A') [ "$fcount" -gt 0 ] && sel=$(( (sel - 1 + fcount) % fcount )) ;;
                $'\x1b[B') [ "$fcount" -gt 0 ] && sel=$(( (sel + 1) % fcount )) ;;
                $'\x1b')   sel=-1; break ;;
            esac
        elif [[ -z $key ]]; then
            [ "$fcount" -gt 0 ] && break
        elif [[ $key == $'\x03' ]]; then
            sel=-1; break
        elif [[ $key == $'\x7f' || $key == $'\x08' ]]; then
            query=${query%?}
            _ui_select_filter
        elif [[ $key =~ [[:print:]] ]]; then
            query+="$key"
            sel=0
            _ui_select_filter
        fi
        printf '\033[%dA' "$((count + 2))"
        _ui_select_draw
    done
    tput cnorm 2>/dev/null
    exec 3<&-

    if [ "$sel" -lt 0 ] || [ "$fcount" -eq 0 ]; then
        eval "$__resultvar="
    else
        eval "$__resultvar=$(( filtered[sel] + 1 ))"
    fi
}

trap 'tput cnorm 2>/dev/null' EXIT
trap 'tput cnorm 2>/dev/null; printf "\n"; exit 130' INT TERM

# Codeberg is the primary source; GitHub is a mirror used as a fallback when
# Codeberg cannot be reached.
CB_BASE="https://codeberg.org/X27/X-Linuxtool/raw/branch/main"
GH_BASE="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main"

CB_TOOLBOX="${CB_BASE}/Desktop"
GH_TOOLBOX="${GH_BASE}/Desktop"

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
    # _download <url> <output-file>
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
    # fetch_file <codeberg-url> <github-url> <output-file> [local-relative-path]
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
        sudo $pkg_manager update -y
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

clear 2>/dev/null
ui_banner

check_and_install_dependencies

while true; do
    clear 2>/dev/null
    ui_banner

    ui_step "Choose a script to download and run"
    ui_rule
    printf '%s  type to search%s   %s↑↓%s move   %sEnter%s select   %sEsc%s exit\n\n' \
        "$C_GREY" "$C_RESET" "$C_GREY" "$C_RESET" "$C_GREY" "$C_RESET" "$C_GREY" "$C_RESET"

    ui_select_menu choice \
        $'🐧 Desktop-Linux\x1fFedora post-install setup, Kinoite & Bazzite tweaks' \
        $'🏠 HomeLab\x1fDocker install, auto-updates & compose updater' \
        $'🦁 Brave\x1fDebloat & harden the Brave browser' \
        $'🎬 YT-DLP\x1fInstall the YT-DLP-Easy video downloader' \
        $'🎮 Proton/Wine & Gaming\x1fProton-CachyOS, Kron4ek Wine builds & full gaming setup' \
        $'💤 Sleep Fix\x1fFix Gigabyte boards not waking from sleep' \
        $'⚡ Fastfetch\x1fCustom Fastfetch config for your terminal' \
        $'🖥️  Virtualization\x1fSet up QEMU/KVM + virt-manager' \
        $'📦 Flatpak Apps\x1fInstall a curated set of Flatpak apps' \
        $'🔄 Flatpak Updates\x1fEnable automatic Flatpak updates' \
        $'🚪 Exit\x1fQuit the toolbox'
    printf '\n'

    if [ -z "$choice" ] || [ "$choice" -eq 11 ]; then
        clear 2>/dev/null
        ui_ok "Goodbye."
        exit 0
    fi

    clear 2>/dev/null

    case $choice in
        1)
            ui_step "Desktop-Linux"
            # Run as the normal user (NOT with sudo): Fedora.sh dispatches to
            # per-option sub-scripts that each handle privilege escalation
            # themselves as needed (Fedora-PostSetup.sh requests sudo internally
            # for its per-user steps; Fedora-Kionite-Setup.sh and
            # Bazzite-Setup.sh are invoked by Fedora.sh with sudo directly).
            fetch_file "${CB_TOOLBOX}/Fedora.sh" "${GH_TOOLBOX}/Fedora.sh" /tmp/Fedora.sh "Desktop/Fedora.sh" || exit 1
            bash /tmp/Fedora.sh < "$INPUT"
            rm -f /tmp/Fedora.sh
            ;;
        2)
            ui_step "HomeLab"
            fetch_file "${CB_HOMELAB}/X27-Homelab.sh" "${GH_HOMELAB}/X27-Homelab.sh" /tmp/X27-Homelab.sh "Homelab/X27-Homelab.sh" || exit 1
            sudo bash /tmp/X27-Homelab.sh < "$INPUT"
            sudo rm -f /tmp/X27-Homelab.sh
            ;;
        3)
            ui_step "Brave"
            fetch_file "${CB_TOOLBOX}/Browser/make_brave_great_again.sh" "${GH_TOOLBOX}/Browser/make_brave_great_again.sh" /tmp/make_brave_great_again.sh "Desktop/Browser/make_brave_great_again.sh" || exit 1
            sudo bash /tmp/make_brave_great_again.sh < "$INPUT"
            sudo rm -f /tmp/make_brave_great_again.sh
            ;;
        4)
            ui_step "YT-DLP"
            fetch_file "${CB_YTDLP}/Install-YT-DLP-Easy.sh" "${GH_YTDLP}/Install-YT-DLP-Easy.sh" /tmp/Install-YT-DLP-Easy.sh || exit 1
            bash /tmp/Install-YT-DLP-Easy.sh < "$INPUT"
            sudo rm -f /tmp/Install-YT-DLP-Easy.sh
            ;;
        5)
            ui_step "Proton/Wine & Gaming"
            # Run as the normal user (NOT with sudo): GamingTools.sh dispatches to
            # per-option sub-scripts that each handle privilege escalation
            # themselves as needed (Wine and Proton run as the normal user;
            # Gaming Setup is invoked by GamingTools.sh with sudo directly).
            fetch_file "${CB_TOOLBOX}/GamingTools.sh" "${GH_TOOLBOX}/GamingTools.sh" /tmp/GamingTools.sh "Desktop/GamingTools.sh" || exit 1
            bash /tmp/GamingTools.sh < "$INPUT"
            rm -f /tmp/GamingTools.sh
            ;;
        6)
            ui_step "Sleep Fix"
            fetch_file "${CB_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" "${GH_TOOLBOX}/Tools/GigabyteSleep-Fix.sh" /tmp/GigabyteSleep-Fix.sh "Desktop/Tools/GigabyteSleep-Fix.sh" || exit 1
            sudo bash /tmp/GigabyteSleep-Fix.sh < "$INPUT"
            sudo rm -f /tmp/GigabyteSleep-Fix.sh
            ;;
        7)
            ui_step "Fastfetch"
            fetch_file "${CB_TOOLBOX}/Tools/fsfetch.sh" "${GH_TOOLBOX}/Tools/fsfetch.sh" /tmp/fsfetch.sh "Desktop/Tools/fsfetch.sh" || exit 1
            bash /tmp/fsfetch.sh < "$INPUT"
            rm -f /tmp/fsfetch.sh
            ;;
        8)
            ui_step "Virtualization"
            fetch_file "${CB_TOOLBOX}/Tools/Virtualization_Setup.sh" "${GH_TOOLBOX}/Tools/Virtualization_Setup.sh" /tmp/Virtualization_Setup.sh "Desktop/Tools/Virtualization_Setup.sh" || exit 1
            sudo bash /tmp/Virtualization_Setup.sh < "$INPUT"
            sudo rm -f /tmp/Virtualization_Setup.sh
            ;;
        9)
            ui_step "Flatpak Apps"
            fetch_file "${CB_TOOLBOX}/Flatpak/flatpaks.sh" "${GH_TOOLBOX}/Flatpak/flatpaks.sh" /tmp/flatpaks.sh "Desktop/Flatpak/flatpaks.sh" || exit 1
            bash /tmp/flatpaks.sh < "$INPUT"
            rm -f /tmp/flatpaks.sh
            ;;
        10)
            ui_step "Flatpak Updates"
            fetch_file "${CB_TOOLBOX}/Flatpak/Flatpak-AutoUpdate-Setup.sh" "${GH_TOOLBOX}/Flatpak/Flatpak-AutoUpdate-Setup.sh" /tmp/Flatpak-AutoUpdate-Setup.sh "Desktop/Flatpak/Flatpak-AutoUpdate-Setup.sh" || exit 1
            sudo bash /tmp/Flatpak-AutoUpdate-Setup.sh < "$INPUT"
            sudo rm -f /tmp/Flatpak-AutoUpdate-Setup.sh
            ;;
        *)
            ui_err "Invalid choice."
            ;;
    esac

    printf '\n'
    printf '%s  ❯%s Press Enter to return to the main menu…%s ' "$C_ACCENT$C_BOLD" "$C_RESET" "$C_GREY"
    read -r _ < "$INPUT"
    printf '%s' "$C_RESET"
done
