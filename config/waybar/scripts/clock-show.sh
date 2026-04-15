#!/usr/bin/env bash
# Outputs waybar JSON for the custom/clock module.
# Reads display mode from /tmp/hypr-os-clock-mode (0=time, 1=date, 2=both).
# Tooltip is rendered by clock-tooltip.py and cached for ~30s.

set -uo pipefail

state=/tmp/hypr-os-clock-mode
mode=$(cat "$state" 2>/dev/null || echo 0)
case "$mode" in
    0) text="$(date '+%-I:%M %p')" ;;
    1) text="$(date '+%a, %b %-d')" ;;
    2) text="$(date '+%-I:%M %p')  ·  $(date '+%a %b %-d')" ;;
    *) text="$(date '+%-I:%M %p')"; echo 0 > "$state" ;;
esac

cache=/tmp/hypr-os-clock-tooltip.cache
script="$HOME/.config/waybar/scripts/clock-tooltip.py"

cache_age=$(( $(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0) ))
if [[ ! -r "$cache" || $cache_age -gt 30 ]]; then
    ( "$script" > "$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache" ) &
    disown
fi

tooltip=$(cat "$cache" 2>/dev/null || echo "Loading…")

jq -nc --arg text "$text" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip, class:"clock"}'
