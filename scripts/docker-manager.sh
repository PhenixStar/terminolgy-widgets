#!/bin/bash

# Docker Manager Widget — WaveTerm
# Polls Docker container status on DGX1 V100 via SSH every 15 seconds.

SSH_HOST="120.28.138.55"
SSH_PORT="2442"
SSH_USER="phenix"
SSH_KEY="$HOME/.ssh/id_ed25519"
DISPLAY_HOST="dgx-station"
REFRESH=15

# shellcheck source=../lib/colors.sh
source "$(dirname "$0")/../lib/colors.sh"
# shellcheck source=../lib/ssh-helper.sh
source "$(dirname "$0")/../lib/ssh-helper.sh"



truncate_str() {
    local str="$1"
    local max="$2"
    if [ "${#str}" -gt "$max" ]; then
        echo "${str:0:$((max - 1))}…"
    else
        printf "%-${max}s" "$str"
    fi
}

status_color() {
    local status="$1"
    case "$status" in
        Up*healthy*)   echo -e "${GREEN}" ;;
        Up*unhealthy*) echo -e "${YELLOW}" ;;
        Up*)           echo -e "${GREEN}" ;;
        Exited*)       echo -e "${RED}" ;;
        Created*)      echo -e "${GRAY}" ;;
        *)             echo -e "${GRAY}" ;;
    esac
}

print_header() {
    local now running stopped
    now=$(date '+%H:%M:%S')
    running="${1:-?}"
    stopped="${2:-?}"
    clear
    echo -e "${BOLD}${CYAN}Docker Manager — DGX1${RESET}  |  ${GREEN}${running} running${RESET}, ${RED}${stopped} stopped${RESET}  |  ${DIM}${now}${RESET}"
    echo -e "${GRAY}$(printf '%.0s─' {1..90})${RESET}"
    printf "${BOLD}%-25s  %-30s  %-18s  %-30s  %s${RESET}\n" \
        "NAME" "IMAGE" "STATUS" "PORTS" "UPTIME"
    echo -e "${GRAY}$(printf '%.0s─' {1..90})${RESET}"
}

print_row() {
    local name="$1"
    local image="$2"
    local status="$3"
    local ports="$4"
    local uptime="$5"

    local name_t image_t status_t ports_t color
    name_t=$(truncate_str "$name" 25)
    image_t=$(truncate_str "$image" 30)
    status_t=$(truncate_str "$status" 18)
    ports_t=$(truncate_str "$ports" 30)
    color=$(status_color "$status")

    printf "%-25s  %-30s  ${color}%-18s${RESET}  %-30s  %s\n" \
        "$name_t" "$image_t" "$status_t" "$ports_t" "$uptime"
}

fetch_and_display() {
    local raw
    raw=$(ssh_exec "$SSH_USER" "$SSH_HOST" "$SSH_PORT" "$SSH_KEY" \
        "docker ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.RunningFor}}'")

    local ssh_exit=$?

    if [ $ssh_exit -ne 0 ] || [ -z "$raw" ] && [ $ssh_exit -ne 0 ]; then
        print_header "?" "?"
        echo ""
        echo -e "  ${FAIL} ${BOLD}DGX1 unreachable${RESET} — retrying in ${REFRESH}s"
        echo -e "  ${DIM}(SSH to ${SSH_USER}@${SSH_HOST}:${SSH_PORT} failed — exit ${ssh_exit})${RESET}"
        return
    fi

    if [ -z "$raw" ]; then
        print_header "0" "0"
        echo -e "\n  ${DIM}No containers found.${RESET}"
        return
    fi

    local running_lines=()
    local stopped_lines=()
    local running=0 stopped=0

    while IFS=$'\t' read -r name image status ports uptime; do
        [ -z "$name" ] && continue
        local row
        row=$(print_row "$name" "$image" "$status" "$ports" "$uptime")
        case "$status" in
            Up*)
                running_lines+=("$row")
                ((running++))
                ;;
            *)
                stopped_lines+=("$row")
                ((stopped++))
                ;;
        esac
    done <<< "$raw"

    local total=$((running + stopped))

    print_header "$running" "$stopped"

    # Running containers first
    if [ ${#running_lines[@]} -gt 0 ]; then
        for line in "${running_lines[@]}"; do
            echo "$line"
        done
    fi

    # Stopped containers
    if [ ${#stopped_lines[@]} -gt 0 ]; then
        [ ${#running_lines[@]} -gt 0 ] && echo -e "${GRAY}$(printf '%.0s─' {1..90})${RESET}"
        for line in "${stopped_lines[@]}"; do
            echo "$line"
        done
    fi

    echo -e "${GRAY}$(printf '%.0s─' {1..90})${RESET}"
    echo -e "  ${OK} ${GREEN}${running} running${RESET}  |  ${FAIL} ${RED}${stopped} stopped${RESET}  |  ${BOLD}${total} total${RESET}"
}

# Main loop
while true; do
    fetch_and_display
    sleep "$REFRESH"
done
