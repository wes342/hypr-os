#!/usr/bin/env bash
# Wrapper that calls the main wallpaper script
exec "$(dirname "$(dirname "$(dirname "$(dirname "$(readlink -f "$0")")")")")/scripts/wallpaper.sh" "$@"
