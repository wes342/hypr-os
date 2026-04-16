#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Eye candy launcher -- rofi menu of      │
# │  terminal visual effects. Each opens     │
# │  in a floating kitty window themed to    │
# │  match the current wallpaper palette.    │
# └──────────────────────────────────────────┘

set -euo pipefail

TERMINAL="${TERMINAL:-kitty}"

launch() {
    local title="$1"; shift
    setsid -f "$TERMINAL" --title "$title" --class "eye-candy" "$@" >/dev/null 2>&1
}

# Read accent from the themed terminal palette.
# cmatrix only takes named colors -- pick the closest vibe.
# We default to green (classic Matrix) but offer themed variants.

EFFECTS=(
    "󱊷  Matrix Rain (green)"
    "󱊷  Matrix Rain (cyan)"
    "󱊷  Matrix Rain (magenta)"
    "  Pipes"
    "  Bonsai Tree"
    "  Clock"
    "󰈺  Aquarium"
    "  Rain"
    "  Cava Visualizer"
)

# Build rofi input.
CHOICE=$(printf '%s\n' "${EFFECTS[@]}" | rofi -dmenu -i \
    -theme ~/.config/rofi/config.rasi \
    -p "Eye Candy" \
    -matching fuzzy) || exit 0

case "$CHOICE" in
    *"Matrix Rain (green)"*)
        launch "Matrix" -e cmatrix -ab -C green -u 4
        ;;
    *"Matrix Rain (cyan)"*)
        launch "Matrix" -e cmatrix -ab -C cyan -u 4
        ;;
    *"Matrix Rain (magenta)"*)
        launch "Matrix" -e cmatrix -ab -C magenta -u 4
        ;;
    *Pipes*)
        launch "Pipes" -e bash -c 'pipes.sh -t 2 -R -r 0 -p 3'
        ;;
    *Bonsai*)
        launch "Bonsai" -e cbonsai -li -w 2
        ;;
    *Clock*)
        launch "Clock" -e tty-clock -cst -C 5
        ;;
    *Aquarium*)
        launch "Aquarium" -e asciiquarium
        ;;
    *Rain*)
        launch "Rain" -e bash -c '
            # Simple rain effect using shell
            cols=$(tput cols); lines=$(tput lines)
            chars=("," "." "│" "┃" "╎" "╏" "╵")
            tput civis; trap "tput cnorm; clear; exit" INT TERM
            while true; do
                c=$((RANDOM % cols)); l=$((RANDOM % lines))
                ch="${chars[$((RANDOM % ${#chars[@]}))]}"
                tput cup $l $c; printf "\033[36m%s\033[0m" "$ch"
                sleep 0.02
            done
        '
        ;;
    *Cava*)
        launch "Cava" -e cava
        ;;
esac
