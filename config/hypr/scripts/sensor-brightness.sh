#!/usr/bin/env bash
# Adjust sensor panel brightness via a black overlay dimmer
# Usage: sensor-brightness.sh up|down|reset
#
# Steps in increments of 10 (0–80), stored as 0.0–0.8 for CSS opacity

STEP=10
MAX=80
MIN=0

# Ensure dimmer window is open
eww active-windows 2>/dev/null | grep -q sensor-dimmer || eww open sensor-dimmer 2>/dev/null

# Read current level (convert 0.X back to integer 0-80)
ALPHA=$(eww get dimmer-alpha 2>/dev/null || echo "0.0")
CURRENT=$(awk -v a="$ALPHA" 'BEGIN{printf "%d", a * 100}')

case "${1:-}" in
    down)  NEW=$(( CURRENT + STEP )) ;;
    up)    NEW=$(( CURRENT - STEP )) ;;
    reset) NEW=0 ;;
    *)     echo "Usage: $0 up|down|reset"; exit 1 ;;
esac

(( NEW > MAX )) && NEW=$MAX
(( NEW < MIN )) && NEW=$MIN

# Convert integer to decimal string for CSS opacity
DECIMAL=$(awk -v n="$NEW" 'BEGIN{printf "%.1f", n / 100}')
eww update dimmer-alpha="$DECIMAL"

# Close dimmer entirely when at 0 for zero overhead
if (( NEW == 0 )); then
    eww close sensor-dimmer 2>/dev/null
fi
