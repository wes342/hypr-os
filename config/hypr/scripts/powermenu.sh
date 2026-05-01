#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Rofi power menu -- lock / suspend /     │
# │  hibernate / logout / reboot / shutdown  │
# └──────────────────────────────────────────┘

set -euo pipefail

THEME="$HOME/.config/rofi/powermenu.rasi"

menu() {
    rofi -dmenu -i -theme "$THEME" -p "Power" "$@"
}

confirm() {
    local action="$1"
    local choice
    choice=$(printf " Yes, %s\n Cancel" "$action" \
        | rofi -dmenu -i -theme "$THEME" -p "Confirm" -selected-row 1)
    [[ "$choice" == *"Yes"* ]]
}

OPTIONS=$(cat <<EOF
󰌾  Lock
󰤄  Suspend
󰒲  Hibernate
󰗽  Logout
󰜉  Reboot
⏻  Shutdown
EOF
)

CHOICE=$(echo "$OPTIONS" | menu) || exit 0

case "$CHOICE" in
    *Lock*)
        if command -v hyprlock >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
            hyprlock &
        else
            swaylock -f &
        fi
        ;;
    *Suspend*)
        systemctl suspend
        ;;
    *Hibernate*)
        systemctl hibernate
        ;;
    *Logout*)
        if [[ -n "${SWAYSOCK:-}" ]]; then
            swaymsg exit
        else
            hyprctl dispatch exit
        fi
        ;;
    *Reboot*)
        if confirm "reboot"; then
            systemctl reboot
        fi
        ;;
    *Shutdown*)
        if confirm "shutdown"; then
            systemctl poweroff
        fi
        ;;
esac
