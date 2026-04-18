#!/usr/bin/env bash
# Adjust sensor panel brightness via a black overlay dimmer
# Usage: sensor-brightness.sh up|down|reset|restore
#
# Level 0 = full brightness, 8 = very dim
# Level is persisted to ~/.cache/hypr/dimmer-level

MAX=8
MIN=0
CACHE="$HOME/.cache/hypr/dimmer-level"

case "${1:-}" in
    restore)
        # Called after eww reload to restore saved level
        [[ -f "$CACHE" ]] && eww update dimmer-level="$(cat "$CACHE")" 2>/dev/null
        exit 0
        ;;
    down|up|reset) ;;
    *) echo "Usage: $0 up|down|reset|restore"; exit 1 ;;
esac

CURRENT=$(eww get dimmer-level 2>/dev/null || echo 0)

case "${1:-}" in
    down)  NEW=$(( CURRENT + 1 )) ;;
    up)    NEW=$(( CURRENT - 1 )) ;;
    reset) NEW=0 ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < MIN )) && NEW=$MIN

eww update dimmer-level="$NEW"
echo "$NEW" > "$CACHE"
