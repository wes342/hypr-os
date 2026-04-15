#!/usr/bin/env bash
# Screenshot helper.
#   screenshot.sh region      -- draw a region with slurp
#   screenshot.sh fullscreen  -- capture all outputs
#   screenshot.sh window      -- capture active window
#
# Second arg "clip" puts the image on the Wayland clipboard only,
# skipping both the disk save and satty (useful for pasting into a
# chat without cluttering ~/Pictures/Screenshots). Default is to
# save+copy+notify+open satty.

set -euo pipefail

MODE="${1:-region}"
SINK="${2:-save}"

capture_to_stdout() {
    case "$MODE" in
        region)
            local geom
            geom=$(slurp 2>/dev/null) || return 1
            grim -g "$geom" -
            ;;
        fullscreen)
            grim -
            ;;
        window)
            local geom
            geom=$(hyprctl -j activewindow \
                | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
            grim -g "$geom" -
            ;;
        *)
            echo "Usage: $0 {region|fullscreen|window} [clip]" >&2
            return 2
            ;;
    esac
}

if [[ "$SINK" == "clip" ]]; then
    # Clipboard only -- no file, no annotation.
    if ! capture_to_stdout | wl-copy; then
        exit 0   # user cancelled slurp, etc.
    fi
    notify-send -t 2000 "Screenshot copied" \
        "Ready to paste" 2>/dev/null || true
    exit 0
fi

OUT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
OUT="$OUT_DIR/screenshot-$STAMP.png"

if ! capture_to_stdout > "$OUT"; then
    rm -f "$OUT"
    exit 0
fi

# Copy to the Wayland clipboard.
wl-copy < "$OUT" || true

# Notify, with the screenshot itself as the icon for a thumbnail preview.
notify-send -t 3500 \
    "Screenshot saved" \
    "$(basename "$OUT")" \
    -i "$OUT" 2>/dev/null || true

# Optional annotation pass.
if command -v satty &>/dev/null; then
    satty --filename "$OUT" \
          --output-filename "$OUT" \
          --copy-command wl-copy \
          --early-exit &
    disown
fi
