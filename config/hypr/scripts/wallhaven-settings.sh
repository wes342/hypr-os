#!/usr/bin/env bash
# Standalone launcher for the Wallhaven settings form.
# Called from SUPER+SHIFT+B or from the wallpaper browser.

set -euo pipefail

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
WALLHAVEN_PY="$HYPR_OS_DIR/scripts/wallhaven.py"
WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
SETTINGS_RASI="$HOME/.config/rofi/settings.rasi"

# Ensure config exists
python3 "$WALLHAVEN_PY" settings >/dev/null 2>&1
[[ -f "$WH_CONF" ]] || exit 1

conf_get() { grep "^$1=" "$WH_CONF" 2>/dev/null | cut -d= -f2; }
conf_set() { sed -i "s/^$1=.*/$1=$2/" "$WH_CONF"; }

rofi_pick() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | rofi -dmenu -i -theme "$SETTINGS_RASI" -p "$prompt"
}

rofi_input() {
    local prompt="$1" current="$2"
    # -filter pre-fills the text box so user can edit in place.
    # Empty stdin so there are no list entries to filter against.
    rofi -dmenu -theme "$SETTINGS_RASI" -p "$prompt" -filter "$current" < /dev/null
}

cat_label() {
    local c="$1" out=""
    [[ "${c:0:1}" == "1" ]] && out+="General " || out+="ꞏꞏꞏꞏꞏꞏꞏ "
    [[ "${c:1:1}" == "1" ]] && out+="Anime " || out+="ꞏꞏꞏꞏꞏ "
    [[ "${c:2:1}" == "1" ]] && out+="People" || out+="ꞏꞏꞏꞏꞏꞏ"
    echo "$out"
}

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

while true; do
    local_source=$(conf_get source)
    local_sorting=$(conf_get sorting)
    local_categories=$(conf_get categories)
    local_purity=$(conf_get purity)
    local_atleast=$(conf_get atleast)
    local_ratios=$(conf_get ratios)
    local_query=$(conf_get query)
    local_api_key=$(conf_get api_key)

    source_icon=""
    case "$local_source" in
        local)     source_icon="📁 Local only" ;;
        wallhaven) source_icon="🌐 Wallhaven only" ;;
        both)      source_icon="📁+🌐 Both" ;;
    esac

    key_status="not set"
    [[ -n "$local_api_key" ]] && key_status="configured ✓"

    entries=""
    entries+="───────── Source ─────────"$'\n'
    entries+="  󰉌  Source          $source_icon"$'\n'
    entries+=""$'\n'
    entries+="───────── Search ─────────"$'\n'
    entries+="  󰍉  Search query    ${local_query:-  (none)}"$'\n'
    entries+="  󰒺  Sorting         $local_sorting"$'\n'
    entries+=""$'\n'
    entries+="───────── Filters ────────"$'\n'
    entries+="  󰉋  Categories      $(cat_label "$local_categories")"$'\n'
    entries+="  󰒃  Purity          $(pur_label "$local_purity")"$'\n'
    entries+="  󰍹  Min resolution  $local_atleast"$'\n'
    entries+="  󰢮  Aspect ratio    $local_ratios"$'\n'
    entries+=""$'\n'
    entries+="───────── Account ────────"$'\n'
    entries+="  󰌆  API key         $key_status"$'\n'
    entries+=""$'\n'
    entries+="  󰄬  Done"

    choice=$(printf '%s' "$entries" | rofi -dmenu -i \
        -theme "$SETTINGS_RASI" -p "⚙ Wallhaven Settings" \
        -matching fuzzy) || exit 0

    case "$choice" in
        *Done*) exit 0 ;;
        *Source*)
            new=$(rofi_pick "󰉌 Source" \
                "📁  local        Use wallpapers from ~/Pictures/Wallpaper" \
                "🌐  wallhaven    Fetch from wallhaven.cc API" \
                "📁+🌐  both        Local + Wallhaven combined") || continue
            case "$new" in
                *local*)     conf_set source local ;;
                *wallhaven*) conf_set source wallhaven ;;
                *both*)      conf_set source both ;;
            esac
            ;;
        *"Search query"*)
            new=$(rofi_input "󰍉 Search query" "$local_query") || continue
            conf_set query "$new"
            ;;
        *Sorting*)
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
            cats="$local_categories"
            while true; do
                local gen_icon="󰄮" ani_icon="󰄮" ppl_icon="󰄮"
                [[ "${cats:0:1}" == "1" ]] && gen_icon="󰄲"
                [[ "${cats:1:1}" == "1" ]] && ani_icon="󰄲"
                [[ "${cats:2:1}" == "1" ]] && ppl_icon="󰄲"

                pick=$(rofi_pick "󰉋 Categories" \
                    "$gen_icon  General" \
                    "$ani_icon  Anime" \
                    "$ppl_icon  People" \
                    "󰄬  Done") || { conf_set categories "$cats"; break; }
                case "$pick" in
                    *General*) cats=$(toggle_bit "$cats" 0); conf_set categories "$cats" ;;
                    *Anime*)   cats=$(toggle_bit "$cats" 1); conf_set categories "$cats" ;;
                    *People*)  cats=$(toggle_bit "$cats" 2); conf_set categories "$cats" ;;
                    *Done*)    break ;;
                esac
            done
            ;;
        *Purity*)
            pur="$local_purity"
            while true; do
                local sfw_icon="󰄮" sketchy_icon="󰄮" nsfw_icon="󰄮"
                [[ "${pur:0:1}" == "1" ]] && sfw_icon="󰄲"
                [[ "${pur:1:1}" == "1" ]] && sketchy_icon="󰄲"
                [[ "${pur:2:1}" == "1" ]] && nsfw_icon="󰄲"

                pick=$(rofi_pick "󰒃 Purity" \
                    "$sfw_icon  SFW" \
                    "$sketchy_icon  Sketchy" \
                    "$nsfw_icon  NSFW" \
                    "󰄬  Done") || { conf_set purity "$pur"; break; }
                case "$pick" in
                    *SFW*)     pur=$(toggle_bit "$pur" 0); conf_set purity "$pur" ;;
                    *Sketchy*) pur=$(toggle_bit "$pur" 1); conf_set purity "$pur" ;;
                    *NSFW*)    pur=$(toggle_bit "$pur" 2); conf_set purity "$pur" ;;
                    *Done*)    break ;;
                esac
            done
            ;;
        *"Min resolution"*)
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
            new=$(rofi_input "󰌆 API key (from wallhaven.cc/settings)" "$local_api_key") || continue
            conf_set api_key "$new"
            ;;
    esac
done
