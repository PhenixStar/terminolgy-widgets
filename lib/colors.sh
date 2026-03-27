#!/usr/bin/env bash
# colors.sh — Shared ANSI color/style library for WaveTerm widgets

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# Additional colors used across scripts
GRAY='\033[0;90m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BG_HEADER='\033[48;5;235m'

# Status icons
OK="${GREEN}●${RESET}"
WARN="${YELLOW}●${RESET}"
FAIL="${RED}●${RESET}"
UNKNOWN="${DIM}○${RESET}"
