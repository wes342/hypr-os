#!/usr/bin/env bash
# Toggle rofi launcher -- if running, kill it; otherwise launch it

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
LOCKFILE="/tmp/hypr-os-launcher.lock"
DEFAULTS="$HOME/.config/hypr/defaults.conf"

if [[ -f "$LOCKFILE" ]]; then
    # Launcher was recently opened, close it
    pkill -x rofi 2>/dev/null
    rm -f "$LOCKFILE"
else
    # Open launcher
    touch "$LOCKFILE"
    MENU=$(grep '^\$menu' "$DEFAULTS" | sed 's/^\$menu = //')
    ${MENU:-rofi -show drun -show-icons}
    # Clean up lock when rofi exits (user picked something or pressed Esc)
    rm -f "$LOCKFILE"
fi
