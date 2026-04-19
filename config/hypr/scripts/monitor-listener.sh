#!/usr/bin/env bash
# Periodically ensures no windows are on the sensor panel monitor.
# Runs every 3 seconds - lightweight check, only acts if needed.

SENSOR="HDMI-A-2"
PRIMARY="DP-3"

while true; do
    sleep 3

    # Skip if primary not connected
    hyprctl monitors -j 2>/dev/null | jq -e ".[] | select(.name==\"$PRIMARY\")" >/dev/null 2>&1 || continue

    # Get sensor monitor ID
    SENSOR_ID=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$SENSOR\") | .id")
    [[ -z "$SENSOR_ID" ]] && continue

    # Move any workspaces stuck on sensor monitor to primary
    STRAY_WS=$(hyprctl workspaces -j 2>/dev/null | jq -r ".[] | select(.monitor==\"$SENSOR\" and .id != 11) | .id")
    for ws in $STRAY_WS; do
        hyprctl dispatch moveworkspacetomonitor "$ws" "$PRIMARY" 2>/dev/null
    done

    # Move any windows stuck on sensor monitor
    STRAY_WIN=$(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.monitor==$SENSOR_ID) | .address")
    for addr in $STRAY_WIN; do
        hyprctl dispatch movetoworkspacesilent "1,address:$addr" 2>/dev/null
    done
done
