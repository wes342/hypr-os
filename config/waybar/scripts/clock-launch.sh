#!/usr/bin/env bash
# Launch the first available calendar app.

# Each entry: "<command-to-detect>|<exec line>"
candidates=(
    "gnome-calendar|gnome-calendar"
    "khal|kitty -e khal interactive"
    "calcurse|kitty -e calcurse"
    "korganizer|korganizer"
    "thunderbird|thunderbird --calendar"
)

for entry in "${candidates[@]}"; do
    cmd="${entry%%|*}"
    exec_line="${entry##*|}"
    if command -v "$cmd" >/dev/null 2>&1; then
        setsid -f sh -c "$exec_line" >/dev/null 2>&1
        exit 0
    fi
done

notify-send -t 4000 "Calendar" "No calendar app found.\nInstall one of: gnome-calendar, khal, calcurse, korganizer." 2>/dev/null
