#!/usr/bin/env bash

MUSIC_DIR="$HOME/.config/hypr/scripts/quickshell/music"
STATE_DIR="/tmp/lock-music"
CTRL="$HOME/.config/hypr/scripts/quickshell/music_control.sh"

mkdir -p "$STATE_DIR"

ls "$MUSIC_DIR"/*.mp3 > "$STATE_DIR/playlist" 2>/dev/null

mapfile -t SONGS < "$STATE_DIR/playlist" 2>/dev/null
TOTAL=${#SONGS[@]}

INDEX=$(cat "$STATE_DIR/index" 2>/dev/null || echo 0)
INDEX=$((INDEX % TOTAL))

echo "$INDEX" > "$STATE_DIR/index"
echo "${SONGS[$INDEX]}" > "$STATE_DIR/song"
basename "${SONGS[$INDEX]}" .mp3 > "$STATE_DIR/display-name"

# Don't start music — wait for user to press play in the lock screen
rm -f "$STATE_DIR/pid" "$STATE_DIR/paused"

quickshell -p ~/.config/hypr/scripts/quickshell/Lock.qml

# Stop music when user unlocks
kill "$(cat "$STATE_DIR/pid" 2>/dev/null)" 2>/dev/null
pkill pw-play 2>/dev/null
wait 2>/dev/null
