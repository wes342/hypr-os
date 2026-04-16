#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Wallpaper -- pick random wallpaper,     │
# │  update hyprpaper.conf, and re-theme     │
# └──────────────────────────────────────────┘

set -euo pipefail

WALLPAPER_DIR="${HOME}/Pictures/Wallpaper"
CACHE_DIR="${HOME}/.cache/hypr"
CACHE_FILE="${CACHE_DIR}/current_wallpaper"
HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
CONFIG_DIR="$HYPR_OS_DIR/config"
THEME_SCRIPT="$HYPR_OS_DIR/scripts/theme.sh"

mkdir -p "$CACHE_DIR"

# If a specific wallpaper is passed, use it; otherwise pick random
if [[ -n "${1:-}" && -f "${1:-}" ]]; then
    WALLPAPER="$(realpath "$1")"
else
    # Get all image files
    mapfile -t WALLS < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)

    if [[ ${#WALLS[@]} -eq 0 ]]; then
        notify-send -t 3000 "Wallpaper" "No wallpapers found in $WALLPAPER_DIR" 2>/dev/null || true
        exit 1
    fi

    # Pick random, avoid repeating the current one if possible
    CURRENT=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
    TRIES=0
    while true; do
        WALLPAPER="${WALLS[$RANDOM % ${#WALLS[@]}]}"
        TRIES=$((TRIES + 1))
        [[ "$WALLPAPER" != "$CURRENT" || $TRIES -ge 5 ]] && break
    done
fi

# Save current wallpaper path
echo "$WALLPAPER" > "$CACHE_FILE"

echo "Setting wallpaper: $WALLPAPER"

# Get all connected monitor names
MONITORS=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null)
if [[ -z "$MONITORS" ]]; then
    MONITORS="DP-3"
fi

# Write hyprpaper.conf with new block syntax (v0.8+)
{
    echo "splash = false"
    echo "ipc = on"
    echo ""
    while IFS= read -r mon; do
        echo "wallpaper {"
        echo "    monitor = $mon"
        echo "    path = $WALLPAPER"
        echo "}"
        echo ""
    done <<< "$MONITORS"
} > "$CONFIG_DIR/hypr/hyprpaper.conf"

# Restart hyprpaper to pick up the new config
killall hyprpaper 2>/dev/null || true
sleep 0.3
hyprpaper &>/dev/null &
disown

# Generate and apply theme from the new wallpaper
if [[ -x "$THEME_SCRIPT" ]]; then
    bash "$THEME_SCRIPT" "$WALLPAPER"
else
    echo "Theme script not found at $THEME_SCRIPT"
fi
