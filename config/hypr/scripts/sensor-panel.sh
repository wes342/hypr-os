#!/usr/bin/env bash
# Open the eww sensor panel on HDMI-A-2 only.
# Tries sensor-panel-0 and sensor-panel-1 to find which eww monitor
# index maps to HDMI-A-2, then keeps only the correct one open.

SENSOR_NAME="HDMI-A-2"
PRIMARY_NAME="DP-3"

# Check if sensor monitor is connected
SENSOR_Y=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$SENSOR_NAME\") | .y")
PRIMARY_Y=$(hyprctl monitors -j 2>/dev/null | jq -r ".[] | select(.name==\"$PRIMARY_NAME\") | .y")
if [[ -z "$SENSOR_Y" || "$SENSOR_Y" == "null" ]]; then
    eww close sensor-panel-0 sensor-panel-1 2>/dev/null
    exit 0
fi

# Helper: check if panel Y is on the sensor monitor (not the primary)
on_sensor() {
    local py="$1"
    [[ -z "$py" ]] && return 1
    # Panel is on sensor if its Y is NOT near the primary monitor
    (( py > PRIMARY_Y + 1000 ))
}

# Close any existing panels
eww close sensor-panel-0 sensor-panel-1 2>/dev/null
sleep 0.3

# Try monitor index 0
eww open sensor-panel-0 2>/dev/null
sleep 0.5
PANEL_Y=$(hyprctl layers 2>/dev/null | grep -A0 "hypr-os-sensor" | grep -oP 'xywh: \d+ \K\d+')

if on_sensor "$PANEL_Y"; then
    sleep 1
    ~/.config/hypr/scripts/sensor-brightness.sh restore 2>/dev/null
    exit 0
fi

# Wrong monitor, try index 1
eww close sensor-panel-0 2>/dev/null
sleep 0.3
eww open sensor-panel-1 2>/dev/null
sleep 0.5
PANEL_Y=$(hyprctl layers 2>/dev/null | grep -A0 "hypr-os-sensor" | grep -oP 'xywh: \d+ \K\d+')

if on_sensor "$PANEL_Y"; then
    sleep 1
    ~/.config/hypr/scripts/sensor-brightness.sh restore 2>/dev/null
    exit 0
fi

# Neither worked, close everything
eww close sensor-panel-0 sensor-panel-1 2>/dev/null
echo "Could not place sensor panel on $SENSOR_NAME" >&2
