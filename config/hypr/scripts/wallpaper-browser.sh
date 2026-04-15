#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Wallpaper browser -- rofi grid of       │
# │  thumbnails. First entry toggles whether │
# │  selecting a wallpaper also re-themes.   │
# └──────────────────────────────────────────┘

set -euo pipefail

WALL_DIR="$HOME/Pictures/Wallpaper"
CACHE_DIR="$HOME/.cache/hypr-os/thumbs"
STATE_FILE="$HOME/.cache/hypr-os/wallpaper-browser.state"
THEME_RASI="$HOME/.config/rofi/wallpaper-browser.rasi"
THUMB_W=320
THUMB_H=180

mkdir -p "$CACHE_DIR" "$(dirname "$STATE_FILE")"

# State: "on" (re-theme on select) or "off" (wallpaper only).
if [[ ! -f "$STATE_FILE" ]]; then
    echo "on" > "$STATE_FILE"
fi
THEME_STATE=$(cat "$STATE_FILE")

# ── Thumbnail generation (cached, keyed on mtime) ──
make_thumb() {
    local src="$1"
    local name
    name=$(basename "$src")
    local mtime
    mtime=$(stat -c %Y "$src")
    local thumb="$CACHE_DIR/${mtime}_${name%.*}.png"

    if [[ ! -f "$thumb" ]]; then
        # Clean stale thumbs for this source so the cache doesn't grow forever.
        rm -f "$CACHE_DIR"/*"_${name%.*}.png" 2>/dev/null || true
        magick "$src" -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity center -extent "${THUMB_W}x${THUMB_H}" \
            -strip "$thumb" 2>/dev/null || return 1
    fi
    echo "$thumb"
}

# ── Build rofi input ──
# Rofi's dmenu icon syntax: "LABEL\0icon\x1f/path/to/image.png"
build_entries() {
    # Toggle row first.
    local toggle_icon
    if [[ "$THEME_STATE" == "on" ]]; then
        toggle_icon="color-picker"     # a built-in icon name that usually resolves
        printf '󰏘  Update theme: ON  (click to turn OFF)\n'
    else
        printf '󰏘  Update theme: OFF (click to turn ON)\n'
    fi

    # Wallpapers.
    shopt -s nullglob nocaseglob
    local files=( "$WALL_DIR"/*.{jpg,jpeg,png,webp} )
    shopt -u nullglob nocaseglob

    if [[ ${#files[@]} -eq 0 ]]; then
        printf '(no wallpapers in %s)\n' "$WALL_DIR"
        return
    fi

    for f in "${files[@]}"; do
        local thumb
        thumb=$(make_thumb "$f") || continue
        local name
        name=$(basename "$f")
        # Strip extension for display.
        printf '%s\0icon\x1f%s\n' "${name%.*}" "$thumb"
    done
}

# ── Launch rofi ──
CHOICE=$(build_entries | rofi -dmenu -i \
    -theme "$THEME_RASI" \
    -p "Wallpaper" \
    -format 's' \
    -matching fuzzy)

[[ -z "$CHOICE" ]] && exit 0

# ── Handle toggle row ──
if [[ "$CHOICE" == *"Update theme:"* ]]; then
    if [[ "$THEME_STATE" == "on" ]]; then
        echo "off" > "$STATE_FILE"
    else
        echo "on" > "$STATE_FILE"
    fi
    # Re-open the browser so the user sees the new state.
    exec "$0"
fi

# ── Resolve choice back to a real file ──
# CHOICE is the basename without extension; find the matching file.
SELECTED=""
shopt -s nullglob nocaseglob
for f in "$WALL_DIR"/*.{jpg,jpeg,png,webp}; do
    n=$(basename "$f")
    if [[ "${n%.*}" == "$CHOICE" ]]; then
        SELECTED="$f"
        break
    fi
done
shopt -u nullglob nocaseglob

if [[ -z "$SELECTED" ]]; then
    notify-send -t 3000 "Wallpaper" "Couldn't resolve '$CHOICE'" 2>/dev/null
    exit 1
fi

# ── Apply ──
echo "$SELECTED" > "$HOME/.cache/hypr/current_wallpaper"

if [[ "$THEME_STATE" == "on" ]]; then
    # theme.sh also reloads hyprpaper/waybar/swaync.
    HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}" \
        "${HYPR_OS_DIR:-$HOME/dev/hypr-os}/scripts/theme.sh" "$SELECTED" >/dev/null 2>&1 &
    notify-send -t 2500 "Wallpaper" "Applied with new theme: $(basename "$SELECTED")" 2>/dev/null || true
else
    # Just swap the wallpaper without touching colors.
    hyprctl hyprpaper reload ",$SELECTED" >/dev/null 2>&1 || {
        # hyprpaper needs the image preloaded first
        hyprctl hyprpaper preload "$SELECTED" >/dev/null 2>&1 || true
        hyprctl hyprpaper reload ",$SELECTED" >/dev/null 2>&1 || true
    }
    notify-send -t 2500 "Wallpaper" "Applied: $(basename "$SELECTED")" 2>/dev/null || true
fi
