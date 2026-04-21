#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Snapper snapshot manager -- rofi menu.  │
# │  Create, list, delete, restore btrfs     │
# │  snapshots with confirmation prompts.    │
# └──────────────────────────────────────────┘

set -euo pipefail

THEME="$HOME/.config/rofi/dmenu.rasi"

# ── Helpers ──────────────────────────────

rofi_menu() {
    rofi -dmenu -i -theme "$THEME" -matching fuzzy "$@"
}

rofi_confirm() {
    local action="$1"
    local choice
    choice=$(printf "  Yes, %s\n  Cancel" "$action" \
        | rofi_menu -p "Confirm" -selected-row 1) || return 1
    [[ "$choice" == *"Yes"* ]]
}

notify() {
    notify-send -t 3000 "Snapper" "$1" 2>/dev/null || true
}

# Run snapper; use pkexec for operations that may need root.
snap() {
    snapper "$@" 2>/dev/null || pkexec snapper "$@" 2>&1
}

# ── Snapshot listing ─────────────────────

list_snapshots() {
    local config="$1"
    snap -c "$config" list --columns number,date,description,type,cleanup \
        2>/dev/null | tail -n +3
}

pick_snapshot() {
    local config="$1" prompt="$2"
    local raw
    raw=$(list_snapshots "$config")
    [[ -z "$raw" ]] && { notify "No snapshots found for '$config'."; return 1; }

    # Build rofi entries: "# │ date │ description │ type"
    local entries=""
    while IFS='│' read -r num date desc stype cleanup; do
        num=$(echo "$num" | xargs)
        date=$(echo "$date" | xargs)
        desc=$(echo "$desc" | xargs)
        stype=$(echo "$stype" | xargs)
        [[ "$num" == "0" ]] && continue  # skip the "current" entry
        [[ -z "$num" ]] && continue
        local icon=""
        case "$stype" in
            single) icon="󰆓" ;;
            pre)    icon="󰦛" ;;
            post)   icon="󰦜" ;;
            *)      icon="󰋣" ;;
        esac
        entries+="$icon  #$num   $date   $desc"$'\n'
    done <<< "$raw"

    [[ -z "$entries" ]] && { notify "No snapshots found."; return 1; }

    local choice
    choice=$(printf '%s' "$entries" | rofi_menu -p "$prompt") || return 1

    # Extract snapshot number from selection.
    echo "$choice" | grep -oP '#\K[0-9]+'
}

# ── Actions ──────────────────────────────

action_create() {
    local config
    config=$(printf '  root\n  home' \
        | rofi_menu -p "Create snapshot for") || return
    case "$config" in
        *root*) config="root" ;;
        *home*) config="home" ;;
        *) return ;;
    esac

    local desc
    desc=$(echo "" | rofi_menu -p "󰏫 Description (optional)") || desc=""

    local args=(-c "$config" create --type single --print-number)
    [[ -n "$desc" ]] && args+=(--description "$desc")

    local num
    num=$(snap "${args[@]}" 2>&1) || { notify "Failed to create snapshot."; return; }
    notify "Created $config snapshot #$num${desc:+ — $desc}"
}

action_list() {
    local config
    config=$(printf '  root\n  home' \
        | rofi_menu -p "List snapshots for") || return
    case "$config" in
        *root*) config="root" ;;
        *home*) config="home" ;;
        *) return ;;
    esac

    local raw
    raw=$(list_snapshots "$config")
    [[ -z "$raw" ]] && { notify "No snapshots."; return; }

    local entries=""
    while IFS='│' read -r num date desc stype cleanup; do
        num=$(echo "$num" | xargs)
        date=$(echo "$date" | xargs)
        desc=$(echo "$desc" | xargs)
        stype=$(echo "$stype" | xargs)
        [[ "$num" == "0" || -z "$num" ]] && continue
        local icon=""
        case "$stype" in
            single) icon="󰆓" ;;
            pre)    icon="󰦛" ;;
            post)   icon="󰦜" ;;
            *)      icon="󰋣" ;;
        esac
        entries+="$icon  #$num   $date   [$stype]   $desc"$'\n'
    done <<< "$raw"

    printf '%s' "$entries" | rofi_menu -p "  $config snapshots" > /dev/null || true
}

action_delete() {
    local config
    config=$(printf '  root\n  home' \
        | rofi_menu -p "Delete snapshot from") || return
    case "$config" in
        *root*) config="root" ;;
        *home*) config="home" ;;
        *) return ;;
    esac

    local num
    num=$(pick_snapshot "$config" "󰆴 Select snapshot to delete") || return

    rofi_confirm "delete $config snapshot #$num" || { notify "Cancelled."; return; }

    if snap -c "$config" delete "$num" 2>&1; then
        notify "Deleted $config snapshot #$num."
    else
        notify "Failed to delete snapshot #$num."
    fi
}

action_restore() {
    local config
    config=$(printf '  root\n  home' \
        | rofi_menu -p "Restore snapshot from") || return
    case "$config" in
        *root*) config="root" ;;
        *home*) config="home" ;;
        *) return ;;
    esac

    local num
    num=$(pick_snapshot "$config" "󰦛 Select snapshot to restore") || return

    # Double confirmation for restore.
    rofi_confirm "RESTORE $config to snapshot #$num (changes will be undone)" || {
        notify "Cancelled."; return
    }
    rofi_confirm "ARE YOU SURE? This will undo all changes since snapshot #$num" || {
        notify "Cancelled."; return
    }

    if snap -c "$config" undochange "$num"..0 2>&1; then
        notify "Restored $config to snapshot #$num. Reboot recommended."
    else
        notify "Restore failed. Check snapper logs."
    fi
}

action_compare() {
    local config
    config=$(printf '  root\n  home' \
        | rofi_menu -p "Compare snapshots for") || return
    case "$config" in
        *root*) config="root" ;;
        *home*) config="home" ;;
        *) return ;;
    esac

    local from to
    from=$(pick_snapshot "$config" "󰁌 FROM snapshot (older)") || return
    to=$(pick_snapshot "$config" "󰁍 TO snapshot (newer)") || return

    local diff_output
    diff_output=$(snap -c "$config" status "$from".."$to" 2>&1 | head -60)
    [[ -z "$diff_output" ]] && diff_output="No changes between #$from and #$to."

    # Show in a floating terminal.
    local tmpf; tmpf=$(mktemp /tmp/snapper-diff.XXXXX)
    {
        echo "╭──────────────────────────────────────────────────╮"
        echo "│  Snapper diff: $config #$from → #$to"
        echo "╰──────────────────────────────────────────────────╯"
        echo ""
        echo "$diff_output"
        echo ""
        echo "Press any key to close."
    } > "$tmpf"
    kitty --title "Snapper Diff" --class "eye-candy" \
        -e bash -c "cat '$tmpf'; rm '$tmpf'; read -rsn1" &
    disown
}

# ── Main menu ────────────────────────────

MENU=(
    "󰄬  Create snapshot"
    "󰋣  List snapshots"
    "──────────────────────────"
    "󰦛  Restore snapshot"
    "󰆴  Delete snapshot"
    "──────────────────────────"
    "󰁌  Compare snapshots"
)

CHOICE=$(printf '%s\n' "${MENU[@]}" | rofi_menu -p "󰋣 Snapper") || exit 0

case "$CHOICE" in
    *Create*)  action_create  ;;
    *List*)    action_list    ;;
    *Restore*) action_restore ;;
    *Delete*)  action_delete  ;;
    *Compare*) action_compare ;;
esac
