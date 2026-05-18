#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# DO NOT DISTURB TOGGLE — Suppress all notifications
# -----------------------------------------------------------------------------
# Sets a flag file that QuickShell's notification popup checks before showing.
# NotificationPopups.qml checks for "1" to suppress display.
# State tracked in ~/.cache/qs_dnd

CACHE_DIR="$HOME/.cache"
STATE_FILE="$CACHE_DIR/qs_dnd"

case "${1:-toggle}" in
    status)
        if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "1" ]; then
            echo "active"
        else
            echo "inactive"
        fi
        exit 0
        ;;
    on)
        echo "1" > "$STATE_FILE"
        notify-send -a "Do Not Disturb" "🔇 DND On" "All notifications suppressed"
        ;;
    off)
        echo "0" > "$STATE_FILE"
        notify-send -a "Do Not Disturb" "🔔 DND Off" "Notifications will appear normally"
        ;;
    toggle|*)
        if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "1" ]; then
            exec "$0" off
        else
            exec "$0" on
        fi
        ;;
esac
