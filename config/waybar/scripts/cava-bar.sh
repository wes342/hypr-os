#!/usr/bin/env bash
# Compact cava visualizer for waybar. Outputs a single line of unicode
# block characters that waybar refreshes on each newline.

exec cava -p ~/.config/cava/waybar.conf 2>/dev/null \
    | sed -u 's/;//g;s/0/▁/g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g'
