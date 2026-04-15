#!/usr/bin/env bash
# eww hover-state coordinator.
# Lets the cursor move from the bar icon into the dropdown
# (and back) without flicker.
#
# Usage: hover.sh <enter|leave> <cpu|gpu|ram|storage>

set -uo pipefail

action="${1:?usage: hover.sh <enter|leave> <name>}"
name="${2:?usage: hover.sh <enter|leave> <name>}"

state_dir="/tmp/hypr-os-eww-hover"
mkdir -p "$state_dir"
state_file="$state_dir/$name"

DELAY="${HOVER_DELAY:-0.18}"
EWW="eww --config $HOME/.config/eww"

case "$action" in
    enter)
        touch "$state_file"
        $EWW open "$name-dropdown" >/dev/null 2>&1
        ;;
    leave)
        rm -f "$state_file"
        # Wait briefly: if cursor entered the partner surface
        # (icon ↔ dropdown), enter will re-create the state file.
        ( sleep "$DELAY"
          if [[ ! -e "$state_file" ]]; then
              $EWW close "$name-dropdown" >/dev/null 2>&1
          fi
        ) &
        disown
        ;;
    *)
        echo "unknown action: $action" >&2
        exit 1
        ;;
esac
