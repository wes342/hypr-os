#!/usr/bin/env bash
# Adjust sensor panel brightness via a black overlay dimmer
# Usage: sensor-brightness.sh up|down|reset
#
# Level 0 = full brightness, 8 = very dim

MAX=8
MIN=0

eww active-windows 2>/dev/null | grep -q sensor-dimmer || eww open sensor-dimmer 2>/dev/null

CURRENT=$(eww get dimmer-level 2>/dev/null || echo 0)

case "${1:-}" in
    down)  NEW=$(( CURRENT + 1 )) ;;
    up)    NEW=$(( CURRENT - 1 )) ;;
    reset) NEW=0 ;;
    *)     echo "Usage: $0 up|down|reset"; exit 1 ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < MIN )) && NEW=$MIN

eww update dimmer-level="$NEW"

if (( NEW == 0 )); then
    eww close sensor-dimmer 2>/dev/null
fi
