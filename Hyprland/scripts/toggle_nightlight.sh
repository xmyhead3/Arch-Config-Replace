#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# NIGHT LIGHT TOGGLE — Blue light filter via wlsunset
# -----------------------------------------------------------------------------
# Requires wlsunset package. Installs it if missing.
# State tracked in ~/.cache/qs_nightlight

CACHE_DIR="$HOME/.cache"
STATE_FILE="$CACHE_DIR/qs_nightlight"
PID_FILE="$CACHE_DIR/qs_nightlight_pid"

# Default temperature values (Kelvin)
NIGHT_TEMP=3500
DAY_TEMP=6500

# Check if wlsunset is installed
if ! command -v wlsunset &>/dev/null; then
    notify-send -a "Night Light" "Installing wlsunset..."
    if command -v yay &>/dev/null; then
        yay -S --noconfirm wlsunset 2>/dev/null
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm wlsunset 2>/dev/null
    fi
    # Re-check
    if ! command -v wlsunset &>/dev/null; then
        notify-send -u critical -a "Night Light" "Failed to install wlsunset" "Please install it manually: sudo pacman -S wlsunset"
        exit 1
    fi
fi

case "${1:-toggle}" in
    status)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "active"
        else
            echo "inactive"
        fi
        exit 0
        ;;
    on)
        # Check if already active
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            exit 0
        fi
        # Start wlsunset in background
        wlsunset -t "$NIGHT_TEMP" -T "$DAY_TEMP" &
        echo $! > "$PID_FILE"
        echo "active" > "$STATE_FILE"
        notify-send -a "Night Light" "🌙 Night Light On" "Warm tint applied (${NIGHT_TEMP}K)"
        ;;
    off)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null
            rm -f "$PID_FILE"
        fi
        echo "inactive" > "$STATE_FILE"
        notify-send -a "Night Light" "🌙 Night Light Off" "Normal color temperature restored"
        ;;
    temp)
        # Set custom night temperature
        if [ -n "$2" ]; then
            NIGHT_TEMP="$2"
            # Restart with new temp
            if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
                kill "$(cat "$PID_FILE")" 2>/dev/null
                wlsunset -t "$NIGHT_TEMP" -T "$DAY_TEMP" &
                echo $! > "$PID_FILE"
            fi
            echo "$NIGHT_TEMP" > "$CACHE_DIR/qs_nightlight_temp"
            notify-send -a "Night Light" "Temperature set to ${NIGHT_TEMP}K"
        fi
        ;;
    toggle|*)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            exec "$0" off
        else
            exec "$0" on
        fi
        ;;
esac
