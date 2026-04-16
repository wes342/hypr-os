#!/usr/bin/env bash
# Toggle the default audio source (microphone) mute and show a
# short notification with the new state. Works regardless of which
# voice app (Discord, browser, Mumble) is in focus -- the mic is
# muted at the OS level.

set -euo pipefail

wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle

# wpctl get-volume returns e.g. "Volume: 1.00 [MUTED]" when muted.
if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
    notify-send -t 1500 -i microphone-sensitivity-muted \
        "Microphone" "Muted" 2>/dev/null || true
else
    notify-send -t 1500 -i microphone-sensitivity-high \
        "Microphone" "Unmuted" 2>/dev/null || true
fi
