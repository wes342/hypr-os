#!/usr/bin/env bash
# Toggle app launcher. The GTK4 app stays resident after first launch
# so subsequent opens are instant via D-Bus re-activation (~20ms).

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
APP_ID="dev.hypros.launcher"
DBUS_PATH="/${APP_ID//\.//}"

# Try D-Bus activation (instant if app is pre-warmed)
if dbus-send --session --print-reply --type=method_call \
    --dest="$APP_ID" "$DBUS_PATH" \
    org.freedesktop.Application.Activate \
    dict:string:variant: &>/dev/null; then
    exit 0
fi

# App not running yet — cold start
python3 "$HYPR_OS_DIR/scripts/launcher-app.py" &
disown
