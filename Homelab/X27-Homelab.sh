#!/bin/bash

if [ -r /dev/tty ]; then
    INPUT=/dev/tty
else
    INPUT=/dev/stdin
fi

if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'
else
    C_RESET="" C_BOLD="" C_DIM=""
    C_RED="" C_GREEN="" C_YELLOW="" C_BLUE=""
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

ui_info()    { printf '%s  ›%s %s\n'   "$C_BLUE"   "$C_RESET" "$1"; }
ui_ok()      { printf '%s  ✔%s %s\n'   "$C_GREEN"  "$C_RESET" "$1"; }
ui_warn()    { printf '%s  ▲%s %s\n'   "$C_YELLOW" "$C_RESET" "$1"; }
ui_err()     { printf '%s  ✖%s %s\n'   "$C_RED"    "$C_RESET" "$1" >&2; }
ui_step() {
    calc_margin
    printf '\n%s%s%s%s%s\n' "$MARGIN" "$C_BOLD" "$C_RED" "$1" "$C_RESET"
    printf '%s%s%s%s\n' "$MARGIN" "$C_DIM" "$RULE_DASH" "$C_RESET"
}
ui_rule()    { calc_margin; printf '%s%s%s%s\n' "$MARGIN" "$C_DIM" "$RULE_DASH" "$C_RESET"; }

ui_menu_item() {
    calc_margin
    printf '%s   %s%s)%s %s%s%s\n' \
        "$MARGIN" "$C_BOLD" "$1" "$C_RESET" \
        "$C_BOLD" "$2" "$C_RESET"
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

CODEBERG_RAW="https://codeberg.org/X27/X-Linuxtool/raw/branch/main/Homelab"
GITHUB_RAW="https://raw.githubusercontent.com/GamerX27/X-Linuxtool/main/Homelab"

# Set by X-Linuxtool.sh when run from a local clone, to use scripts on disk.
LOCAL_BASE="${X27_LOCAL_ROOT:+$X27_LOCAL_ROOT/Homelab}"

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

fetch_repo_file() {
    local rel="$1" out="$2"

    if [ -n "$LOCAL_BASE" ] && [ -f "$LOCAL_BASE/$rel" ]; then
        ui_info "Using local copy: ${rel}"
        cp "$LOCAL_BASE/$rel" "$out"
        return 0
    fi

    ui_info "Fetching ${rel} from Codeberg…"
    if _download "${CODEBERG_RAW}/${rel}" "$out"; then
        ui_ok "Downloaded from Codeberg."
        return 0
    fi

    ui_warn "Codeberg unreachable; falling back to GitHub mirror…"
    if _download "${GITHUB_RAW}/${rel}" "$out"; then
        ui_ok "Downloaded from GitHub mirror."
        return 0
    fi

    ui_err "Could not fetch ${rel} from Codeberg or GitHub."
    return 1
}

MENU_LABELS=("Install Docker" "Auto Update setup" "Docker Compose Updater" "Back")
LAST_MENU_INDEX=3

while true; do
    clear 2>/dev/null

    if [ "$INPUT" = "/dev/tty" ]; then
        if ui_pick "HomeLab" "${MENU_LABELS[@]}"; then
            [ "$PICK_INDEX" -eq "$LAST_MENU_INDEX" ] && choice=0 || choice=$((PICK_INDEX + 1))
        else
            choice=0
        fi
    else
        ui_step "HomeLab"
        ui_rule
        ui_menu_item 1 "Install Docker"
        ui_menu_item 2 "Auto Update setup"
        ui_menu_item 3 "Docker Compose Updater"
        ui_menu_item 0 "Back"
        printf '%s  ❯%s Enter your choice [0-3]: ' "$C_BOLD" "$C_RESET"
        read -r choice < "$INPUT" || exit 0
    fi

    case $choice in
        0)
            ui_info "Returning to the main menu…"
            exit 0
            ;;
        1)
            ui_step "Install Docker"
            fetch_repo_file "Scripts/Docker/Docker-Install.sh" Docker-Install.sh || exit 1
            sudo bash Docker-Install.sh
            sudo rm Docker-Install.sh
            ;;
        2)
            ui_step "Server-Updater"
            fetch_repo_file "Scripts/Server-Updater.sh" Server-Updater.sh || exit 1
            sudo bash Server-Updater.sh
            sudo rm Server-Updater.sh
            ;;
        3)
            ui_step "Docker-Updater"
            fetch_repo_file "Scripts/Docker/Docker-Updater.sh" Docker-Updater.sh || exit 1
            sudo bash Docker-Updater.sh
            sudo rm Docker-Updater.sh
            ;;
        *)
            ui_err "Invalid choice."
            ;;
    esac

    printf '\n'
    printf '%s  ❯%s Press Enter to return to this menu… ' "$C_BOLD" "$C_RESET"
    read -r _ < "$INPUT"
    printf '%s' "$C_RESET"
done
