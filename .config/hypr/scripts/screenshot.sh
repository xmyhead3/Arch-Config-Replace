#!/usr/bin/env bash

# Directories
SAVE_DIR="$HOME/Pictures/Screenshots"
RECORD_DIR="$HOME/Videos/Recordings"
mkdir -p "$SAVE_DIR"
mkdir -p "$RECORD_DIR"

# ---------------------------------------------------------
# SMART TOGGLE: STOP RECORDING IF RUNNING
# ---------------------------------------------------------
# If wl-screenrec is active, send SIGINT (Ctrl+C) to finalize the MP4 safely.
if pgrep -x "wl-screenrec" > /dev/null; then
    pkill -SIGINT -x "wl-screenrec"
    notify-send -a "Screen Recorder" "⏺ Recording Saved" "Saved to $RECORD_DIR"
    exit 0
fi

# Define timestamp for filenames
time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"
VID_FILENAME="$RECORD_DIR/Recording_$time.mp4"
CACHE_FILE="$HOME/.cache/qs_screenshot_geom"
MODE_CACHE_FILE="$HOME/.cache/qs_screenshot_mode"

# Parse arguments
EDIT_MODE=false
FULL_MODE=false
RECORD_MODE=false
GEOMETRY=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --edit) EDIT_MODE=true; shift ;;
        --full) FULL_MODE=true; shift ;;
        --record) RECORD_MODE=true; shift ;;
        --geometry) GEOMETRY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ---------------------------------------------------------
# PHASE 1: Execution (Instant Fullscreen OR Region Callback)
# ---------------------------------------------------------
if [ "$FULL_MODE" = true ] || [ -n "$GEOMETRY" ]; then
    
    # Mode: Screen Record
    if [ "$RECORD_MODE" = true ]; then
        if [ "$FULL_MODE" = true ]; then
            wl-screenrec -f "$VID_FILENAME" &
        else
            wl-screenrec -g "$GEOMETRY" -f "$VID_FILENAME" &
        fi
        notify-send -a "Screen Recorder" "⏺ Recording Started" "Press your screenshot shortcut again to stop."
        exit 0
    fi

    # Mode: Screenshot
    GRIM_CMD="grim -"
    if [ -n "$GEOMETRY" ]; then
        GRIM_CMD="grim -g \"$GEOMETRY\" -"
    fi

    if [ "$EDIT_MODE" = true ]; then
        eval $GRIM_CMD | GSK_RENDERER=gl satty --filename - --output-filename "$FILENAME" --init-tool brush --copy-command wl-copy
    else
        eval $GRIM_CMD | tee "$FILENAME" | wl-copy
    fi
    
    if [ -s "$FILENAME" ]; then
        notify-send -a "Screenshot" -i "$FILENAME" "Screenshot Saved" "File: Screenshot_$time.png\nFolder: $SAVE_DIR"
    fi
    exit 0
fi

# ---------------------------------------------------------
# PHASE 2: UI Trigger (Launch Standalone Quickshell Overlay)
# ---------------------------------------------------------
if [ "$EDIT_MODE" = true ]; then
    export QS_SCREENSHOT_EDIT="true"
else
    export QS_SCREENSHOT_EDIT="false"
fi

# Load previous geometry if it exists
if [ -f "$CACHE_FILE" ]; then
    export QS_CACHED_GEOM=$(cat "$CACHE_FILE")
else
    export QS_CACHED_GEOM=""
fi

# Load previous mode selection if it exists
if [ -f "$MODE_CACHE_FILE" ]; then
    export QS_CACHED_MODE=$(cat "$MODE_CACHE_FILE")
else
    export QS_CACHED_MODE="false"
fi

quickshell -p ~/.config/hypr/scripts/quickshell/ScreenshotOverlay.qml
