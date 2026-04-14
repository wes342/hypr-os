#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Wallpaper -- pick random wallpaper and  │
# │  apply it via hyprpaper + update theme   │
# └──────────────────────────────────────────┘

set -euo pipefail

WALLPAPER_DIR="${HOME}/Pictures/Wallpaper"
CACHE_DIR="${HOME}/.cache/hypr"
CACHE_FILE="${CACHE_DIR}/current_wallpaper"
HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
THEME_SCRIPT="$HYPR_OS_DIR/scripts/theme.sh"

mkdir -p "$CACHE_DIR"

# If a specific wallpaper is passed, use it; otherwise pick random
if [[ -n "${1:-}" && -f "${1:-}" ]]; then
    WALLPAPER="$1"
else
    # Get all image files
    mapfile -t WALLS < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)

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
        # Accept if different from current, or give up after 5 tries
        [[ "$WALLPAPER" != "$CURRENT" || $TRIES -ge 5 ]] && break
    done
fi

# Save current wallpaper path
echo "$WALLPAPER" > "$CACHE_FILE"

echo "Setting wallpaper: $WALLPAPER"

# Apply via hyprpaper using hyprctl
# Preload the new wallpaper, set it, then unload the old one
hyprctl hyprpaper preload "$WALLPAPER" 2>/dev/null
hyprctl hyprpaper wallpaper ",$WALLPAPER" 2>/dev/null
# Unload all previously loaded wallpapers except the current one
hyprctl hyprpaper unload all 2>/dev/null
hyprctl hyprpaper preload "$WALLPAPER" 2>/dev/null

# Generate and apply theme from the new wallpaper
if [[ -x "$THEME_SCRIPT" ]]; then
    bash "$THEME_SCRIPT" "$WALLPAPER"
else
    echo "Theme script not found at $THEME_SCRIPT"
fi
