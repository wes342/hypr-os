#!/usr/bin/env bash
# Launch default apps -- reads from compositor defaults.conf
# Usage: launch.sh terminal|browser|files|menu

if [[ -f "$HOME/.config/sway/defaults.conf" && -n "${SWAYSOCK:-}" ]]; then
    DEFAULTS="$HOME/.config/sway/defaults.conf"
else
    DEFAULTS="$HOME/.config/hypr/defaults.conf"
fi

get_default() {
    grep "^\$$1 " "$DEFAULTS" | sed 's/^\$[a-zA-Z]* = //'
}

case "${1:-}" in
    terminal)    shift; exec $(get_default terminal) "$@" ;;
    browser)     shift; exec $(get_default browser) "$@" ;;
    files)       shift; exec $(get_default fileManager) "$@" ;;
    menu)        shift; exec $(get_default menu) "$@" ;;
    *)           echo "Usage: $0 terminal|browser|files|menu" ;;
esac
