#!/usr/bin/env bash
PIPE="/tmp/qs_audio_wait_$$.fifo"
mkfifo "$PIPE" 2>/dev/null

trap 'rm -f "$PIPE"; kill $MONITOR_PID 2>/dev/null; exit 0' EXIT INT TERM

LC_ALL=C pactl subscribe 2>/dev/null > "$PIPE" &
MONITOR_PID=$!

# Fallback timeout: re-poll every 2s even if pactl misses wpctl events
timeout 2 grep -m 1 -E "sink|server" < "$PIPE" > /dev/null 2>&1
