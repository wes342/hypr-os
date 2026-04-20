#!/usr/bin/env bash
# Guard daemon: keeps windows off the sensor panel monitor.
# Checks every 5 seconds with minimal subprocess spawning.

SENSOR="HDMI-A-2"
PRIMARY="DP-3"
DIMMER_CACHE="$HOME/.cache/hypr/dimmer-level"

while true; do
    sleep 5

    # Single hyprctl call, cache result
    MONITORS=$(hyprctl monitors -j 2>/dev/null) || continue

    # Skip if primary not connected or sensor not connected
    echo "$MONITORS" | jq -e ".[] | select(.name==\"$PRIMARY\")" >/dev/null 2>&1 || continue
    SENSOR_INFO=$(echo "$MONITORS" | jq -r ".[] | select(.name==\"$SENSOR\")")
    [[ -z "$SENSOR_INFO" ]] && continue

    SENSOR_ID=$(echo "$SENSOR_INFO" | jq -r '.id')
    FOCUSED_MON=$(echo "$MONITORS" | jq -r '.[] | select(.focused) | .name')

    # Fix cursor if stuck on sensor monitor
    if [[ "$FOCUSED_MON" == "$SENSOR" ]]; then
        hyprctl dispatch focusmonitor "$PRIMARY" 2>/dev/null
        hyprctl dispatch movecursor 1280 720 2>/dev/null
    fi

    # Check for stray windows on sensor monitor
    STRAY=$(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.monitor==$SENSOR_ID) | .address")
    if [[ -n "$STRAY" ]]; then
        CURRENT_WS=$(hyprctl activeworkspace -j 2>/dev/null | jq -r '.id')
        for addr in $STRAY; do
            hyprctl dispatch movetoworkspacesilent "1,address:$addr" 2>/dev/null
        done
        [[ -n "$CURRENT_WS" ]] && hyprctl dispatch workspace "$CURRENT_WS" 2>/dev/null
    fi

    # Restore dimmer if it drifted
    SAVED_DIM=$(cat "$DIMMER_CACHE" 2>/dev/null)
    if [[ -n "$SAVED_DIM" && "$SAVED_DIM" != "0" ]]; then
        CURRENT_DIM=$(eww get dimmer-level 2>/dev/null)
        [[ "$SAVED_DIM" != "$CURRENT_DIM" ]] && eww update dimmer-level="$SAVED_DIM" 2>/dev/null
    fi

    # If no sensor panel is open, try to open one (but never close+reopen)
    if ! eww active-windows 2>/dev/null | grep -q "sensor-panel"; then
        ~/.config/hypr/scripts/sensor-panel.sh 2>/dev/null &
        continue
    fi

    # If panel is on wrong monitor (Y < 1000 means it's on primary), fix it
    PANEL_Y=$(hyprctl layers 2>/dev/null | grep "hypr-os-sensor" | head -1 | grep -oP 'xywh: \d+ \K\d+')
    if [[ -n "$PANEL_Y" ]] && (( PANEL_Y < 1000 )); then
        ~/.config/hypr/scripts/sensor-panel.sh 2>/dev/null &
    fi
done
