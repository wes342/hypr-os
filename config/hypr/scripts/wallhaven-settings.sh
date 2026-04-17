#!/usr/bin/env bash
# Standalone launcher for the Wallhaven settings form.
# Called from SUPER+SHIFT+B or from the wallpaper browser.

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
WALLHAVEN_PY="$HYPR_OS_DIR/scripts/wallhaven.py"
WH_CONF="$HOME/.config/hypr-os/wallhaven.conf"
SETTINGS_RASI="$HOME/.config/rofi/settings.rasi"

# Ensure config exists
python3 "$WALLHAVEN_PY" settings >/dev/null 2>&1
[[ -f "$WH_CONF" ]] || exit 1

conf_get() { grep "^$1=" "$WH_CONF" 2>/dev/null | cut -d= -f2 || echo ""; }
conf_set() { sed -i "s|^$1=.*|$1=$2|" "$WH_CONF"; }

rofi_pick() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | rofi -dmenu -i -theme "$SETTINGS_RASI" -p "$prompt"
}

rofi_input() {
    local prompt="$1" current="$2"
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
    src=$(conf_get source)
    srt=$(conf_get sorting)
    cats=$(conf_get categories)
    pur=$(conf_get purity)
    res=$(conf_get atleast)
    rat=$(conf_get ratios)
    qry=$(conf_get query)
    key=$(conf_get api_key)

    src_label=""
    case "$src" in
        local)     src_label="📁 Local only" ;;
        wallhaven) src_label="🌐 Wallhaven only" ;;
        both)      src_label="📁+🌐 Both" ;;
    esac

    key_label="not set"
    [[ -n "$key" ]] && key_label="configured ✓"

    entries=""
    entries+="───────── Source ─────────"$'\n'
    entries+="  󰉌  Source          $src_label"$'\n'
    entries+=""$'\n'
    entries+="───────── Search ─────────"$'\n'
    entries+="  󰍉  Search query    ${qry:-  (none)}"$'\n'
    entries+="  󰒺  Sorting         $srt"$'\n'
    entries+=""$'\n'
    entries+="───────── Filters ────────"$'\n'
    entries+="  󰉋  Categories      $(cat_label "$cats")"$'\n'
    entries+="  󰒃  Purity          $(pur_label "$pur")"$'\n'
    entries+="  󰍹  Min resolution  $res"$'\n'
    entries+="  󰢮  Aspect ratio    $rat"$'\n'
    entries+=""$'\n'
    entries+="───────── Account ────────"$'\n'
    entries+="  󰌆  API key         $key_label"$'\n'
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
            new=$(rofi_input "󰍉 Search query" "$qry") || continue
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
            while true; do
                gen_icon="󰄮"; ani_icon="󰄮"; ppl_icon="󰄮"
                [[ "${cats:0:1}" == "1" ]] && gen_icon="󰄲"
                [[ "${cats:1:1}" == "1" ]] && ani_icon="󰄲"
                [[ "${cats:2:1}" == "1" ]] && ppl_icon="󰄲"

                pick=$(rofi_pick "󰉋 Categories" \
                    "$gen_icon  General" \
                    "$ani_icon  Anime" \
                    "$ppl_icon  People" \
                    "󰄬  Done") || break
                case "$pick" in
                    *General*) cats=$(toggle_bit "$cats" 0); conf_set categories "$cats" ;;
                    *Anime*)   cats=$(toggle_bit "$cats" 1); conf_set categories "$cats" ;;
                    *People*)  cats=$(toggle_bit "$cats" 2); conf_set categories "$cats" ;;
                    *Done*)    break ;;
                esac
            done
            ;;
        *Purity*)
            while true; do
                sfw_icon="󰄮"; sketchy_icon="󰄮"; nsfw_icon="󰄮"
                [[ "${pur:0:1}" == "1" ]] && sfw_icon="󰄲"
                [[ "${pur:1:1}" == "1" ]] && sketchy_icon="󰄲"
                [[ "${pur:2:1}" == "1" ]] && nsfw_icon="󰄲"

                pick=$(rofi_pick "󰒃 Purity" \
                    "$sfw_icon  SFW" \
                    "$sketchy_icon  Sketchy" \
                    "$nsfw_icon  NSFW" \
                    "󰄬  Done") || break
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
            new=$(rofi_input "󰌆 API key (from wallhaven.cc/settings)" "$key") || continue
            conf_set api_key "$new"
            ;;
    esac
done
