#!/usr/bin/env python3
"""
hypr-os App Launcher — GTK4 + Adwaita.

Replaces rofi drun with a themed launcher featuring:
  - Blurred wallpaper on the left
  - Quick-launch icon sidebar (terminal, files, browser)
  - Searchable app grid on the right
  - Full keyboard navigation (type to search, Enter to launch, Esc to close)
"""

import os
import re
import subprocess
import sys
import threading
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, Gtk, Pango

# ── Paths ──
HOME = Path.home()
COLORS_CSS = HOME / ".config" / "waybar" / "colors.css"
CACHE_DIR = HOME / ".cache" / "hypr-os"
BLUR_CACHE = CACHE_DIR / "wallpaper-blur.png"
CURRENT_WP = HOME / ".cache" / "hypr" / "current_wallpaper"

# ── Quick-launch sidebar apps ──
# (nerd_font_icon, tooltip, command, font_size_px)
SIDEBAR_APPS = [
    ("\ue795", "Terminal", ["kitty"], 29),
    ("\uf07b", "Files", ["thunar"], 26),
    ("\U000f0239", "Browser", ["firefox"], 29),
]


# ── Helpers ──

def hex_to_rgba(hex_color, alpha):
    """Convert #RRGGBB to rgba(r, g, b, alpha)."""
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r}, {g}, {b}, {alpha})"


def read_color(name, fallback):
    if COLORS_CSS.exists():
        m = re.search(
            rf"@define-color\s+{re.escape(name)}\s+(#[0-9a-fA-F]{{6}})",
            COLORS_CSS.read_text(),
        )
        if m:
            return m.group(1)
    return fallback


def get_wallpaper():
    if CURRENT_WP.exists():
        p = CURRENT_WP.read_text().strip()
        if p and Path(p).exists():
            return p
    return ""


def ensure_blur(wallpaper):
    """Create a blurred + darkened version of the wallpaper, cached."""
    if not wallpaper:
        return None
    wp_mtime = int(Path(wallpaper).stat().st_mtime)
    cache_key = f"{wallpaper}:{wp_mtime}"
    marker = CACHE_DIR / "blur-mtime.txt"
    if BLUR_CACHE.exists() and marker.exists():
        try:
            if marker.read_text().strip() == cache_key:
                return str(BLUR_CACHE)
        except Exception:
            pass
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["magick", wallpaper,
         "-resize", "800x600^",
         "-gravity", "center", "-extent", "800x600",
         "-blur", "0x5",
         "-brightness-contrast", "-20x-10",
         str(BLUR_CACHE)],
        capture_output=True, timeout=5,
    )
    marker.write_text(cache_key)
    return str(BLUR_CACHE) if BLUR_CACHE.exists() else None


# ── App listing ──

def get_all_apps():
    """Get launchable desktop apps, sorted by display name."""
    apps = []
    for app in Gio.AppInfo.get_all():
        if not app.should_show():
            continue
        name = app.get_display_name()
        icon = app.get_icon()
        apps.append((name, icon, app))
    apps.sort(key=lambda x: x[0].lower())
    return apps


# ── Launcher App ──

class LauncherApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="dev.hypros.launcher")
        self._win = None
        self._start_hidden = False
        self._css_provider = None
        self._bg_pic = None
        # Pre-cache apps at init time
        self.apps = get_all_apps()

    def _apply_theme(self):
        """Read current theme colors and wallpaper, apply CSS and blur."""
        bg = read_color("bg", "#1a1b26")
        bg_dim = read_color("bg_dim", "#16161e")
        bg_hl = read_color("bg_highlight", "#24283b")
        fg = read_color("fg", "#c0caf5")
        fg_dim = read_color("fg_dim", "#565f89")
        accent = read_color("accent", "#7aa2f7")
        accent_dim = read_color("accent_dim", "#3d59a1")

        css = f"""
        window, window.background {{
            background-color: transparent;
        }}
        .launcher-window {{
            background-color: transparent;
            border-radius: 16px;
            border: 2px solid {accent_dim};
        }}
        .sidebar-icon {{
            font-family: "Iosevka Nerd Font";
            font-size: 26px;
            color: {fg_dim};
            padding: 8px;
        }}
        .sidebar-hover {{
            color: {fg};
        }}
        .sidebar-pressed {{
            color: {accent_dim};
        }}
        .right-panel {{
            background-color: {hex_to_rgba(bg_dim, 0.7)};
            border-radius: 0;
            padding: 16px;
        }}
        .search-entry {{
            background-color: {hex_to_rgba(bg_hl, 0.6)};
            color: {fg};
            border-radius: 8px;
            padding: 8px 14px;
            border: 1px solid {accent_dim};
            caret-color: {fg};
            font-size: 14px;
        }}
        .search-entry:focus {{
            border-color: {accent};
        }}
        scrolledwindow {{
            background-color: transparent;
        }}
        .row-inner {{
            padding: 8px 12px;
            border-radius: 8px;
            border: 1px solid transparent;
            margin: 1px 0;
            background-color: transparent;
        }}
        .row-inner:hover {{
            background-color: {hex_to_rgba(accent_dim, 0.4)};
        }}
        .row-active {{
            background-color: {hex_to_rgba(bg_hl, 0.5)};
            border-color: {accent};
        }}
        .app-name {{
            color: {fg};
            font-size: 14px;
        }}
        .prompt-label {{
            color: {accent};
            font-weight: bold;
            font-size: 15px;
            padding: 8px 12px;
        }}
        """
        display = Gdk.Display.get_default()
        # Remove old provider if present
        if self._css_provider:
            Gtk.StyleContext.remove_provider_for_display(display, self._css_provider)
        self._css_provider = Gtk.CssProvider()
        self._css_provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            display, self._css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 100,
        )

        # Update blurred wallpaper
        wallpaper = get_wallpaper()
        blur_path = ensure_blur(wallpaper)
        if blur_path and self._bg_pic:
            try:
                texture = Gdk.Texture.new_from_filename(blur_path)
                self._bg_pic.set_paintable(texture)
            except Exception:
                pass

    def do_activate(self):
        try:
            self._do_activate()
        except Exception as e:
            import traceback
            print(f"LAUNCHER ERROR: {e}", flush=True)
            traceback.print_exc()

    def _do_activate(self):
        # If window exists, toggle visibility or re-show
        if self._win:
            if self._win.get_visible():
                self._hide()
                return
            self._show()
            return

        # Force dark color scheme
        style_mgr = Adw.StyleManager.get_default()
        style_mgr.set_color_scheme(Adw.ColorScheme.FORCE_DARK)

        win = Adw.ApplicationWindow(application=self)
        self._win = win
        win.set_title("Launcher")
        win.set_decorated(False)
        win.set_default_size(960, 560)
        win.set_resizable(False)

        # ── Layout: full-window blurred wallpaper bg, icons on left, app list on right ──
        root = Gtk.Overlay()
        root.add_css_class("launcher-window")

        # Blurred wallpaper fills entire background
        self._bg_pic = Gtk.Picture()
        self._bg_pic.set_content_fit(Gtk.ContentFit.COVER)
        self._bg_pic.set_can_shrink(True)
        root.set_child(self._bg_pic)

        # Apply theme (sets CSS + loads blur into _bg_pic)
        self._apply_theme()

        # Content layer on top of the blurred wallpaper
        content = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)

        # ── Left side: icon buttons ──
        icon_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        icon_box.set_valign(Gtk.Align.CENTER)
        icon_box.set_halign(Gtk.Align.START)
        icon_box.set_margin_start(16)
        icon_box.set_margin_end(16)
        icon_box.set_hexpand(False)

        for nf_icon, tooltip, cmd, icon_size in SIDEBAR_APPS:
            lbl = Gtk.Label(label=nf_icon)
            lbl.add_css_class("sidebar-icon")
            lbl.set_tooltip_text(tooltip)
            lbl.set_cursor(Gdk.Cursor.new_from_name("pointer"))
            # Per-icon size to match visual weight
            sz_css = Gtk.CssProvider()
            sz_css.load_from_string(f".sidebar-icon {{ font-size: {icon_size}px; }}")
            lbl.get_style_context().add_provider(sz_css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 200)
            # Click handler
            click = Gtk.GestureClick()
            click.connect("pressed", self._on_sidebar_pressed, lbl, cmd, win)
            click.connect("released", self._on_sidebar_released, lbl)
            lbl.add_controller(click)
            # Hover handler
            hover = Gtk.EventControllerMotion()
            hover.connect("enter", lambda c, x, y, l=lbl: l.add_css_class("sidebar-hover"))
            hover.connect("leave", lambda c, l=lbl: l.remove_css_class("sidebar-hover"))
            lbl.add_controller(hover)
            icon_box.append(lbl)

        content.append(icon_box)

        # Spacer pushes right panel to the right half
        spacer = Gtk.Box()
        spacer.set_hexpand(True)
        content.append(spacer)

        # ── Right side: search + app list (right half of window) ──
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        right.add_css_class("right-panel")
        right.set_hexpand(False)
        right.set_size_request(480, -1)

        # Search bar
        search_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        prompt = Gtk.Label(label="")
        prompt.add_css_class("prompt-label")
        search_row.append(prompt)

        self.search = Gtk.Entry()
        self.search.set_placeholder_text("Search...")
        self.search.add_css_class("search-entry")
        self.search.set_hexpand(True)
        self.search.connect("changed", self._on_search_changed)
        self.search.connect("activate", self._on_search_activate)
        search_row.append(self.search)
        right.append(search_row)

        # App list (plain Box for full CSS control — no Adwaita overrides)
        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self.app_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        scroll.set_child(self.app_list)
        self._selected_idx = 0
        right.append(scroll)

        content.append(right)
        root.add_overlay(content)
        win.set_content(root)

        # Keyboard: Escape to close, Up/Down for navigation
        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.set_propagation_phase(Gtk.PropagationPhase.BUBBLE)
        key_ctrl.connect("key-pressed", self._on_key_press, win)
        win.add_controller(key_ctrl)

        # Populate app list
        self._populate_list("")
        self._select_row(0)

        if self._start_hidden:
            # Build window but keep it hidden for instant show later
            self._start_hidden = False
            win.set_visible(False)
            # Hold the application open even with no visible windows
            self.hold()
        else:
            win.present()
            GLib.idle_add(self._focus_search_end)

    def _populate_list(self, query):
        # Remove all existing children
        while True:
            child = self.app_list.get_first_child()
            if child is None:
                break
            self.app_list.remove(child)

        q = query.lower()
        self._rows = []
        for name, icon, app_info in self.apps:
            if q and q not in name.lower():
                continue

            inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
            inner.add_css_class("row-inner")
            inner.app_info = app_info

            # Click handler
            click = Gtk.GestureClick()
            click.connect("pressed", self._on_row_clicked, inner)
            inner.add_controller(click)

            # Icon
            if icon:
                img = Gtk.Image.new_from_gicon(icon)
            else:
                img = Gtk.Image.new_from_icon_name("application-x-executable")
            img.set_pixel_size(32)
            inner.append(img)

            # Name
            lbl = Gtk.Label(label=name)
            lbl.add_css_class("app-name")
            lbl.set_halign(Gtk.Align.START)
            lbl.set_ellipsize(Pango.EllipsizeMode.END)
            inner.append(lbl)

            self.app_list.append(inner)
            self._rows.append(inner)

    def _select_row(self, idx):
        """Highlight row at idx, unhighlight previous."""
        for r in self._rows:
            r.remove_css_class("row-active")
        if 0 <= idx < len(self._rows):
            self._rows[idx].add_css_class("row-active")
            self._selected_idx = idx

    def _get_selected_row(self):
        if 0 <= self._selected_idx < len(self._rows):
            return self._rows[self._selected_idx]
        return None

    def _on_row_clicked(self, gesture, n_press, x, y, inner):
        if hasattr(inner, 'app_info'):
            self._launch_app(inner.app_info)

    def _on_search_changed(self, entry):
        self._populate_list(entry.get_text())
        self._select_row(0)

    def _on_search_activate(self, _entry):
        row = self._get_selected_row()
        if row and hasattr(row, 'app_info'):
            self._launch_app(row.app_info)

    def _show(self):
        """Show the window, refresh theme, reset search."""
        self._apply_theme()
        self.apps = get_all_apps()
        self.search.set_text("")
        self._populate_list("")
        self._select_row(0)
        self._win.set_visible(True)
        self._win.present()
        GLib.idle_add(self._focus_search_end)

    def _focus_search_end(self):
        """Focus search entry with cursor at end, no selection."""
        self.search.grab_focus()
        length = len(self.search.get_text())
        self.search.select_region(length, length)
        return False

    def _hide(self):
        """Hide the window (keep process alive for instant re-open)."""
        self._win.set_visible(False)

    def _launch_app(self, app_info):
        try:
            app_info.launch([], None)
        except Exception as e:
            print(f"Launch error: {e}", file=sys.stderr)
        self._hide()

    def _on_sidebar_pressed(self, gesture, n_press, x, y, lbl, cmd, win):
        lbl.add_css_class("sidebar-pressed")

    def _on_sidebar_released(self, gesture, n_press, x, y, lbl):
        lbl.remove_css_class("sidebar-pressed")
        # Launch the app
        # Get cmd from the SIDEBAR_APPS list by matching the label
        for nf_icon, tooltip, cmd, icon_size in SIDEBAR_APPS:
            if lbl.get_text() == nf_icon:
                subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self._hide()
                return

    def _on_key_press(self, controller, keyval, keycode, state, win):
        if keyval == Gdk.KEY_Escape:
            self._hide()
            return True
        # Arrow keys move selection while keeping focus on search
        if keyval == Gdk.KEY_Down or (keyval == Gdk.KEY_Tab and not (state & Gdk.ModifierType.SHIFT_MASK)):
            if self._selected_idx + 1 < len(self._rows):
                self._select_row(self._selected_idx + 1)
            GLib.idle_add(self._focus_search_end)
            return True
        if keyval == Gdk.KEY_Up:
            if self._selected_idx > 0:
                self._select_row(self._selected_idx - 1)
            GLib.idle_add(self._focus_search_end)
            return True
        # All other keys: pass through to search entry
        return False


def main():
    # Pre-generate blur before GTK init
    wallpaper = get_wallpaper()
    if wallpaper:
        ensure_blur(wallpaper)

    hidden = "--hidden" in sys.argv
    app = LauncherApp()
    if hidden:
        # Start in background without showing window — just hold the process
        app._start_hidden = True
    app.run(None)


if __name__ == "__main__":
    main()
