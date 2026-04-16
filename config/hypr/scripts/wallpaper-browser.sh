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

thumb_path() {
    local src="$1"
    local rel mtime hash
    rel="${src#"$WALL_DIR"/}"
    mtime=$(stat -c %Y "$src")
    # Hash the relative path so "anime/1.jpg" and "nature/1.jpg" don't
    # collide on basename alone.
    hash=$(printf '%s' "$rel" | md5sum | cut -c1-10)
    echo "$CACHE_DIR/${THUMB_W}x${THUMB_H}_${mtime}_${hash}.png"
}

# Generate one thumb if missing. Safe to invoke from xargs -P.
generate_thumb() {
    local src="$1"
    local thumb; thumb=$(thumb_path "$src")
    [[ -f "$thumb" ]] && return 0
    local rel hash
    rel="${src#"$WALL_DIR"/}"
    hash=$(printf '%s' "$rel" | md5sum | cut -c1-10)
    # Purge stale thumbs for this source (different mtime, same hash).
    find "$CACHE_DIR" -maxdepth 1 -name "*_${hash}.png" -delete 2>/dev/null || true
    magick "$src" -resize "${THUMB_W}x${THUMB_H}^" \
        -gravity center -extent "${THUMB_W}x${THUMB_H}" \
        -strip "$thumb" 2>/dev/null
}
export -f thumb_path generate_thumb
export WALL_DIR CACHE_DIR THUMB_W THUMB_H

# Generate all missing thumbs in parallel. Called in the background
# on first open so rofi launches instantly; missing thumbnails
# appear blank in the current session but are cached for next open.
warm_thumbs() {
    local jobs; jobs=$(nproc); (( jobs > 16 )) && jobs=16
    list_wallpapers | xargs -r -d '\n' -P "$jobs" -I{} \
        bash -c 'generate_thumb "$1"' _ {} 2>/dev/null
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

    # Always fire a background warmer. It's idempotent -- existing
    # thumbs cost a stat, missing ones get generated in parallel. No
    # noticeable wait, and the next open shows every thumbnail.
    (warm_thumbs >/dev/null 2>&1 &)

    local current=""
    [[ -f "$HOME/.cache/hypr/current_wallpaper" ]] && \
        current=$(cat "$HOME/.cache/hypr/current_wallpaper")

    CURRENT_INDEX=""
    local i
    for i in "${!FILES[@]}"; do
        [[ "${FILES[$i]}" == "$current" ]] && { CURRENT_INDEX="$i"; break; }
    done

    # Single Python pass: compute thumb path per file and emit the
    # rofi dmenu line with or without \0icon\x1f. Way faster than the
    # equivalent bash loop, which forked stat+md5sum subshells per
    # file (98 files -> ~200 forks -> ~600ms). Python does it in ~15ms.
    printf '%s\n' "${FILES[@]}" | python3 -c '
import hashlib, os, sys
wd = os.environ["WALL_DIR"]
cd = os.environ["CACHE_DIR"]
w, h = os.environ["THUMB_W"], os.environ["THUMB_H"]
for line in sys.stdin:
    full = line.rstrip("\n")
    if not full: continue
    try:
        mtime = int(os.path.getmtime(full))
    except OSError:
        continue
    rel = os.path.relpath(full, wd)
    hh = hashlib.md5(rel.encode()).hexdigest()[:10]
    thumb = f"{cd}/{w}x{h}_{mtime}_{hh}.png"
    label = rel.rsplit(".", 1)[0]
    if os.path.exists(thumb):
        sys.stdout.write(f"{label}\0icon\x1f{thumb}\n")
    else:
        sys.stdout.write(f"{label}\n")
'
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
