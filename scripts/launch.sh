#!/usr/bin/env bash
# Launch default apps -- reads from hyprland defaults.conf
# Usage: launch.sh terminal|browser|files|menu

DEFAULTS="$HOME/.config/hypr/defaults.conf"

get_default() {
    grep "^\$$1 " "$DEFAULTS" | sed 's/^\$[a-zA-Z]* = //'
}

case "${1:-}" in
    terminal)    exec $(get_default terminal) ;;
    browser)     exec $(get_default browser) ;;
    files)       exec $(get_default fileManager) ;;
    menu)        exec $(get_default menu) ;;
    *)           echo "Usage: $0 terminal|browser|files|menu" ;;
esac
