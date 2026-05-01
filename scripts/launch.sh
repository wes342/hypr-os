#!/usr/bin/env bash
# Launch default apps -- reads from compositor defaults.conf
# Usage: launch.sh terminal|browser|files|menu

if [[ -f "$HOME/.config/sway/defaults.conf" && -n "${SWAYSOCK:-}" ]]; then
    DEFAULTS="$HOME/.config/sway/defaults.conf"
else
    DEFAULTS="$HOME/.config/hypr/defaults.conf"
fi

export GTK_THEME="${GTK_THEME:-Adwaita:dark}"
export GTK_APPLICATION_PREFER_DARK_THEME="${GTK_APPLICATION_PREFER_DARK_THEME:-1}"
export QT_STYLE_OVERRIDE="${QT_STYLE_OVERRIDE:-Adwaita-Dark}"

get_default() {
    awk -v key="$1" '
        $1 == "set" && $2 == "$" key {
            $1 = ""; $2 = ""; sub(/^  */, ""); print; exit
        }
        $1 == "$" key && $2 == "=" {
            $1 = ""; $2 = ""; sub(/^  */, ""); print; exit
        }
    ' "$DEFAULTS"
}

case "${1:-}" in
    terminal)    shift; exec $(get_default terminal) "$@" ;;
    browser)     shift; exec $(get_default browser) "$@" ;;
    files)       shift; exec $(get_default fileManager) "$@" ;;
    menu)        shift; exec $(get_default menu) "$@" ;;
    *)           echo "Usage: $0 terminal|browser|files|menu" ;;
esac
