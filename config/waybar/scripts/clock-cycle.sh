#!/usr/bin/env bash
# Cycle clock display mode: 0=time → 1=date → 2=both → 0
state=/tmp/hypr-os-clock-mode
mode=$(cat "$state" 2>/dev/null || echo 0)
mode=$(( (mode + 1) % 3 ))
echo "$mode" > "$state"
