#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Wallpaper -- pick random wallpaper,     │
# │  update compositor wallpaper and theme   │
# └──────────────────────────────────────────┘

set -euo pipefail

WALLPAPER_DIR="${HOME}/Pictures/Wallpaper"
CACHE_DIR="${HOME}/.cache/hypr"
CACHE_FILE="${CACHE_DIR}/current_wallpaper"
HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
CONFIG_DIR="$HYPR_OS_DIR/config"
THEME_SCRIPT="$HYPR_OS_DIR/scripts/theme.sh"
COMPOSITOR="${HYPR_OS_DESKTOP:-}"

if [[ -z "$COMPOSITOR" ]]; then
    if [[ -n "${SWAYSOCK:-}" ]]; then
        COMPOSITOR="sway"
    else
        COMPOSITOR="hyprland"
    fi
fi

mkdir -p "$CACHE_DIR"

# --restore flag: reuse last wallpaper instead of picking random
RESTORE=false
if [[ "${1:-}" == "--restore" ]]; then
    RESTORE=true
    shift
fi

# Read source mode from wallhaven.conf: local, wallhaven, or both.
SOURCE_MODE="local"
WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
[[ -f "$WH_CONF" ]] && {
    m=$(grep '^source=' "$WH_CONF" 2>/dev/null | cut -d= -f2)
    [[ -n "$m" ]] && SOURCE_MODE="$m"
}

# If restoring, use cached wallpaper from last session
if [[ "$RESTORE" == true && -f "$CACHE_FILE" ]]; then
    CACHED=$(cat "$CACHE_FILE" 2>/dev/null)
    if [[ -n "$CACHED" && -f "$CACHED" ]]; then
        WALLPAPER="$CACHED"
    fi
fi

# If a specific wallpaper is passed, use it; otherwise pick random
if [[ -n "${WALLPAPER:-}" ]]; then
    : # already set by --restore
elif [[ -n "${1:-}" && -f "${1:-}" ]]; then
    WALLPAPER="$(realpath "$1")"
else
    WALLPAPER=""

    # Read local folder filter
    LOCAL_DIR="$WALLPAPER_DIR"
    [[ -f "$WH_CONF" ]] && {
        LOCAL_FOLDER=$(grep '^local_folder=' "$WH_CONF" 2>/dev/null | cut -d= -f2)
        [[ -n "$LOCAL_FOLDER" && -d "$WALLPAPER_DIR/$LOCAL_FOLDER" ]] && LOCAL_DIR="$WALLPAPER_DIR/$LOCAL_FOLDER"
    }

    if [[ "$SOURCE_MODE" == "both" ]]; then
        # Both: 50/50 coin flip between local and wallhaven
        mapfile -t WALLS < <(find "$LOCAL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)
        COIN=$((RANDOM % 2))

        if [[ $COIN -eq 0 && ${#WALLS[@]} -gt 0 ]]; then
            # Pick random local
            CURRENT=$(cat "$CACHE_FILE" 2>/dev/null || echo "")
            TRIES=0
            while true; do
                WALLPAPER="${WALLS[$RANDOM % ${#WALLS[@]}]}"
                TRIES=$((TRIES + 1))
                [[ "$WALLPAPER" != "$CURRENT" || $TRIES -ge 5 ]] && break
            done
        else
            # Pick from wallhaven
            WH_PATH=$("$HYPR_OS_DIR/scripts/wallhaven.py" random 2>/dev/null) || true
            [[ -n "$WH_PATH" && -f "$WH_PATH" ]] && WALLPAPER="$WH_PATH"
        fi

        # Fallback: if chosen source failed, try the other
        if [[ -z "$WALLPAPER" && ${#WALLS[@]} -gt 0 ]]; then
            WALLPAPER="${WALLS[$RANDOM % ${#WALLS[@]}]}"
        elif [[ -z "$WALLPAPER" ]]; then
            WH_PATH=$("$HYPR_OS_DIR/scripts/wallhaven.py" random 2>/dev/null) || true
            [[ -n "$WH_PATH" && -f "$WH_PATH" ]] && WALLPAPER="$WH_PATH"
        fi

    elif [[ "$SOURCE_MODE" == "wallhaven" ]]; then
        # Wallhaven only
        WH_PATH=$("$HYPR_OS_DIR/scripts/wallhaven.py" random 2>/dev/null) || true
        [[ -n "$WH_PATH" && -f "$WH_PATH" ]] && WALLPAPER="$WH_PATH"

    else
        # Local only (respects folder filter)
        mapfile -t WALLS < <(find "$LOCAL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)
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

    # Fall back to bundled default if nothing found
    if [[ -z "$WALLPAPER" ]]; then
        default_wp="$CONFIG_DIR/wallpapers/default.jpg"
        if [[ -f "$default_wp" ]]; then
            WALLPAPER="$(realpath "$default_wp")"
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

if [[ "$COMPOSITOR" == "sway" ]]; then
    mkdir -p "$CONFIG_DIR/sway"
    printf 'output * bg "%s" fill\n' "$WALLPAPER" > "$CONFIG_DIR/sway/wallpaper.conf"
    pkill -x swaybg 2>/dev/null || true
    sleep 0.2
    swaybg -m fill -i "$WALLPAPER" &>/dev/null &
    disown
else
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
fi

# Generate and apply theme from the new wallpaper
if [[ -x "$THEME_SCRIPT" ]]; then
    bash "$THEME_SCRIPT" "$WALLPAPER"
else
    echo "Theme script not found at $THEME_SCRIPT"
fi

# Pre-generate blurred wallpaper for launcher (background, non-blocking)
BLUR_CACHE="$HOME/.cache/hypr-os/wallpaper-blur.png"
magick "$WALLPAPER" -resize 800x600^ -gravity center -extent 800x600 \
    -blur 0x10 -brightness-contrast -20x-10 "$BLUR_CACHE" 2>/dev/null &
