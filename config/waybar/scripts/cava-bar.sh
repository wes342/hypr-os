#!/usr/bin/env bash
# Compact cava visualizer for waybar. Outputs unicode block characters
# prefixed with a separator. When nothing is playing (all bars at 0),
# outputs an empty line so waybar hides both the separator and the
# visualizer.

exec cava -p ~/.config/cava/waybar.conf 2>/dev/null \
    | sed -u 's/;//g;s/0/▁/g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g' \
    | sed -u 's/^▁*$//; t; s/^/│ /'
