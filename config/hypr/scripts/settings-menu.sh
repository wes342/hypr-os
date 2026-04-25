#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Settings menu -- rofi-based nested      │
# │  menu for hypr-os customization.         │
# └──────────────────────────────────────────┘

set -euo pipefail

THEME="$HOME/.config/rofi/dmenu.rasi"
HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"
FASTFETCH_LOGO="$HOME/.config/fastfetch/logo.png"
TERMINAL="${TERMINAL:-kitty}"

# Logo dimensions (characters) -- must match fastfetch config.jsonc
LOGO_WIDTH_CHARS=40
LOGO_HEIGHT_CHARS=20
LOGO_WIDTH_PX=$(( LOGO_WIDTH_CHARS * 8 ))
LOGO_HEIGHT_PX=$(( LOGO_HEIGHT_CHARS * 16 ))

rofi_menu() {
    rofi -dmenu -i -theme "$THEME" -matching fuzzy "$@"
}

notify() {
    notify-send -t 3000 "Settings" "$1" 2>/dev/null || true
}

# ── Native file picker (GTK4 via python) ─

pick_image_native() {
    python3 -c "
import gi, sys
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, Gio, GLib

def on_response(dialog, result):
    try:
        f = dialog.open_finish(result)
        print(f.get_path())
    except Exception:
        pass
    loop.quit()

app = Gtk.Application(application_id='dev.hypros.filepicker',
                      flags=Gio.ApplicationFlags.NON_UNIQUE)

def on_activate(app):
    global loop
    win = Gtk.ApplicationWindow(application=app)
    win.set_default_size(1, 1)
    win.present()

    dialog = Gtk.FileDialog()
    dialog.set_title('Select Terminal Image')

    # Image filter
    img_filter = Gtk.FileFilter()
    img_filter.set_name('Images')
    img_filter.add_mime_type('image/png')
    img_filter.add_mime_type('image/jpeg')
    img_filter.add_mime_type('image/webp')

    filters = Gio.ListStore.new(Gtk.FileFilter)
    filters.append(img_filter)
    dialog.set_filters(filters)
    dialog.set_default_filter(img_filter)

    # Start in wallpaper directory
    dialog.set_initial_folder(Gio.File.new_for_path('$HOME/Pictures/Wallpaper'))

    dialog.open(win, None, on_response)

app.connect('activate', on_activate)
app.run(None)
" 2>/dev/null
}

# ── Terminal Image picker ────────────────

pick_terminal_image() {
    local chosen
    chosen=$(pick_image_native)

    [[ -z "$chosen" || ! -f "$chosen" ]] && return

    # Resize to fit fastfetch logo dimensions and save
    magick "$chosen" \
        -resize "${LOGO_WIDTH_PX}x${LOGO_HEIGHT_PX}^" \
        -gravity center \
        -extent "${LOGO_WIDTH_PX}x${LOGO_HEIGHT_PX}" \
        -strip \
        "$FASTFETCH_LOGO" 2>/dev/null || {
        notify "Failed to process image."
        return
    }

    notify "Terminal image set to: $(basename "$chosen")"

    # Show preview in a new terminal
    setsid -f "$TERMINAL" --title "fastfetch" --class "eye-candy" \
        -e bash -c 'fastfetch; echo ""; echo "Press any key to close."; read -rsn1' \
        >/dev/null 2>&1
}

# ── Category: Theme ──────────────────────

menu_theme() {
    local OPTS=(
        "󰋩  Terminal Image"
    )

    local choice
    choice=$(printf '%s\n' "${OPTS[@]}" | rofi_menu -p "  Theme") || return

    case "$choice" in
        *Terminal\ Image*) pick_terminal_image ;;
    esac
}

# ── Main menu ────────────────────────────

CATEGORIES=(
    "  Theme"
)

CHOICE=$(printf '%s\n' "${CATEGORIES[@]}" | rofi_menu -p "  Settings") || exit 0

case "$CHOICE" in
    *Theme*) menu_theme ;;
esac
