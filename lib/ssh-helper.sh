#!/usr/bin/env bash
# ssh-helper.sh — Shared SSH execution helper for WaveTerm widgets
# Source this file to get the ssh_exec function.

# ssh_exec <user> <host> <port> <key> <remote_command...>
#   Runs a remote command via SSH with hard 8s timeout and 5s connect timeout.
#   Suppresses SSH warnings. Returns empty string on failure (exit code preserved).
#   Usage: output=$(ssh_exec "$USER" "$HOST" "$PORT" "$KEY" "echo hello")
ssh_exec() {
    local user="$1"
    local host="$2"
    local port="$3"
    local key="$4"
    shift 4

    timeout 8 ssh \
        -i "${key}" \
        -p "${port}" \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new \
        -o LogLevel=ERROR \
        -o ServerAliveInterval=4 \
        -o ServerAliveCountMax=1 \
        "${user}@${host}" \
        "$@" 2>/dev/null
}
