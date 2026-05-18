#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# CAFFEINE TOGGLE — Prevent system suspend
# -----------------------------------------------------------------------------
# When active, inhibits idle/suspend via systemd-inhibit.
# State tracked in ~/.cache/qs_caffeine

CACHE_DIR="$HOME/.cache"
STATE_FILE="$CACHE_DIR/qs_caffeine"
PID_FILE="$CACHE_DIR/qs_caffeine_pid"

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
        # Start systemd-inhibit in background
        systemd-inhibit --what=idle:sleep:shutdown \
            --who="WifeRice Caffeine" \
            --why="User requested no suspend" \
            sleep infinity &
        echo $! > "$PID_FILE"
        echo "active" > "$STATE_FILE"
        notify-send -a "Caffeine" "☕ Caffeine On" "System will not suspend"
        ;;
    off)
        if [ -f "$PID_FILE" ]; then
            kill "$(cat "$PID_FILE")" 2>/dev/null
            rm -f "$PID_FILE"
        fi
        echo "inactive" > "$STATE_FILE"
        notify-send -a "Caffeine" "☕ Caffeine Off" "System may suspend normally"
        ;;
    toggle|*)
        if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            exec "$0" off
        else
            exec "$0" on
        fi
        ;;
esac
