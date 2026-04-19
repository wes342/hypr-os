#!/usr/bin/env bash
# Periodically ensures:
# 1. No windows are on the sensor panel monitor
# 2. Eww sensor panel is on the correct monitor (not the primary)
# Runs every 3 seconds.

SENSOR="HDMI-A-2"
PRIMARY="DP-3"

while true; do
    sleep 3

    # Skip if primary not connected
    hyprctl monitors -j 2>/dev/null | jq -e ".[] | select(.name==\"$PRIMARY\")" >/dev/null 2>&1 || continue

    SENSOR_ID=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$SENSOR\") | .id")
    [[ -z "$SENSOR_ID" || "$SENSOR_ID" == "null" ]] && continue

    # Remember which workspace is focused so we can restore it
    CURRENT_WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')

    MOVED=false

    # Move any stray windows off sensor monitor silently to workspace 1
    for addr in $(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.monitor==$SENSOR_ID) | .address"); do
        hyprctl dispatch movetoworkspacesilent "1,address:$addr" 2>/dev/null
        MOVED=true
    done

    # Move any workspaces stuck on sensor monitor (except the empty placeholder)
    for ws in $(hyprctl workspaces -j 2>/dev/null | jq -r ".[] | select(.monitor==\"$SENSOR\" and .windows > 0) | .id"); do
        hyprctl dispatch moveworkspacetomonitor "$ws" "$PRIMARY" 2>/dev/null
        MOVED=true
    done

    # Restore focus and cursor to primary monitor
    if $MOVED && [[ -n "$CURRENT_WS" ]]; then
        hyprctl dispatch workspace "$CURRENT_WS" 2>/dev/null
        hyprctl dispatch focusmonitor "$PRIMARY" 2>/dev/null
        hyprctl dispatch movecursor 1280 720 2>/dev/null
    fi

    # Ensure cursor is on primary monitor (can drift during sleep/wake)
    FOCUSED_MON=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name')
    if [[ "$FOCUSED_MON" == "$SENSOR" ]]; then
        hyprctl dispatch focusmonitor "$PRIMARY" 2>/dev/null
        hyprctl dispatch movecursor 1280 720 2>/dev/null
    fi

    # Ensure dimmer level matches saved value
    SAVED_DIM=$(cat "$HOME/.cache/hypr/dimmer-level" 2>/dev/null || echo 0)
    CURRENT_DIM=$(eww get dimmer-level 2>/dev/null || echo 0)
    if [[ "$SAVED_DIM" != "$CURRENT_DIM" && "$SAVED_DIM" != "0" ]]; then
        eww update dimmer-level="$SAVED_DIM" 2>/dev/null
    fi

    # Check if sensor panel eww is on the wrong monitor
    if eww active-windows 2>/dev/null | grep -q "sensor-panel"; then
        SENSOR_Y=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$SENSOR\") | .y")
        PANEL_Y=$(hyprctl layers 2>/dev/null | grep -A0 "hypr-os-sensor" | grep -oP 'xywh: \d+ \K\d+')
        if [[ -n "$PANEL_Y" && "$PANEL_Y" != "$SENSOR_Y" ]]; then
            ~/.config/hypr/scripts/sensor-panel.sh 2>/dev/null &
        fi
    fi
done
