#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Unified wallpaper browser -- local +    │
# │  Wallhaven in one rofi grid.             │
# │                                          │
# │  Alt+l  → local tab                     │
# │  Alt+w  → wallhaven tab                 │
# │  Alt+t  → toggle re-theme               │
# │  Alt+s  → settings                       │
# │  Alt+n  → next page (wallhaven)          │
# │  Alt+p  → prev page (wallhaven)          │
# │  Esc    → close                          │
# └──────────────────────────────────────────┘

set -euo pipefail

WALL_DIR="$HOME/Pictures/Wallpaper"
CACHE_DIR="$HOME/.cache/hypr-os/thumbs"
STATE_FILE="$HOME/.cache/hypr-os/wallpaper-browser.state"
MODE_FILE="$HOME/.cache/hypr-os/wallpaper-browser.mode"
THEME_RASI="$HOME/.config/rofi/wallpaper-browser.rasi"
HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
WALLHAVEN_PY="$HYPR_OS_DIR/scripts/wallhaven.py"
WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
THUMB_W=400
THUMB_H=400
WH_PAGE=1
WH_QUERY=""

mkdir -p "$CACHE_DIR" "$(dirname "$STATE_FILE")"

[[ -f "$STATE_FILE" ]] || echo "on" > "$STATE_FILE"

# Source mode: local, wallhaven, both. Read from wallhaven.conf or
# fall back to a persistent cache file.
read_mode() {
    if [[ -f "$HOME/.config/hypr-os/wallhaven.conf" ]]; then
        local m
        m=$(grep '^source=' "$HOME/.config/hypr-os/wallhaven.conf" 2>/dev/null | cut -d= -f2)
        [[ -n "$m" ]] && { echo "$m"; return; }
    fi
    [[ -f "$MODE_FILE" ]] && cat "$MODE_FILE" || echo "local"
}

write_mode() {
    local m="$1"
    echo "$m" > "$MODE_FILE"
    # Also persist to wallhaven.conf
    local conf="$HOME/.config/hypr-os/wallhaven.conf"
    if [[ -f "$conf" ]]; then
        sed -i "s/^source=.*/source=$m/" "$conf"
    else
        python3 "$WALLHAVEN_PY" settings >/dev/null 2>&1 || true
        [[ -f "$conf" ]] && sed -i "s/^source=.*/source=$m/" "$conf"
    fi
}

# ── Local thumb helpers (unchanged from before) ──

export WALL_DIR CACHE_DIR THUMB_W THUMB_H

thumb_path() {
    local src="$1" rel mtime hash
    rel="${src#"$WALL_DIR"/}"
    mtime=$(stat -c %Y "$src")
    hash=$(printf '%s' "$rel" | md5sum | cut -c1-10)
    echo "$CACHE_DIR/${THUMB_W}x${THUMB_H}_${mtime}_${hash}.png"
}
generate_thumb() {
    local src="$1" thumb
    thumb=$(thumb_path "$src")
    [[ -f "$thumb" ]] && return 0
    local rel hash
    rel="${src#"$WALL_DIR"/}"
    hash=$(printf '%s' "$rel" | md5sum | cut -c1-10)
    find "$CACHE_DIR" -maxdepth 1 -name "*_${hash}.png" -delete 2>/dev/null || true
    magick "$src" -resize "${THUMB_W}x${THUMB_H}^" \
        -gravity center -extent "${THUMB_W}x${THUMB_H}" \
        -strip "$thumb" 2>/dev/null
}
export -f thumb_path generate_thumb

warm_thumbs() {
    local jobs; jobs=$(nproc); (( jobs > 16 )) && jobs=16
    list_wallpapers | xargs -r -d '\n' -P "$jobs" -I{} \
        bash -c 'generate_thumb "$1"' _ {} 2>/dev/null
}

list_wallpapers() {
    find -L "$WALL_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        2>/dev/null | sort
}

CURRENT_INDEX=""

build_local_entries() {
    mapfile -t FILES < <(list_wallpapers)
    [[ ${#FILES[@]} -eq 0 ]] && { printf '(no local wallpapers)\n'; return; }
    (warm_thumbs >/dev/null 2>&1 &)

    local current=""
    [[ -f "$HOME/.cache/hypr/current_wallpaper" ]] && \
        current=$(cat "$HOME/.cache/hypr/current_wallpaper")
    CURRENT_INDEX=""
    for i in "${!FILES[@]}"; do
        [[ "${FILES[$i]}" == "$current" ]] && { CURRENT_INDEX="$i"; break; }
    done

    printf '%s\n' "${FILES[@]}" | python3 -c '
import hashlib, os, sys
wd = os.environ["WALL_DIR"]; cd = os.environ["CACHE_DIR"]
w, h = os.environ["THUMB_W"], os.environ["THUMB_H"]
for line in sys.stdin:
    full = line.rstrip("\n")
    if not full: continue
    try: mtime = int(os.path.getmtime(full))
    except OSError: continue
    rel = os.path.relpath(full, wd)
    hh = hashlib.md5(rel.encode()).hexdigest()[:10]
    thumb = f"{cd}/{w}x{h}_{mtime}_{hh}.png"
    label = rel.rsplit(".", 1)[0]
    if os.path.exists(thumb): sys.stdout.write(f"{label}\0icon\x1f{thumb}\n")
    else: sys.stdout.write(f"{label}\n")
'
}

build_wallhaven_entries() {
    local args=(search)
    [[ -n "$WH_QUERY" ]] && args+=(--query "$WH_QUERY")
    (( WH_PAGE > 1 )) && args+=(--page "$WH_PAGE")
    CURRENT_INDEX=""
    python3 "$WALLHAVEN_PY" "${args[@]}" 2>/dev/null
}

resolve_local() {
    local choice="$1" f
    for f in $(list_wallpapers); do
        local rel="${f#"$WALL_DIR"/}"
        if [[ "${rel%.*}" == "$choice" ]]; then
            echo "$f"; return 0
        fi
    done
    return 1
}

resolve_wallhaven() {
    local choice="$1"
    # choice format: "wallhaven-xxxxx  2560x1440  general"
    local wid="${choice%%  *}"
    wid="${wid// /}"

    # Get full image URL from API
    local full_url
    full_url=$(python3 "$WALLHAVEN_PY" resolve "$wid" 2>/dev/null) || {
        notify-send -t 2500 "Wallhaven" "Failed to resolve $wid" 2>/dev/null || true
        return 1
    }

    # Download full image
    local path
    path=$(python3 "$WALLHAVEN_PY" download "$full_url" 2>/dev/null) || {
        notify-send -t 2500 "Wallhaven" "Download failed" 2>/dev/null || true
        return 1
    }
    echo "$path"
}

apply_wallpaper() {
    local path="$1" state="$2"
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
    } > "$HYPR_OS_DIR/config/hypr/hyprpaper.conf"

    killall hyprpaper 2>/dev/null || true
    sleep 0.2
    (hyprpaper &>/dev/null &)

    if [[ "$state" == "on" ]]; then
        HYPR_OS_DIR="$HYPR_OS_DIR" "$HYPR_OS_DIR/scripts/theme.sh" "$path" \
            >/dev/null 2>&1 || true
    fi
}

# ── Settings submenu ──

SETTINGS_RASI="$HOME/.config/rofi/settings.rasi"

# Read a single value from wallhaven.conf
conf_get() {
    grep "^$1=" "$WH_CONF" 2>/dev/null | cut -d= -f2
}
conf_set() {
    sed -i "s/^$1=.*/$1=$2/" "$WH_CONF"
}

# Helper: rofi single-select from a list of options
rofi_pick() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | rofi -dmenu -i -theme "$SETTINGS_RASI" -p "$prompt"
}

# Helper: rofi text input with current value pre-filled
rofi_input() {
    local prompt="$1" current="$2"
    echo "$current" | rofi -dmenu -theme "$SETTINGS_RASI" -p "$prompt"
}

# Decode categories bitmask to human labels
cat_label() {
    local c="$1" out=""
    [[ "${c:0:1}" == "1" ]] && out+="General " || out+="ꞏꞏꞏꞏꞏꞏꞏ "
    [[ "${c:1:1}" == "1" ]] && out+="Anime " || out+="ꞏꞏꞏꞏꞏ "
    [[ "${c:2:1}" == "1" ]] && out+="People" || out+="ꞏꞏꞏꞏꞏꞏ"
    echo "$out"
}

# Decode purity bitmask
pur_label() {
    local p="$1" out=""
    [[ "${p:0:1}" == "1" ]] && out+="SFW " || out+="ꞏꞏꞏ "
    [[ "${p:1:1}" == "1" ]] && out+="Sketchy " || out+="ꞏꞏꞏꞏꞏꞏꞏ "
    [[ "${p:2:1}" == "1" ]] && out+="NSFW" || out+="ꞏꞏꞏꞏ"
    echo "$out"
}

toggle_bit() {
    local val="$1" pos="$2"
    local c="${val:$pos:1}"
    if [[ "$c" == "1" ]]; then c="0"; else c="1"; fi
    echo "${val:0:$pos}${c}${val:$((pos+1))}"
}

run_settings() {
    # Ensure config exists
    python3 "$WALLHAVEN_PY" settings >/dev/null 2>&1
    WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
    [[ -f "$WH_CONF" ]] || return

    while true; do
        local source=$(conf_get source)
        local sorting=$(conf_get sorting)
        local categories=$(conf_get categories)
        local purity=$(conf_get purity)
        local atleast=$(conf_get atleast)
        local ratios=$(conf_get ratios)
        local query=$(conf_get query)
        local api_key=$(conf_get api_key)

        local source_icon=""
        case "$source" in
            local)     source_icon="📁 Local only" ;;
            wallhaven) source_icon="🌐 Wallhaven only" ;;
            both)      source_icon="📁+🌐 Both" ;;
        esac

        local key_status="not set"
        [[ -n "$api_key" ]] && key_status="configured ✓"

        local entries=""
        entries+="───────── Source ─────────"$'\n'
        entries+="  󰉌  Source          $source_icon"$'\n'
        entries+=""$'\n'
        entries+="───────── Search ─────────"$'\n'
        entries+="  󰍉  Search query    ${query:-  (none)}"$'\n'
        entries+="  󰒺  Sorting         $sorting"$'\n'
        entries+=""$'\n'
        entries+="───────── Filters ────────"$'\n'
        entries+="  󰉋  Categories      $(cat_label "$categories")"$'\n'
        entries+="  󰒃  Purity          $(pur_label "$purity")"$'\n'
        entries+="  󰍹  Min resolution  $atleast"$'\n'
        entries+="  󰢮  Aspect ratio    $ratios"$'\n'
        entries+=""$'\n'
        entries+="───────── Account ────────"$'\n'
        entries+="  󰌆  API key         $key_status"$'\n'
        entries+=""$'\n'
        entries+="  󰄬  Done"

        local choice
        choice=$(printf '%s' "$entries" | rofi -dmenu -i \
            -theme "$SETTINGS_RASI" -p "⚙ Wallhaven Settings" \
            -matching fuzzy) || return

        case "$choice" in
            *Done*) return ;;
            *Source*)
                local new
                new=$(rofi_pick "󰉌 Source" \
                    "📁  local        Use wallpapers from ~/Pictures/Wallpaper" \
                    "🌐  wallhaven    Fetch from wallhaven.cc API" \
                    "📁+🌐  both        Local + Wallhaven combined") || continue
                case "$new" in
                    *local*)     conf_set source local; write_mode local ;;
                    *wallhaven*) conf_set source wallhaven; write_mode wallhaven ;;
                    *both*)      conf_set source both; write_mode both ;;
                esac
                ;;
            *"Search query"*)
                local new
                new=$(rofi_input "󰍉 Search query" "$query") || continue
                conf_set query "$new"
                ;;
            *Sorting*)
                local new
                new=$(rofi_pick "󰒺 Sorting" \
                    "random       Shuffled results" \
                    "toplist      Most popular" \
                    "hot          Trending now" \
                    "latest       Newest uploads" \
                    "relevance    Best match for query") || continue
                new="${new%% *}"
                conf_set sorting "$new"
                ;;
            *Categories*)
                # Toggle loop
                local cats="$categories"
                while true; do
                    local pick
                    pick=$(rofi_pick "󰉋 Toggle categories (current: $(cat_label "$cats"))" \
                        "$( [[ ${cats:0:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  General" \
                        "$( [[ ${cats:1:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  Anime" \
                        "$( [[ ${cats:2:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  People" \
                        "  Apply") || break
                    case "$pick" in
                        *General*) cats=$(toggle_bit "$cats" 0) ;;
                        *Anime*)   cats=$(toggle_bit "$cats" 1) ;;
                        *People*)  cats=$(toggle_bit "$cats" 2) ;;
                        *Apply*)   break ;;
                    esac
                done
                conf_set categories "$cats"
                ;;
            *Purity*)
                local pur="$purity"
                while true; do
                    local pick
                    pick=$(rofi_pick "󰒃 Toggle purity (current: $(pur_label "$pur"))" \
                        "$( [[ ${pur:0:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  SFW" \
                        "$( [[ ${pur:1:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  Sketchy" \
                        "$( [[ ${pur:2:1} == 1 ]] && echo '󰄲' || echo '󰄮' )  NSFW (needs API key)" \
                        "  Apply") || break
                    case "$pick" in
                        *SFW*)     pur=$(toggle_bit "$pur" 0) ;;
                        *Sketchy*) pur=$(toggle_bit "$pur" 1) ;;
                        *NSFW*)    pur=$(toggle_bit "$pur" 2) ;;
                        *Apply*)   break ;;
                    esac
                done
                conf_set purity "$pur"
                ;;
            *"Min resolution"*)
                local new
                new=$(rofi_pick "󰍹 Minimum resolution" \
                    "2560x1440    1440p" \
                    "3840x2160    4K" \
                    "1920x1080    1080p" \
                    "any          No minimum") || continue
                new="${new%% *}"
                [[ "$new" == "any" ]] && new=""
                conf_set atleast "$new"
                ;;
            *"Aspect ratio"*)
                local new
                new=$(rofi_pick "󰢮 Aspect ratio" \
                    "16x9         Widescreen" \
                    "21x9         Ultrawide" \
                    "16x10        MacBook-style" \
                    "any          No filter") || continue
                new="${new%% *}"
                [[ "$new" == "any" ]] && new=""
                conf_set ratios "$new"
                ;;
            *"API key"*)
                local new
                new=$(rofi_input "󰌆 API key (from wallhaven.cc/settings)" "$api_key") || continue
                conf_set api_key "$new"
                ;;
        esac
    done
}

# ── Main loop ──

MODE=$(read_mode)

while true; do
    STATE=$(cat "$STATE_FILE")

    local_icon=""; wh_icon=""
    case "$MODE" in
        local)     local_icon="󰄲"; wh_icon="󰄮" ;;
        wallhaven) local_icon="󰄮"; wh_icon="󰄲" ;;
        both)      local_icon="󰄲"; wh_icon="󰄲" ;;
    esac

    if [[ "$STATE" == "on" ]]; then
        theme_indicator="✓theme"
    else
        theme_indicator="☐theme"
    fi

    case "$MODE" in
        local)     mode_label="📁 Local" ;;
        wallhaven) mode_label="🌐 Wallhaven (p$WH_PAGE)" ;;
        both)      mode_label="📁+🌐 Both" ;;
    esac

    PROMPT="$mode_label  [$theme_indicator]  l/w:Alt  t:theme  s:set"

    # Build entries based on mode
    ENTRIES_FILE=$(mktemp)
    trap 'rm -f "$ENTRIES_FILE"' EXIT

    case "$MODE" in
        local)
            build_local_entries > "$ENTRIES_FILE"
            ;;
        wallhaven)
            build_wallhaven_entries > "$ENTRIES_FILE"
            ;;
        both)
            build_local_entries > "$ENTRIES_FILE"
            build_wallhaven_entries >> "$ENTRIES_FILE"
            ;;
    esac

    ACTIVE_ARGS=()
    [[ -n "$CURRENT_INDEX" && "$MODE" != "wallhaven" ]] && ACTIVE_ARGS=( -a "$CURRENT_INDEX" )

    set +e
    CHOICE=$(rofi -dmenu -i \
        -theme "$THEME_RASI" \
        -p "$PROMPT" \
        -format 's' \
        -matching fuzzy \
        -kb-custom-1 "Alt+t" \
        -kb-custom-2 "Alt+l" \
        -kb-custom-3 "Alt+w" \
        -kb-screenshot "" \
        -kb-custom-4 "Alt+s" \
        -kb-custom-5 "Alt+n" \
        -kb-custom-6 "Alt+p" \
        -kb-accept-entry "Return" \
        "${ACTIVE_ARGS[@]}" < "$ENTRIES_FILE")
    RC=$?
    set -e
    rm -f "$ENTRIES_FILE"

    case "$RC" in
        0)
            # Selection made.
            [[ -z "$CHOICE" ]] && exit 0

            SELECTED=""
            if [[ "$MODE" == "wallhaven" ]]; then
                SELECTED=$(resolve_wallhaven "$CHOICE") || continue
            elif [[ "$MODE" == "local" ]]; then
                SELECTED=$(resolve_local "$CHOICE") || {
                    notify-send -t 2500 "Wallpaper" "Couldn't resolve '$CHOICE'" 2>/dev/null || true
                    continue
                }
            else
                # Both: try local first, then wallhaven
                SELECTED=$(resolve_local "$CHOICE" 2>/dev/null) || \
                    SELECTED=$(resolve_wallhaven "$CHOICE") || {
                    notify-send -t 2500 "Wallpaper" "Couldn't resolve '$CHOICE'" 2>/dev/null || true
                    continue
                }
            fi

            apply_wallpaper "$SELECTED" "$STATE"
            continue
            ;;
        10)  # Alt+t: toggle theme
            if [[ "$STATE" == "on" ]]; then echo "off" > "$STATE_FILE"
            else echo "on" > "$STATE_FILE"; fi
            continue
            ;;
        11)  # Alt+l: switch to local
            MODE="local"; WH_PAGE=1
            write_mode "local"
            continue
            ;;
        12)  # Alt+w: switch to wallhaven
            MODE="wallhaven"; WH_PAGE=1
            write_mode "wallhaven"
            continue
            ;;
        13)  # Alt+s: settings
            run_settings
            continue
            ;;
        14)  # Alt+n: next page
            WH_PAGE=$((WH_PAGE + 1))
            continue
            ;;
        15)  # Alt+p: prev page
            (( WH_PAGE > 1 )) && WH_PAGE=$((WH_PAGE - 1))
            continue
            ;;
        *)
            exit 0
            ;;
    esac
done
