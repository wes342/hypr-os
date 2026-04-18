#!/usr/bin/env bash
# Toggle rofi launcher -- if running, kill it; otherwise launch it.
# Reads the current wallpaper + theme colors fresh every launch so
# it always matches the latest theme, even if colors.rasi hasn't
# been reloaded yet.

LOCKFILE="/tmp/hypr-os-launcher.lock"
COLORS_CSS="$HOME/.config/waybar/colors.css"

if [[ -f "$LOCKFILE" ]]; then
    pkill -x rofi 2>/dev/null
    rm -f "$LOCKFILE"
    exit 0
fi

touch "$LOCKFILE"

# Read current wallpaper
WALLPAPER=$(cat "$HOME/.cache/hypr/current_wallpaper" 2>/dev/null || echo "")

# Read live accent colors from the latest colors.css
read_color() {
    grep -oP "@define-color\\s+$1\\s+#\\K[0-9a-fA-F]{6}" "$COLORS_CSS" 2>/dev/null | head -1
}
ACCENT="#$(read_color accent)"
ACCENT_DIM="#$(read_color accent_dim)"
FG="#$(read_color fg)"
FG_DIM="#$(read_color fg_dim)"
[[ "$ACCENT" == "#" ]] && ACCENT="#7aa2f7"
[[ "$ACCENT_DIM" == "#" ]] && ACCENT_DIM="#3d59a1"
[[ "$FG" == "#" ]] && FG="#c0caf5"
[[ "$FG_DIM" == "#" ]] && FG_DIM="#565f89"

# Build live theme overrides
THEME_STR=""
if [[ -n "$WALLPAPER" && -f "$WALLPAPER" ]]; then
    THEME_STR+="window { background-image: url(\"$WALLPAPER\", width); }"
fi
THEME_STR+=" window { border-color: ${ACCENT_DIM}; }"
THEME_STR+=" * { text-color: ${FG}; }"
THEME_STR+=" prompt { text-color: ${ACCENT}; }"
THEME_STR+=" entry { placeholder-color: ${FG_DIM}; }"
THEME_STR+=" element selected.normal { border-color: ${ACCENT}; }"

rofi -show drun -show-icons -theme-str "$THEME_STR"

rm -f "$LOCKFILE"
