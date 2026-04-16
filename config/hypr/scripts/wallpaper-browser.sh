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
    local rel mtime hash thumb
    rel="${src#"$WALL_DIR"/}"
    mtime=$(stat -c %Y "$src")
    # Hash the relative path so "anime/1.jpg" and "nature/1.jpg" don't
    # collide on basename alone.
    hash=$(printf '%s' "$rel" | md5sum | cut -c1-10)
    thumb="$CACHE_DIR/${THUMB_W}x${THUMB_H}_${mtime}_${hash}.png"
    if [[ ! -f "$thumb" ]]; then
        # Purge any stale thumbs for this same source (different mtime).
        rm -f "$CACHE_DIR"/*"_${hash}.png" 2>/dev/null || true
        magick "$src" -resize "${THUMB_W}x${THUMB_H}^" \
            -gravity center -extent "${THUMB_W}x${THUMB_H}" \
            -strip "$thumb" 2>/dev/null || return 1
    fi
    echo "$thumb"
}

CURRENT_INDEX=""

# Recursively collect all image files from $WALL_DIR into the FILES array,
# so wallpapers organized into subfolders (e.g. Wallpaper/anime,
# Wallpaper/nature) are all picked up.
list_wallpapers() {
    find -L "$WALL_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        2>/dev/null | sort
}

# Display label: "folder/name" when nested, just "name" when at the top level.
label_for() {
    local path="$1" rel
    rel="${path#"$WALL_DIR"/}"
    if [[ "$rel" == */* ]]; then
        # Strip extension and use "folder/basename" form.
        local dir="${rel%/*}"
        local base="${rel##*/}"
        echo "$dir/${base%.*}"
    else
        local base="${rel##*/}"
        echo "${base%.*}"
    fi
}

build_entries() {
    mapfile -t FILES < <(list_wallpapers)

    if [[ ${#FILES[@]} -eq 0 ]]; then
        printf '(no wallpapers in %s)\n' "$WALL_DIR"
        return
    fi

    local current=""
    [[ -f "$HOME/.cache/hypr/current_wallpaper" ]] && \
        current=$(cat "$HOME/.cache/hypr/current_wallpaper")

    CURRENT_INDEX=""
    local i=0
    for f in "${FILES[@]}"; do
        local thumb label
        thumb=$(make_thumb "$f") || { i=$((i+1)); continue; }
        label=$(label_for "$f")
        [[ "$f" == "$current" ]] && CURRENT_INDEX="$i"
        printf '%s\0icon\x1f%s\n' "$label" "$thumb"
        i=$((i+1))
    done
}

resolve_file() {
    local choice="$1"
    local f
    for f in $(list_wallpapers); do
        if [[ "$(label_for "$f")" == "$choice" ]]; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

apply_wallpaper() {
    local path="$1" state="$2"
    local hypr_os_dir="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"

    # Rewrite hyprpaper.conf for all connected monitors and restart hyprpaper.
    # Mirrors the logic in scripts/wallpaper.sh, keeping both code paths in
    # sync on how the config is written.
    echo "$path" > "$HOME/.cache/hypr/current_wallpaper"

    local monitors
    monitors=$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
    [[ -z "$monitors" ]] && monitors="DP-3"

    {
        echo "splash = false"
        echo "ipc = on"
        echo ""
        while IFS= read -r mon; do
            [[ -z "$mon" ]] && continue
            echo "wallpaper {"
            echo "    monitor = $mon"
            echo "    path = $path"
            echo "}"
            echo ""
        done <<< "$monitors"
    } > "$hypr_os_dir/config/hypr/hyprpaper.conf"

    killall hyprpaper 2>/dev/null || true
    sleep 0.2
    (hyprpaper &>/dev/null &)

    if [[ "$state" == "on" ]]; then
        HYPR_OS_DIR="$hypr_os_dir" "$hypr_os_dir/scripts/theme.sh" "$path" \
            >/dev/null 2>&1 || true
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

    # Write entries to a temp file so we don't lose the \0 icon markers
    # to bash command substitution (which strips NUL bytes).
    ENTRIES_FILE=$(mktemp)
    trap 'rm -f "$ENTRIES_FILE"' EXIT
    build_entries > "$ENTRIES_FILE"

    ACTIVE_ARGS=()
    [[ -n "$CURRENT_INDEX" ]] && ACTIVE_ARGS=( -a "$CURRENT_INDEX" )

    set +e
    CHOICE=$(rofi -dmenu -i \
        -theme "$THEME_RASI" \
        -p "$PROMPT" \
        -format 's' \
        -matching fuzzy \
        -kb-custom-1 "Alt+t" \
        -kb-accept-entry "Return" \
        "${ACTIVE_ARGS[@]}" < "$ENTRIES_FILE")
    RC=$?
    set -e
    rm -f "$ENTRIES_FILE"

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
