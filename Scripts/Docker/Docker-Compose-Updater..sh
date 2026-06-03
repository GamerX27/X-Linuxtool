#!/bin/bash

# Colors for UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOCKER_BASE_DIR="$HOME/docker"

if [ ! -d "$DOCKER_BASE_DIR" ]; then
    if [ -d "/docker" ]; then
        DOCKER_BASE_DIR="/docker"
    else
        DOCKER_BASE_DIR="."
    fi
fi

# Ensure docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker command not found.${NC}"
    exit 1
fi

# Global array to store service information
# Format: "index|service_name|image_name|file_path"
SERVICES_DATA=()

load_services() {
    echo -e "${BLUE}Scanning for Compose services...${NC}"
    SERVICES_MSGS=()
    SERVICES_DATA=()
    local counter=0

    # Find all compose files
    local files=$(find "$DOCKER_BASE_DIR" -type f \( -name "compose.yml" -o -name "docker-compose.yml" \) 2>/dev/null | sort)

    if [ -z "$files" ]; then
        return 1
    fi

    for file in $files; do
        # Extract services and images using docker compose config
        # We use JSON format to reliably parse service names and their images
        while read -r line; do
            [ -z "$line" ] && continue

            local s_name=$(echo "$line" | cut -d'|' -f1)
            local s_image=$(echo "$line" | cut -d'|' -f2)

            SERVICES_DATA+=("$counter|$s_name|$s_image|$file")
            ((counter++))
        done < <(
            # This subshell processes each file to extract service/image pairs
            docker compose -f "$file" config --format json 2>/dev/null | \
            jq -r '.services | to_entries[] | "\(.key)|\(.value.image)"' 2>/dev/null || \
            # Fallback if jq is not installed: use a simpler grep approach
            docker compose -f "$file" config --services | while read -r s; do
                local img=$(docker compose -f "$file" config --format json 2>/dev/null | \
                            grep -A 10 "\"$s\":" | grep '"image":' | cut -d'"' -f4)
                echo "$s|$img"
            done
        )
    done
    return 0
}

display_list() {
    printf "\033[H\033[J" # Clear screen
    echo "==============================================================================="
    echo -e "${CYAN}             🐳 DOCKER COMPOSE UPDATER 🐳${NC}"
    echo -e "Base Dir: ${YELLOW}$DOCKER_BASE_DIR${NC}"
    echo "-------------------------------------------------------------------------------"

    if [ ${#SERVICES_DATA[@]} -eq 0 ]; then
        echo -e "${RED}No services found.${NC}"
        return 0
    fi

    # Header for the table
    printf "${CYAN}%-5s %-20s %-35s %-s${NC}\n" "ID" "Service" "Image" "Compose File"
    echo "-------------------------------------------------------------------------------"

    for entry in "${SERVICES_DATA[@]}"; do
        IFS='|' read -r idx name image path <<< "$entry"
        printf "[%2d] %-20s %-35s %s\n" "$idx" "$name" "$image" "$path"
    done

    echo "-------------------------------------------------------------------------------"
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${BLUE}a${NC} - Update everything"
    echo -e "  ${BLUE}0,2,3${NC} - Update specific indices (comma separated)"
    echo -e "  ${BLUE}r${NC} - Rescan files"
    echo -e "  ${BLUE}q${NC} - Quit"
    echo "==============================================================================="
    return 0
}

apply_updates() {
    local selection=$1
    local target_indices=()

    if [ "$selection" == "a" ]; then
        target_indices=("${!SERVICES_DATA[@]}")
    else
        # Split comma separated input into array
        IFS=',' read -ra ADDR <<< "$selection"
        for idx in "${ADDR[@]}"; do
            # Trim whitespace
            idx=$(echo "$idx" | xargs)
            if [[ "$idx" =~ ^[0-9]+$ ]] && [ "$idx" -lt "${#SERVICES_DATA[@]}" ]; then
                target_indices+=("$idx")
            else
                echo -e "${RED}Invalid index: $idx${NC}"
            fi
        done
    fi

    if [ ${#target_indices[@]} -eq 0 ]; then
        echo -e "${RED}No valid targets selected.${NC}"
        sleep 2
        return 1
    fi

    for idx in "${target_indices[@]}"; do
        IFS='|' read -r i name image path <<< "${SERVICES_DATA[$idx]}"
        echo -e "\n${PURPE}>>> Processing: $name ($image)${NC}"
        echo -e "  File: $path"
        echo -e "  Pulling images..."
        if docker compose -f "$path" pull "$name"; then
            echo -e "  Recreating service..."
            docker compose -f "$path" up -d --force-recreate "$name"
            echo -e "${GREEN}  Successfully updated $name${NC}"
        else
            echo -e "${RED}  Failed to update $name${NC}"
        fi
    done
    echo -e "\n${GREEN}Task completed.${NC}"
    sleep 2
}

# Main execution loop
load_services
if [ ${#SERVICES_DATA[@]} -gt 0 ]; then
    while true; do
        display_list
        read -p "Selection: " user_choice

        case $user_choice in
            [Qq]*) exit 0 ;;
            [Rr]*)
                load_services
                ;;
            a)
                apply_updates "a"
                ;;
            *)
                apply_updates "$user_choice"
                ;;
        esac
    done
else
    echo -e "${YELLOW}No services found to manage.${NC}"
fi
