#!/usr/bin/env bash
# Toggle screen recording with wf-recorder
# Usage: screen-record.sh [region]

if pgrep -x wf-recorder >/dev/null; then
    pkill -x wf-recorder
    notify-send -t 2000 "Recording" "Stopped — saved to ~/Videos/"
    exit 0
fi

# Record the focused monitor
MONITOR=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name')
[[ -z "$MONITOR" ]] && MONITOR="DP-3"

mkdir -p ~/Videos
OUTFILE=~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4

if [[ "${1:-}" == "region" ]]; then
    GEOM=$(slurp 2>/dev/null) || exit 1
    wf-recorder -o "$MONITOR" -g "$GEOM" -f "$OUTFILE" &
    notify-send -t 2000 "Recording" "Region recording started"
else
    wf-recorder -o "$MONITOR" -f "$OUTFILE" &
    notify-send -t 2000 "Recording" "Started"
fi

disown
