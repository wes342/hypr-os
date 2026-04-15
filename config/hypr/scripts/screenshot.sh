#!/usr/bin/env bash
# Screenshot helper.
#   screenshot.sh region      -- draw a region with slurp
#   screenshot.sh fullscreen  -- capture all outputs
#   screenshot.sh window      -- capture active window
#
# Always saves a timestamped PNG to ~/Pictures/Screenshots, copies it
# to the clipboard, and (if satty is installed) opens it for
# annotation. The saved file is retained even if the user cancels
# satty, so a screenshot is never "lost".

set -euo pipefail

MODE="${1:-region}"
OUT_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$OUT_DIR"
STAMP=$(date +%Y-%m-%d_%H-%M-%S)
OUT="$OUT_DIR/screenshot-$STAMP.png"

case "$MODE" in
    region)
        GEOM=$(slurp 2>/dev/null) || exit 0   # user cancelled
        grim -g "$GEOM" "$OUT"
        ;;
    fullscreen)
        grim "$OUT"
        ;;
    window)
        GEOM=$(hyprctl -j activewindow \
            | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')
        grim -g "$GEOM" "$OUT"
        ;;
    *)
        echo "Usage: $0 {region|fullscreen|window}" >&2
        exit 2
        ;;
esac

# Copy to the Wayland clipboard.
wl-copy < "$OUT" || true

# Notify, with the screenshot itself as the icon for a thumbnail preview.
notify-send -t 3500 \
    "Screenshot saved" \
    "$(basename "$OUT")" \
    -i "$OUT" 2>/dev/null || true

# Optional annotation pass.
if command -v satty &>/dev/null; then
    # --early-exit closes satty on save, --copy-command re-copies the
    # annotated version, --output-filename writes over the original
    # if the user chooses Save.
    satty --filename "$OUT" \
          --output-filename "$OUT" \
          --copy-command wl-copy \
          --early-exit &
    disown
fi
