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

# Read source mode from wallhaven.conf: local, wallhaven, or both.
SOURCE_MODE="local"
WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
[[ -f "$WH_CONF" ]] && {
    m=$(grep '^source=' "$WH_CONF" 2>/dev/null | cut -d= -f2)
    [[ -n "$m" ]] && SOURCE_MODE="$m"
}

# If a specific wallpaper is passed, use it; otherwise pick random
if [[ -n "${1:-}" && -f "${1:-}" ]]; then
    WALLPAPER="$(realpath "$1")"
else
    WALLPAPER=""

    # Try Wallhaven if source is wallhaven or both
    if [[ "$SOURCE_MODE" == "wallhaven" || "$SOURCE_MODE" == "both" ]]; then
        WH_PATH=$("$HYPR_OS_DIR/scripts/wallhaven.py" random 2>/dev/null) || true
        [[ -n "$WH_PATH" && -f "$WH_PATH" ]] && WALLPAPER="$WH_PATH"
    fi

    # Try local if source is local, both, or Wallhaven failed
    if [[ -z "$WALLPAPER" && "$SOURCE_MODE" != "wallhaven" ]] || \
       [[ -z "$WALLPAPER" && "$SOURCE_MODE" == "wallhaven" ]]; then
        mapfile -t WALLS < <(find "$WALLPAPER_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)

        if [[ ${#WALLS[@]} -eq 0 && -z "$WALLPAPER" ]]; then
            notify-send -t 3000 "Wallpaper" "No wallpapers found" 2>/dev/null || true
            exit 1
        fi

        if [[ ${#WALLS[@]} -gt 0 ]]; then
            CURRENT=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
            TRIES=0
            while true; do
                WALLPAPER="${WALLS[$RANDOM % ${#WALLS[@]}]}"
                TRIES=$((TRIES + 1))
                [[ "$WALLPAPER" != "$CURRENT" || $TRIES -ge 5 ]] && break
            done
        fi
    fi

    if [[ -z "$WALLPAPER" ]]; then
        notify-send -t 3000 "Wallpaper" "No wallpaper found from any source" 2>/dev/null || true
        exit 1
    fi
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
