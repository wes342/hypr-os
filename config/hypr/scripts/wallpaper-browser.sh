#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Wallpaper browser -- rofi grid of       │
# │  thumbnails. Tab toggles the "apply      │
# │  theme" state. Browser stays open after  │
# │  a selection so you can see the new      │
# │  theme and keep browsing; Esc to close.  │
# └──────────────────────────────────────────┘

set -euo pipefail

WALL_DIR="$HOME/Pictures/Wallpaper"
CACHE_DIR="$HOME/.cache/hypr-os/thumbs"
STATE_FILE="$HOME/.cache/hypr-os/wallpaper-browser.state"
THEME_RASI="$HOME/.config/rofi/wallpaper-browser.rasi"
# Rofi's element-icon is square, so square thumbs fill the tile with no
# letterboxing. We center-crop the source to keep the subject visible.
THUMB_W=400
THUMB_H=400

mkdir -p "$CACHE_DIR" "$(dirname "$STATE_FILE")"

[[ -f "$STATE_FILE" ]] || echo "on" > "$STATE_FILE"

make_thumb() {
    local src="$1"
    local name mtime thumb
    name=$(basename "$src")
    mtime=$(stat -c %Y "$src")
    thumb="$CACHE_DIR/${THUMB_W}x${THUMB_H}_${mtime}_${name%.*}.png"
    if [[ ! -f "$thumb" ]]; then
        rm -f "$CACHE_DIR"/*"_${name%.*}.png" 2>/dev/null || true
        magick "$src" -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity center -extent "${THUMB_W}x${THUMB_H}" \
            -strip "$thumb" 2>/dev/null || return 1
    fi
    echo "$thumb"
}

CURRENT_INDEX=""

build_entries() {
    shopt -s nullglob nocaseglob
    local files=( "$WALL_DIR"/*.{jpg,jpeg,png,webp} )
    shopt -u nullglob nocaseglob

    if [[ ${#files[@]} -eq 0 ]]; then
        printf '(no wallpapers in %s)\n' "$WALL_DIR"
        return
    fi

    local current=""
    [[ -f "$HOME/.cache/hypr/current_wallpaper" ]] && \
        current=$(cat "$HOME/.cache/hypr/current_wallpaper")

    CURRENT_INDEX=""
    local i=0
    for f in "${files[@]}"; do
        local thumb name
        thumb=$(make_thumb "$f") || { i=$((i+1)); continue; }
        name=$(basename "$f")
        [[ "$f" == "$current" ]] && CURRENT_INDEX="$i"
        printf '%s\0icon\x1f%s\n' "${name%.*}" "$thumb"
        i=$((i+1))
    done
}

resolve_file() {
    local choice="$1"
    shopt -s nullglob nocaseglob
    for f in "$WALL_DIR"/*.{jpg,jpeg,png,webp}; do
        local n; n=$(basename "$f")
        if [[ "${n%.*}" == "$choice" ]]; then
            echo "$f"
            shopt -u nullglob nocaseglob
            return 0
        fi
    done
    shopt -u nullglob nocaseglob
    return 1
}

apply_wallpaper() {
    local path="$1" state="$2"
    echo "$path" > "$HOME/.cache/hypr/current_wallpaper"
    if [[ "$state" == "on" ]]; then
        HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}" \
            "${HYPR_OS_DIR:-$HOME/dev/hypr-os}/scripts/theme.sh" "$path" \
            >/dev/null 2>&1
    else
        hyprctl hyprpaper preload "$path" >/dev/null 2>&1 || true
        hyprctl hyprpaper reload ",$path" >/dev/null 2>&1 || true
    fi
}

# ── Main loop: show rofi, act on result, reopen until user cancels ──
while true; do
    STATE=$(cat "$STATE_FILE")
    if [[ "$STATE" == "on" ]]; then
        PROMPT="[✓ re-theme]  Alt+t"
    else
        PROMPT="[ ] re-theme   Alt+t"
    fi

    # -kb-custom-1 Alt+t  → exits with code 10 when Alt+T is pressed.
    # Tab is reserved by rofi for row-tab, so we pick a free combo.
    # -a <idx> marks the currently-applied wallpaper with the "active" style.
    ENTRIES=$(build_entries)
    ACTIVE_ARGS=()
    [[ -n "$CURRENT_INDEX" ]] && ACTIVE_ARGS=( -a "$CURRENT_INDEX" )

    set +e
    CHOICE=$(printf '%s\n' "$ENTRIES" | rofi -dmenu -i \
        -theme "$THEME_RASI" \
        -p "$PROMPT" \
        -format 's' \
        -matching fuzzy \
        -kb-custom-1 "Alt+t" \
        -kb-accept-entry "Return" \
        "${ACTIVE_ARGS[@]}")
    RC=$?
    set -e

    case "$RC" in
        0)
            # A wallpaper was selected.
            [[ -z "$CHOICE" ]] && exit 0
            if SELECTED=$(resolve_file "$CHOICE"); then
                apply_wallpaper "$SELECTED" "$STATE"
            else
                notify-send -t 2500 "Wallpaper" "Couldn't resolve '$CHOICE'" 2>/dev/null || true
            fi
            # Loop: reopen so the user sees the new theme and can keep browsing.
            continue
            ;;
        10)
            # Tab pressed → flip toggle and reopen immediately.
            if [[ "$STATE" == "on" ]]; then
                echo "off" > "$STATE_FILE"
            else
                echo "on" > "$STATE_FILE"
            fi
            continue
            ;;
        *)
            # Esc / cancel (typically rc=1).
            exit 0
            ;;
    esac
done
