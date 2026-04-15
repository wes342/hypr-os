#!/usr/bin/env bash
# Close the active window, optionally refusing to kill fullscreen windows.
#   kill-window.sh          -- close unless fullscreen (safe default)
#   kill-window.sh --force  -- close even if fullscreen

set -euo pipefail

FORCE=${1:-}

fs=$(hyprctl activewindow -j 2>/dev/null | jq -r '.fullscreen' 2>/dev/null || echo "0")

if [[ "$FORCE" != "--force" ]] && [[ "$fs" != "0" && "$fs" != "null" && "$fs" != "false" ]]; then
    notify-send -t 1500 "Close" "Active window is fullscreen. Use SUPER+SHIFT+Q." 2>/dev/null || true
    exit 0
fi

hyprctl dispatch killactive ""
