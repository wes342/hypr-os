#!/usr/bin/env bash
# Toggle screen recording with wf-recorder
# Usage: screen-record.sh [region]

if pgrep -x wf-recorder >/dev/null; then
    pkill -x wf-recorder
    notify-send -t 2000 "Recording" "Stopped — saved to ~/Videos/"
    exit 0
fi

mkdir -p ~/Videos
OUTFILE=~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4

if [[ "${1:-}" == "region" ]]; then
    GEOM=$(slurp 2>/dev/null) || exit 1
    wf-recorder -g "$GEOM" -f "$OUTFILE" &
    notify-send -t 2000 "Recording" "Region recording started"
else
    wf-recorder -f "$OUTFILE" &
    notify-send -t 2000 "Recording" "Started"
fi

disown
