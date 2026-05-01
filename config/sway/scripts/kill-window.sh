#!/usr/bin/env bash
if [[ "${1:-}" == "--force" ]]; then
    swaymsg kill
else
    swaymsg kill
fi
