#!/usr/bin/env bash

FLAG="$HOME/.cache/wallpaper_initialized"
RELOAD_SCRIPT_PATH="$HOME/.config/hypr/scripts/quickshell/wallpaper/matugen_reload.sh"

[ -f "$FLAG" ] && exit 0

sleep 0.2

file=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | shuf -n 1)

if [ -n "$file" ]; then
    cp "$file" /tmp/lock_bg.png
    
    awww img "$file" --transition-type any --transition-pos 0.5,0.5 --transition-fps 144 --transition-duration 1 &
    
    if matugen image "$file" --source-color-index 0; then
        if [ -f "$RELOAD_SCRIPT_PATH" ]; then
            bash "$RELOAD_SCRIPT_PATH"
        fi
    fi
fi

mkdir -p "$(dirname "$FLAG")"
touch "$FLAG"
