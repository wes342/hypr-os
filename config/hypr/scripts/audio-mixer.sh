#!/usr/bin/env bash
# Open whichever audio mixer GUI is installed. pwvucontrol is the
# PipeWire-native option (preferred); pavucontrol is the classic
# PulseAudio mixer.

for gui in pwvucontrol pavucontrol; do
    if command -v "$gui" &>/dev/null; then
        # If a window is already open, focus it instead of spawning another.
        if hyprctl clients -j 2>/dev/null | grep -q "\"class\": \"$gui\""; then
            hyprctl dispatch focuswindow "class:$gui" >/dev/null
        else
            setsid -f "$gui" >/dev/null 2>&1
        fi
        exit 0
    fi
done

notify-send -t 4000 "Audio" \
    "No mixer installed. Run: sudo pacman -S pwvucontrol" 2>/dev/null
