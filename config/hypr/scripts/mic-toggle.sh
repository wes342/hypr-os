#!/usr/bin/env bash
# Toggle the default audio source (microphone) mute and show a
# short notification with the new state. Works regardless of which
# voice app (Discord, browser, Mumble) is in focus -- the mic is
# muted at the OS level.

set -euo pipefail

SOUND_DIR="/usr/share/sounds/freedesktop/stereo"

play_sound() {
    local file="$1"
    [[ ! -f "$file" ]] && return
    if command -v pw-play &>/dev/null; then
        pw-play "$file" >/dev/null 2>&1 &
    elif command -v paplay &>/dev/null; then
        paplay "$file" >/dev/null 2>&1 &
    fi
    disown 2>/dev/null || true
}

# Find the Elgato Wave XLR source by name (ID can change on reboot).
# Falls back to the default source if Elgato isn't connected.
MIC_ID=$(wpctl status | grep -i "elgato.*mono" | grep -oP '\d+\.' | head -1 | tr -d '.')
MIC_ID="${MIC_ID:-@DEFAULT_AUDIO_SOURCE@}"

wpctl set-mute "$MIC_ID" toggle

# wpctl get-volume returns e.g. "Volume: 1.00 [MUTED]" when muted.
if wpctl get-volume "$MIC_ID" | grep -q MUTED; then
    play_sound "$SOUND_DIR/device-removed.oga"
    notify-send -t 1500 -i microphone-sensitivity-muted \
        "Microphone" "Muted" 2>/dev/null || true
else
    play_sound "$SOUND_DIR/device-added.oga"
    notify-send -t 1500 -i microphone-sensitivity-high \
        "Microphone" "Unmuted" 2>/dev/null || true
fi
