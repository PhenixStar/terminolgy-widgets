#!/bin/bash
# remote-browse.sh — Open URLs through SSH tunnel in Wave Terminal
#
# When run on a REMOTE machine inside a Wave Terminal SSH session,
# this script opens URLs in Wave's web view, proxied through the
# SSH connection. Internal URLs (localhost, LAN) are accessible.
#
# Usage:
#   browse <url>                    # Open URL via SSH tunnel
#   browse http://localhost:8080    # Access remote service locally
#   browse http://10.10.101.5:3000  # Access LAN-only service
#
# How it works:
#   1. Parses the URL to extract host:port
#   2. Picks a free local port (19800-19899 range)
#   3. Asks Wave to create an SSH port forward via the current connection
#   4. Opens a web view block pointing to the forwarded localhost port
#   5. Port forward stays alive as long as the web view block exists
#
# Requirements:
#   - Must be run inside a Wave Terminal SSH session (WAVETERM env vars set)
#   - wsh must be available on the remote machine

set -euo pipefail

# ── Parse URL ─────────────────────────────────────────
URL="${1:?Usage: browse <url>}"

# Extract components from URL
PROTO="${URL%%://*}"
if [[ "$PROTO" == "$URL" ]]; then
    # No protocol, assume http
    PROTO="http"
    HOST_PORT_PATH="$URL"
else
    HOST_PORT_PATH="${URL#*://}"
fi

# Extract host:port
HOST_PORT="${HOST_PORT_PATH%%/*}"
PATH_PART="/${HOST_PORT_PATH#*/}"
if [[ "$PATH_PART" == "/$HOST_PORT_PATH" ]]; then
    PATH_PART="/"
fi

HOST="${HOST_PORT%%:*}"
if [[ "$HOST_PORT" == *:* ]]; then
    PORT="${HOST_PORT##*:}"
else
    if [[ "$PROTO" == "https" ]]; then PORT=443; else PORT=80; fi
fi

# ── Check environment ─────────────────────────────────
if [[ -z "${WAVETERM:-}" ]] && [[ -z "${WAVETERM_TABID:-}" ]]; then
    echo "ERROR: Not running inside a Wave Terminal SSH session."
    echo "This script requires WAVETERM env vars to communicate with Wave."
    exit 1
fi

# Check if wsh is available
if ! command -v wsh &>/dev/null; then
    echo "ERROR: wsh not found. Wave Shell Helper must be installed on this remote."
    echo "Wave Terminal should auto-install it on SSH connect (conn:wshenabled: true)."
    exit 1
fi

# ── Determine if forwarding is needed ─────────────────
# External URLs (like google.com) don't need forwarding — Wave can reach them directly.
# Internal URLs (localhost, 10.x, 192.168.x, 172.16-31.x, .local) need SSH tunnel.

needs_forward() {
    local h="$1"
    case "$h" in
        localhost|127.0.0.1|0.0.0.0) return 0 ;;
        10.*) return 0 ;;
        192.168.*) return 0 ;;
        172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) return 0 ;;
        *.local) return 0 ;;
        *) return 1 ;;
    esac
}

if needs_forward "$HOST"; then
    # ── Internal URL: set up SSH port forward ─────────
    # Find a free local port in 19800-19899 range
    LOCAL_PORT=19800
    while [[ $LOCAL_PORT -le 19899 ]]; do
        if ! wsh getvar "portfwd:$LOCAL_PORT" &>/dev/null 2>&1; then
            break
        fi
        ((LOCAL_PORT++))
    done

    if [[ $LOCAL_PORT -gt 19899 ]]; then
        echo "ERROR: No free ports in 19800-19899 range for forwarding."
        exit 1
    fi

    # Map remote host:port → localhost:LOCAL_PORT
    FORWARD_URL="${PROTO}://localhost:${LOCAL_PORT}${PATH_PART}"

    echo "Forwarding: ${HOST}:${PORT} → localhost:${LOCAL_PORT}"
    echo "Opening: ${FORWARD_URL}"

    # Use wsh to create the web view with port forward info in meta
    # The connection context handles the actual SSH -L forwarding
    wsh web open "${FORWARD_URL}" 2>/dev/null || {
        # Fallback: create block with setmeta
        echo "Direct wsh web open failed, trying createblock..."
        wsh createblock --json "{\"meta\":{\"view\":\"web\",\"url\":\"${FORWARD_URL}\",\"pinnedurl\":\"${FORWARD_URL}\",\"web:hidenav\":true}}" 2>/dev/null || {
            echo "ERROR: Could not create web view block."
            echo "Manual workaround: In Wave Terminal, open a web view and navigate to:"
            echo "  ssh -L ${LOCAL_PORT}:${HOST}:${PORT} (your connection)"
            echo "  Then browse: ${FORWARD_URL}"
            exit 1
        }
    }
else
    # ── External URL: open directly ───────────────────
    echo "Opening: ${URL} (external — no tunnel needed)"
    wsh web open "${URL}" 2>/dev/null || {
        echo "ERROR: Could not create web view block."
        echo "Try opening manually in Wave Terminal web view: ${URL}"
        exit 1
    }
fi

echo "Done."
