#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Theme Generator -- extract colors from  │
# │  wallpaper and apply to all apps         │
# └──────────────────────────────────────────┘

set -euo pipefail

WALLPAPER="${1:-$(cat ~/.cache/hypr/current_wallpaper 2>/dev/null || echo '')}"
CONFIG_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}/config"

if [[ -z "$WALLPAPER" || ! -f "$WALLPAPER" ]]; then
    echo "No wallpaper specified or found in cache."
    exit 1
fi

if ! command -v magick &>/dev/null; then
    echo "imagemagick not installed -- skipping theme generation."
    echo "Install with: sudo pacman -S imagemagick"
    notify-send -t 5000 "Theme" "Install imagemagick for dynamic theming: sudo pacman -S imagemagick" 2>/dev/null || true
    exit 0
fi

echo "Extracting colors from: $WALLPAPER"

# Extract 16 dominant colors using ImageMagick
# Resize first for speed, then quantize to 16 colors
COLORS=$(magick "$WALLPAPER" -resize 400x400^ -colors 16 -unique-colors -depth 8 txt:- \
    | grep -oP '#[0-9A-Fa-f]{6}' \
    | head -16)

COLOR_ARRAY=()
while IFS= read -r c; do
    COLOR_ARRAY+=("$c")
done <<< "$COLORS"

# Ensure we have enough colors (pad with defaults if needed)
while [[ ${#COLOR_ARRAY[@]} -lt 16 ]]; do
    COLOR_ARRAY+=("#282828")
done

# Sort colors by luminance (dark to light)
sorted_colors=$(for c in "${COLOR_ARRAY[@]}"; do
    r=$((16#${c:1:2}))
    g=$((16#${c:3:2}))
    b=$((16#${c:5:2}))
    lum=$(( (r * 299 + g * 587 + b * 114) / 1000 ))
    echo "$lum $c"
done | sort -n | awk '{print $2}')

SORTED=()
while IFS= read -r c; do
    SORTED+=("$c")
done <<< "$sorted_colors"

# Assign color roles
bg="${SORTED[0]}"
bg_dim="${SORTED[1]}"
bg_highlight="${SORTED[2]}"
accent_dim="${SORTED[3]}"
accent="${SORTED[$(( ${#SORTED[@]} / 2 ))]}"
fg_dim="${SORTED[$(( ${#SORTED[@]} - 3 ))]}"
fg="${SORTED[$(( ${#SORTED[@]} - 2 ))]}"
fg_bright="${SORTED[$(( ${#SORTED[@]} - 1 ))]}"

# Map 16 terminal colors (dark variant first, then bright)
color0="$bg"
color8="$bg_highlight"
color1="${SORTED[3]}"
color9="${SORTED[4]}"
color2="${SORTED[5]}"
color10="${SORTED[6]}"
color3="${SORTED[7]}"
color11="${SORTED[8]}"
color4="${SORTED[9]}"
color12="${SORTED[10]}"
color5="${SORTED[11]}"
color13="${SORTED[12]}"
color6="${SORTED[13]}"
color14="${SORTED[14]}"
color7="$fg"
color15="$fg_bright"

strip_hash() { echo "${1#\#}"; }

# ── Contrast enforcement ────────────────────
# Ensure text colors are readable against the background.
# Uses WCAG relative luminance and adjusts brightness while
# preserving the original hue from the wallpaper.

# Calculate relative luminance (0.0 - 1.0) for a hex color
rel_luminance() {
    local hex="$1"
    local ri=$(printf '%d' "0x${hex:1:2}")
    local gi=$(printf '%d' "0x${hex:3:2}")
    local bi=$(printf '%d' "0x${hex:5:2}")
    awk -v r="$ri" -v g="$gi" -v b="$bi" '
    BEGIN {
        rs = r/255; gs = g/255; bs = b/255
        rl = (rs <= 0.03928) ? rs/12.92 : ((rs+0.055)/1.055)^2.4
        gl = (gs <= 0.03928) ? gs/12.92 : ((gs+0.055)/1.055)^2.4
        bl = (bs <= 0.03928) ? bs/12.92 : ((bs+0.055)/1.055)^2.4
        printf "%.6f", 0.2126*rl + 0.7152*gl + 0.0722*bl
    }'
}

# Contrast ratio between two hex colors (returns float like "4.5")
contrast_ratio() {
    local l1 l2
    l1=$(rel_luminance "$1")
    l2=$(rel_luminance "$2")
    awk -v a="$l1" -v b="$l2" 'BEGIN {
        if (a > b) printf "%.2f", (a + 0.05) / (b + 0.05)
        else       printf "%.2f", (b + 0.05) / (a + 0.05)
    }'
}

# Adjust a color's brightness toward white or black until it meets
# the minimum contrast ratio against bg_color. Preserves hue.
# Usage: enforce_contrast <fg_hex> <bg_hex> <min_ratio>
enforce_contrast() {
    local fg_hex="$1" bg_hex="$2" min_ratio="$3"
    local bg_lum
    bg_lum=$(rel_luminance "$bg_hex")

    # Determine if we should lighten or darken fg
    local direction
    direction=$(awk -v bl="$bg_lum" 'BEGIN { print (bl < 0.5) ? "lighten" : "darken" }')

    local r g b best="$fg_hex"
    r=$(printf '%d' "0x${fg_hex:1:2}")
    g=$(printf '%d' "0x${fg_hex:3:2}")
    b=$(printf '%d' "0x${fg_hex:5:2}")

    local step=0
    while (( step < 20 )); do
        local ratio
        ratio=$(contrast_ratio "$best" "$bg_hex")
        local pass
        pass=$(awk -v r="$ratio" -v m="$min_ratio" 'BEGIN { print (r >= m) ? 1 : 0 }')
        [[ "$pass" == "1" ]] && break

        if [[ "$direction" == "lighten" ]]; then
            r=$(( r + (255 - r) / 4 ))
            g=$(( g + (255 - g) / 4 ))
            b=$(( b + (255 - b) / 4 ))
        else
            r=$(( r * 3 / 4 ))
            g=$(( g * 3 / 4 ))
            b=$(( b * 3 / 4 ))
        fi

        (( r > 255 )) && r=255; (( g > 255 )) && g=255; (( b > 255 )) && b=255
        (( r < 0 )) && r=0; (( g < 0 )) && g=0; (( b < 0 )) && b=0

        best=$(printf '#%02X%02X%02X' "$r" "$g" "$b")
        step=$((step + 1))
    done

    echo "$best"
}

# Enforce contrast on fg, fg_dim, and terminal palette colors
MIN_CONTRAST="4.5"
MIN_CONTRAST_DIM="3.0"

fg=$(enforce_contrast "$fg" "$bg" "$MIN_CONTRAST")
fg_dim=$(enforce_contrast "$fg_dim" "$bg" "$MIN_CONTRAST_DIM")
fg_bright=$(enforce_contrast "$fg_bright" "$bg" "$MIN_CONTRAST")

# Terminal palette: enforce contrast for the 6 main colors (normal + bright)
# Skip color0/color8 (blacks) and color7/color15 (whites) — those are bg/fg
color1=$(enforce_contrast "$color1" "$bg" "$MIN_CONTRAST_DIM")
color2=$(enforce_contrast "$color2" "$bg" "$MIN_CONTRAST_DIM")
color3=$(enforce_contrast "$color3" "$bg" "$MIN_CONTRAST_DIM")
color4=$(enforce_contrast "$color4" "$bg" "$MIN_CONTRAST_DIM")
color5=$(enforce_contrast "$color5" "$bg" "$MIN_CONTRAST_DIM")
color6=$(enforce_contrast "$color6" "$bg" "$MIN_CONTRAST_DIM")
color9=$(enforce_contrast "$color9" "$bg" "$MIN_CONTRAST")
color10=$(enforce_contrast "$color10" "$bg" "$MIN_CONTRAST")
color11=$(enforce_contrast "$color11" "$bg" "$MIN_CONTRAST")
color12=$(enforce_contrast "$color12" "$bg" "$MIN_CONTRAST")
color13=$(enforce_contrast "$color13" "$bg" "$MIN_CONTRAST")
color14=$(enforce_contrast "$color14" "$bg" "$MIN_CONTRAST")

# Update color7/15 to match adjusted fg
color7="$fg"
color15="$fg_bright"

# ── Hyprland theme.conf ──────────────────
cat > "$CONFIG_DIR/hypr/theme.conf" << EOF
# Auto-generated by theme.sh from: $(basename "$WALLPAPER")
\$bg = rgb($(strip_hash "$bg"))
\$bg_dim = rgb($(strip_hash "$bg_dim"))
\$bg_highlight = rgb($(strip_hash "$bg_highlight"))
\$fg = rgb($(strip_hash "$fg"))
\$fg_dim = rgb($(strip_hash "$fg_dim"))
\$accent = rgb($(strip_hash "$accent"))
\$accent_dim = rgb($(strip_hash "$accent_dim"))

general {
    col.active_border = \$accent \$accent 45deg
    col.inactive_border = \$accent_dim
}
EOF

# ── Kitty theme ──────────────────────────
cat > "$CONFIG_DIR/kitty/current-theme.conf" << EOF
# Auto-generated by theme.sh
foreground                      $fg
background                      $bg
selection_foreground            $bg
selection_background            $accent
cursor                          $fg
cursor_text_color               $bg
url_color                       $accent
active_border_color             $accent
inactive_border_color           $accent_dim
active_tab_background           $bg_highlight
active_tab_foreground           $fg
inactive_tab_background         $bg
inactive_tab_foreground         $fg_dim
tab_bar_background              $bg_dim

color0                          $color0
color8                          $color8
color1                          $color1
color9                          $color9
color2                          $color2
color10                         $color10
color3                          $color3
color11                         $color11
color4                          $color4
color12                         $color12
color5                          $color5
color13                         $color13
color6                          $color6
color14                         $color14
color7                          $color7
color15                         $color15
EOF

# ── Ghostty theme ────────────────────────
# Write ONLY the palette to theme.conf. The static config lives in
# config/ghostty/config (unchanged on theme updates) and imports this
# file via `config-file = ?theme.conf`.
if [[ -d "$CONFIG_DIR/ghostty" ]]; then
cat > "$CONFIG_DIR/ghostty/theme.conf" << EOF
# Auto-generated by theme.sh
background = $bg
foreground = $fg
cursor-color = $fg
selection-background = $accent
selection-foreground = $bg
palette = 0=$color0
palette = 1=$color1
palette = 2=$color2
palette = 3=$color3
palette = 4=$color4
palette = 5=$color5
palette = 6=$color6
palette = 7=$color7
palette = 8=$color8
palette = 9=$color9
palette = 10=$color10
palette = 11=$color11
palette = 12=$color12
palette = 13=$color13
palette = 14=$color14
palette = 15=$color15
EOF
fi

# ── Alacritty colors ─────────────────────
if [[ -d "$CONFIG_DIR/alacritty" ]]; then
cat > "$CONFIG_DIR/alacritty/colors.toml" << EOF
# Auto-generated by theme.sh from: $(basename "$WALLPAPER")

[colors.primary]
background = "$bg"
foreground = "$fg"

[colors.cursor]
text   = "$bg"
cursor = "$fg"

[colors.selection]
text       = "$bg"
background = "$accent"

[colors.normal]
black   = "$color0"
red     = "$color1"
green   = "$color2"
yellow  = "$color3"
blue    = "$color4"
magenta = "$color5"
cyan    = "$color6"
white   = "$color7"

[colors.bright]
black   = "$color8"
red     = "$color9"
green   = "$color10"
yellow  = "$color11"
blue    = "$color12"
magenta = "$color13"
cyan    = "$color14"
white   = "$color15"
EOF
fi

# ── Waybar colors ────────────────────────
cat > "$CONFIG_DIR/waybar/colors.css" << EOF
/* Auto-generated by theme.sh */
@define-color bg $bg;
@define-color bg_dim $bg_dim;
@define-color bg_highlight $bg_highlight;
@define-color fg $fg;
@define-color fg_dim $fg_dim;
@define-color accent $accent;
@define-color accent_dim $accent_dim;
EOF

# ── Rofi colors ──────────────────────────
cat > "$CONFIG_DIR/rofi/colors.rasi" << EOF
/* Auto-generated by theme.sh */
* {
    bg:             $bg;
    bg-dim:         $bg_dim;
    bg-highlight:   $bg_highlight;
    fg:             $fg;
    fg-dim:         $fg_dim;
    accent:         $accent;
    accent-dim:     $accent_dim;
}
EOF

# ── Cava colors ──────────────────────────
mkdir -p "$CONFIG_DIR/cava"
cat > "$CONFIG_DIR/cava/config" << EOF
# Auto-generated by theme.sh
[general]
framerate = 60
bars = 0
bar_width = 2
bar_spacing = 1

[color]
gradient = 1
gradient_count = 4
gradient_color_1 = '$(strip_hash "$accent_dim")'
gradient_color_2 = '$(strip_hash "$accent")'
gradient_color_3 = '$(strip_hash "$fg_dim")'
gradient_color_4 = '$(strip_hash "$fg")'
EOF

# ── SwayNC colors ────────────────────────
mkdir -p "$CONFIG_DIR/swaync"
cat > "$CONFIG_DIR/swaync/colors.css" << EOF
/* Auto-generated by theme.sh */
@define-color bg $bg;
@define-color bg_dim $bg_dim;
@define-color bg_highlight $bg_highlight;
@define-color fg $fg;
@define-color fg_dim $fg_dim;
@define-color accent $accent;
@define-color accent_dim $accent_dim;
EOF

# ── Eww colors (waybar dropdowns) ────────
mkdir -p "$CONFIG_DIR/eww"
cat > "$CONFIG_DIR/eww/colors.css" << EOF
/* Auto-generated by theme.sh */
@define-color bg            $bg;
@define-color bg_dim        $bg_dim;
@define-color bg_highlight  $bg_highlight;
@define-color fg            $fg;
@define-color fg_dim        $fg_dim;
@define-color accent        $accent;
@define-color accent_dim    $accent_dim;
@define-color ok            $color2;
@define-color warm          $color3;
@define-color critical      $color1;
EOF

# ── btop theme ───────────────────────────
mkdir -p "$HOME/.config/btop/themes"
cat > "$HOME/.config/btop/themes/hypr-os.theme" << EOF
# Auto-generated by theme.sh

# Main background, empty for terminal default (uses terminal bg for transparency)
theme[main_bg]=""

# Main text color
theme[main_fg]="$fg"

# Title color for boxes
theme[title]="$fg"

# Highlight color for keyboard shortcuts
theme[hi_fg]="$accent"

# Background color of selected item
theme[selected_bg]="$accent"

# Foreground color of selected item
theme[selected_fg]="$bg"

# Color of inactive/disabled text
theme[inactive_fg]="$fg_dim"

# Color of text on top of graphs
theme[graph_text]="$fg"

# Background color of percentage meters
theme[meter_bg]="$bg_highlight"

# Misc colors for processes box
theme[proc_misc]="$accent"

# Box outline colors
theme[cpu_box]="$accent"
theme[mem_box]="$color2"
theme[net_box]="$color4"
theme[proc_box]="$color5"

# Divider line color
theme[div_line]="$accent_dim"

# Temperature graph colors
theme[temp_start]="$color2"
theme[temp_mid]="$color3"
theme[temp_end]="$color1"

# CPU graph colors
theme[cpu_start]="$color2"
theme[cpu_mid]="$color3"
theme[cpu_end]="$color1"

# Memory graph colors
theme[free_start]="$color4"
theme[free_mid]="$color12"
theme[free_end]="$accent"
theme[cached_start]="$color6"
theme[cached_mid]="$color14"
theme[cached_end]="$accent"
theme[available_start]="$color2"
theme[available_mid]="$color10"
theme[available_end]="$accent"
theme[used_start]="$color3"
theme[used_mid]="$color11"
theme[used_end]="$color1"

# Network graph colors
theme[download_start]="$color2"
theme[download_mid]="$color4"
theme[download_end]="$accent"
theme[upload_start]="$color5"
theme[upload_mid]="$color1"
theme[upload_end]="$color9"

# Process graph colors
theme[process_start]="$accent"
theme[process_mid]="$fg_dim"
theme[process_end]="$accent_dim"
EOF

# Set btop to use hypr-os theme (update config if it exists)
BTOP_CONF="$HOME/.config/btop/btop.conf"
if [[ -f "$BTOP_CONF" ]]; then
    sed -i 's/^color_theme = .*/color_theme = "hypr-os"/' "$BTOP_CONF"
    # Disable theme background so terminal transparency works
    sed -i 's/^theme_background = .*/theme_background = false/' "$BTOP_CONF"
fi

# ── SDDM theme (hypr-os) ─────────────────
# Regenerates the greeter's theme.conf so the login screen matches the
# current wallpaper. Only writes if the theme dir exists.
if [[ -d "$CONFIG_DIR/sddm/hypr-os" ]]; then
cat > "$CONFIG_DIR/sddm/hypr-os/theme.conf" << EOF
[General]
# Auto-generated by theme.sh
background=$WALLPAPER
bg=$bg
bg_dim=$bg_dim
bg_highlight=$bg_highlight
fg=$fg
fg_dim=$fg_dim
accent=$accent
accent_dim=$accent_dim
font=Iosevka Nerd Font
EOF
    # install-sddm-theme.sh symlinks /usr/share/sddm/themes/hypr-os
    # to this directory, so the login greeter picks this file up
    # directly on next boot — no sudo needed at re-theme time.
fi

echo "Theme applied from: $(basename "$WALLPAPER")"
echo "  bg=$bg  fg=$fg  accent=$accent"

# ── Reload apps ──────────────────────────
# Hyprland (border colors from theme.conf)
hyprctl reload 2>/dev/null || true

# Waybar
pkill waybar 2>/dev/null || true; sleep 0.2; waybar &>/dev/null &

# Close rofi so next open picks up the new wallpaper + colors
pkill -x rofi 2>/dev/null || true
rm -f /tmp/hypr-os-launcher.lock

# SwayNC
swaync-client -rs 2>/dev/null || true

# Kitty (SIGUSR1 triggers config reload)
pkill -USR1 kitty 2>/dev/null || true

# Ghostty: SIGUSR1 terminates the process, so don't send signals. New
# windows pick up the imported theme.conf automatically. Users can
# trigger a live reload in existing ghostty windows with the default
# keybind Ctrl+Shift+,

# Cava
pkill -USR2 cava 2>/dev/null || true

# btop: no signal reload support — picks up new theme on next launch

# Eww sensor panel — reload to pick up new colors.css, reopen on correct monitor
if pgrep -x eww >/dev/null 2>&1; then
    eww close sensor-panel-0 sensor-panel-1 2>/dev/null || true
    eww reload 2>/dev/null || true
    (sleep 1 && ~/.config/hypr/scripts/sensor-panel.sh) &
fi

# Notify
notify-send -t 3000 "Theme Updated" "Colors extracted from $(basename "$WALLPAPER")" 2>/dev/null || true

echo "Done."
