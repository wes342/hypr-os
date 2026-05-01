#!/usr/bin/env bash
set -euo pipefail

if ! command -v eww >/dev/null 2>&1; then
    exit 0
fi

eww daemon 2>/dev/null || true
eww close sensor-panel-0 sensor-panel-1 2>/dev/null || true

outputs=$(swaymsg -t get_outputs 2>/dev/null | jq '[.[] | select(.active)] | length' 2>/dev/null || echo 1)
if [[ "$outputs" -gt 1 ]]; then
    eww open sensor-panel-1 2>/dev/null || eww open sensor-panel-0 2>/dev/null || true
else
    eww open sensor-panel-0 2>/dev/null || true
fi

"${HYPR_OS_DIR:-$HOME/dev/hypr-os}/config/hypr/scripts/sensor-brightness.sh" restore 2>/dev/null || true
