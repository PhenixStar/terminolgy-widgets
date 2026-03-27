#!/bin/bash

# WaveTerm widget: Git Sync Status
# Checks git repo sync state across Local (Sweep) and Remote (DGX1) every 60 seconds.

# --- Config ---
REMOTE_USER="phenix"
REMOTE_HOST="120.28.138.55"
REMOTE_PORT="2442"
REMOTE_KEY="$HOME/.ssh/id_ed25519"
SSH_TIMEOUT=8

# shellcheck source=../lib/colors.sh
source "$(dirname "$0")/../lib/colors.sh"
# shellcheck source=../lib/ssh-helper.sh
source "$(dirname "$0")/../lib/ssh-helper.sh"

declare -A LOCAL_REPOS=(
    ["mapping-config"]="D:/mapping"
    ["AIO Canvas"]="D:/Dev/Active/canvas-A-I-O"
)
LOCAL_ORDER=("mapping-config" "AIO Canvas")

declare -A REMOTE_REPOS=(
    ["mapping-config"]="/raid/projects/mapping"
    ["AIO Canvas"]="/raid/projects/canvas-A-I-O"
)
REMOTE_ORDER=("mapping-config" "AIO Canvas")

# --- Helpers ---

# Run a git command in a specific directory, return output or error token
git_in() {
    local dir="$1"
    shift
    git -C "$dir" "$@" 2>/dev/null
}

# Gather repo info for a local path
# Outputs: branch|ahead|behind|dirty|last_date|last_msg
gather_local_repo() {
    local path="$1"

    if [[ ! -d "$path/.git" ]]; then
        echo "ERR_NO_REPO||||"
        return
    fi

    local branch ahead behind dirty last_date last_msg remote_branch

    branch=$(git_in "$path" rev-parse --abbrev-ref HEAD)
    [[ -z "$branch" ]] && { echo "ERR_NO_BRANCH||||"; return; }

    remote_branch=$(git_in "$path" rev-parse --abbrev-ref "@{u}" 2>/dev/null)

    if [[ -n "$remote_branch" ]]; then
        # Fetch quietly so counts are fresh (skip if it takes too long)
        git_in "$path" fetch --quiet --no-tags 2>/dev/null &
        wait $! 2>/dev/null

        ahead=$(git_in "$path" rev-list --count "@{u}..HEAD" 2>/dev/null)
        behind=$(git_in "$path" rev-list --count "HEAD..@{u}" 2>/dev/null)
    fi
    ahead="${ahead:-0}"
    behind="${behind:-0}"

    dirty=$(git_in "$path" status --porcelain | wc -l | tr -d ' ')
    last_date=$(git_in "$path" log -1 --format="%cd" --date=format:"%Y-%m-%d %H:%M")
    last_msg=$(git_in "$path" log -1 --format="%s" | cut -c1-50)

    echo "${branch}|${ahead}|${behind}|${dirty}|${last_date}|${last_msg}"
}

# Build remote SSH script that gathers info for all remote repos
build_remote_script() {
    local paths=("$@")
    # Emit a self-contained bash snippet to run on the remote host
    printf 'set -o pipefail\n'
    for path in "${paths[@]}"; do
        printf 'if [ -d "%s/.git" ]; then\n' "$path"
        printf '  _b=$(git -C "%s" rev-parse --abbrev-ref HEAD 2>/dev/null)\n' "$path"
        printf '  _u=$(git -C "%s" rev-parse --abbrev-ref "@{u}" 2>/dev/null)\n' "$path"
        printf '  if [ -n "$_u" ]; then\n'
        printf '    git -C "%s" fetch --quiet --no-tags 2>/dev/null\n' "$path"
        printf '    _ah=$(git -C "%s" rev-list --count "@{u}..HEAD" 2>/dev/null)\n' "$path"
        printf '    _bh=$(git -C "%s" rev-list --count "HEAD..@{u}" 2>/dev/null)\n' "$path"
        printf '  fi\n'
        printf '  _ah=${_ah:-0}; _bh=${_bh:-0}\n'
        printf '  _d=$(git -C "%s" status --porcelain 2>/dev/null | wc -l | tr -d " ")\n' "$path"
        printf '  _ld=$(git -C "%s" log -1 --format="%%cd" --date=format:"%%Y-%%m-%%d %%H:%%M" 2>/dev/null)\n' "$path"
        printf '  _lm=$(git -C "%s" log -1 --format="%%s" 2>/dev/null | cut -c1-50)\n' "$path"
        printf '  echo "OK|${_b}|${_ah}|${_bh}|${_d}|${_ld}|${_lm}"\n'
        printf 'else\n'
        printf '  echo "ERR_NO_REPO||||"\n'
        printf 'fi\n'
    done
}

# Render sync badge string for ahead/behind values
sync_badge() {
    local ahead="$1"
    local behind="$2"
    if [[ "$ahead" == "ERR" || "$behind" == "ERR" ]]; then
        printf "${UNKNOWN} ${DIM}?/?${RESET}"
        return
    fi
    if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
        printf "${OK} ${GREEN}in sync${RESET}"
    elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
        printf "${WARN} ${CYAN}+${ahead} ahead${RESET}"
    elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
        printf "${WARN} ${YELLOW}-${behind} behind${RESET}"
    else
        printf "${FAIL} ${RED}+${ahead}/−${behind} diverged${RESET}"
    fi
}

# Print a single repo row
print_row() {
    local name="$1" branch="$2" ahead="$3" behind="$4" dirty="$5"
    local last_date="$6" last_msg="$7"

    local dirty_str=""
    if [[ "$dirty" -gt 0 ]]; then
        dirty_str=" ${YELLOW}(${dirty} dirty)${RESET}"
    fi

    local badge
    badge=$(sync_badge "$ahead" "$behind")

    printf "  ${BOLD}${WHITE}%-18s${RESET}" "$name"
    printf " ${CYAN}%-18s${RESET}" "$branch"
    printf " %-30b" "$badge"
    printf "${dirty_str}"
    printf "\n"
    printf "  ${DIM}%-18s${RESET} %s  %s\n" "" "$last_date" "$last_msg"
}

# Print section separator
print_divider() {
    printf "${DIM}%s${RESET}\n" "────────────────────────────────────────────────────────────────────────────"
}

# --- Main render loop ---
render() {
    clear

    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    printf "${BG_HEADER}${BOLD}${WHITE}  Git Sync Status${RESET}${BG_HEADER}%*s${RESET}\n" \
        $((58 - ${#timestamp})) "$timestamp  "
    echo ""

    local needs_attention=0
    local total_repos=0
    local synced_repos=0

    # ---- LOCAL (Sweep) ----
    printf "${BOLD}${CYAN}  Local (Sweep)${RESET}\n"
    print_divider

    declare -A local_results
    for name in "${LOCAL_ORDER[@]}"; do
        local_results["$name"]=$(gather_local_repo "${LOCAL_REPOS[$name]}")
    done

    for name in "${LOCAL_ORDER[@]}"; do
        local info="${local_results[$name]}"
        local branch ahead behind dirty last_date last_msg

        IFS='|' read -r branch ahead behind dirty last_date last_msg <<< "$info"

        ((total_repos++))
        if [[ "$branch" == ERR* ]]; then
            printf "  ${BOLD}${WHITE}%-18s${RESET} ${FAIL} ${RED}not a git repo${RESET}\n\n" "$name"
            ((needs_attention++))
            continue
        fi

        if [[ "$ahead" -gt 0 || "$behind" -gt 0 ]]; then
            ((needs_attention++))
        else
            ((synced_repos++))
        fi

        print_row "$name" "$branch" "$ahead" "$behind" "$dirty" "$last_date" "$last_msg"
        echo ""
    done

    echo ""

    # ---- REMOTE (DGX1) ----
    printf "${BOLD}${CYAN}  Remote (DGX1)${RESET}\n"
    print_divider

    # Build and run a single SSH session for all remote repos
    local remote_paths=()
    for name in "${REMOTE_ORDER[@]}"; do
        remote_paths+=("${REMOTE_REPOS[$name]}")
    done

    local remote_script
    remote_script=$(build_remote_script "${remote_paths[@]}")

    local ssh_output
    ssh_output=$(ssh_exec "$REMOTE_USER" "$REMOTE_HOST" "$REMOTE_PORT" "$REMOTE_KEY" \
        "bash -s" <<< "$remote_script")
    local ssh_exit=$?

    if [[ $ssh_exit -ne 0 ]]; then
        printf "  ${FAIL} ${BOLD}DGX1 unreachable${RESET} ${DIM}(SSH failed — exit ${ssh_exit})${RESET}\n"
        echo ""
    else
        local idx=0
        while IFS= read -r line; do
            local name="${REMOTE_ORDER[$idx]}"
            local status branch ahead behind dirty last_date last_msg

            IFS='|' read -r status branch ahead behind dirty last_date last_msg <<< "$line"

            ((total_repos++))
            if [[ "$status" != "OK" ]]; then
                printf "  ${BOLD}${WHITE}%-18s${RESET} ${FAIL} ${RED}not a git repo${RESET}\n\n" "$name"
                ((needs_attention++))
            else
                if [[ "$ahead" -gt 0 || "$behind" -gt 0 ]]; then
                    ((needs_attention++))
                else
                    ((synced_repos++))
                fi
                print_row "$name" "$branch" "$ahead" "$behind" "$dirty" "$last_date" "$last_msg"
                echo ""
            fi

            ((idx++))
        done <<< "$ssh_output"
    fi

    echo ""
    print_divider

    # ---- Summary ----
    if [[ $needs_attention -eq 0 && $total_repos -gt 0 ]]; then
        printf "  ${OK} ${GREEN}${BOLD}${synced_repos}/${total_repos} repos in sync${RESET}\n"
    elif [[ $total_repos -gt 0 ]]; then
        printf "  ${WARN} ${YELLOW}${BOLD}${synced_repos}/${total_repos} repos in sync${RESET}  ${DIM}(${needs_attention} need attention)${RESET}\n"
    fi

    printf "${DIM}  Refreshes every 60s — press Ctrl+C to stop${RESET}\n"
}

# --- Entry point ---
while true; do
    render
    sleep 60
done
