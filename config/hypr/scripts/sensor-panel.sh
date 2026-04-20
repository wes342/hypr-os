#!/usr/bin/env bash
# Open the eww sensor panel on HDMI-A-2 only.
# Tries sensor-panel-0 and sensor-panel-1 to find which eww monitor
# index maps to HDMI-A-2, then keeps only the correct one open.
# Will NOT close a panel that's already on the correct monitor.

SENSOR_NAME="HDMI-A-2"
PRIMARY_NAME="DP-3"

# Check if sensor monitor is connected
SENSOR_Y=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$SENSOR_NAME\") | .y")
if [[ -z "$SENSOR_Y" || "$SENSOR_Y" == "null" ]]; then
    eww close sensor-panel-0 sensor-panel-1 2>/dev/null
    exit 0
fi

# If a panel is already open and on the sensor monitor, do nothing
if eww active-windows 2>/dev/null | grep -q "sensor-panel"; then
    PANEL_Y=$(hyprctl layers 2>/dev/null | grep "hypr-os-sensor" | head -1 | grep -oP 'xywh: \d+ \K\d+')
    if [[ -n "$PANEL_Y" ]] && (( PANEL_Y > 1000 )); then
        # Already on correct monitor
        exit 0
    fi
fi

# Close any panels on the wrong monitor
eww close sensor-panel-0 sensor-panel-1 2>/dev/null
sleep 0.3

# Try monitor index 0
eww open sensor-panel-0 2>/dev/null
sleep 0.5
PANEL_Y=$(hyprctl layers 2>/dev/null | grep "hypr-os-sensor" | head -1 | grep -oP 'xywh: \d+ \K\d+')

if [[ -n "$PANEL_Y" ]] && (( PANEL_Y > 1000 )); then
    sleep 1
    ~/.config/hypr/scripts/sensor-brightness.sh restore 2>/dev/null
    exit 0
fi

# Wrong monitor, try index 1
eww close sensor-panel-0 2>/dev/null
sleep 0.3
eww open sensor-panel-1 2>/dev/null
sleep 0.5
PANEL_Y=$(hyprctl layers 2>/dev/null | grep "hypr-os-sensor" | head -1 | grep -oP 'xywh: \d+ \K\d+')

if [[ -n "$PANEL_Y" ]] && (( PANEL_Y > 1000 )); then
    sleep 1
    ~/.config/hypr/scripts/sensor-brightness.sh restore 2>/dev/null
    exit 0
fi

# Neither worked, close everything
eww close sensor-panel-0 sensor-panel-1 2>/dev/null
echo "Could not place sensor panel on $SENSOR_NAME" >&2
