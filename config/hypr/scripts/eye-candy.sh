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
    "󱊷  Matrix"
    "  Bonsai Tree"
    "  Clock"
    "  Rain"
)

CHOICE=$(printf '%s\n' "${EFFECTS[@]}" | rofi -dmenu -i \
    -theme ~/.config/rofi/dmenu.rasi \
    -p "Eye Candy" \
    -matching fuzzy) || exit 0

case "$CHOICE" in
    *Matrix*)
        launch "Matrix" -e "$HOME/.config/hypr/scripts/matrix-run.sh"
        ;;
    *Bonsai*)
        launch "Bonsai" -e cbonsai -li -w 2
        ;;
    *Clock*)
        launch "Clock" -e tty-clock -cst -C 5
        ;;
    *Rain*)
        launch "Rain" -e bash -c '
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
esac
