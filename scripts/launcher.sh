#!/usr/bin/env bash
# Toggle rofi launcher -- if running, kill it; otherwise launch it.
# Injects the current wallpaper as the window background-image.

LOCKFILE="/tmp/hypr-os-launcher.lock"
WALLPAPER=$(cat "$HOME/.cache/hypr/current_wallpaper" 2>/dev/null || echo "")

if [[ -f "$LOCKFILE" ]]; then
    pkill -x rofi 2>/dev/null
    rm -f "$LOCKFILE"
else
    touch "$LOCKFILE"

    THEME_EXTRA=""
    if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
        THEME_EXTRA="window { background-image: url(\"$WALLPAPER\", width); }"
    fi

    rofi -show drun -show-icons \
        -theme-str "$THEME_EXTRA"

    rm -f "$LOCKFILE"
fi
