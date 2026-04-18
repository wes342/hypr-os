#!/usr/bin/env bash
# Adjust sensor panel brightness via a black overlay dimmer
# Usage: sensor-brightness.sh up|down|reset
#
# Dimmer opacity 0 = full brightness, 80 = very dim

STEP=10
MAX=80
MIN=0

# Ensure dimmer window is open
eww active-windows 2>/dev/null | grep -q sensor-dimmer || eww open sensor-dimmer 2>/dev/null

CURRENT=$(eww get dimmer-opacity 2>/dev/null || echo 0)

case "${1:-}" in
    down)  NEW=$(( CURRENT + STEP )) ;;
    up)    NEW=$(( CURRENT - STEP )) ;;
    reset) NEW=0 ;;
    *)     echo "Usage: $0 up|down|reset"; exit 1 ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < MIN )) && NEW=$MIN

eww update dimmer-opacity="$NEW"

# Close dimmer entirely when at 0 for zero overhead
if (( NEW == 0 )); then
    eww close sensor-dimmer 2>/dev/null
fi
