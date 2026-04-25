#!/usr/bin/env python3
"""
hypr-os Settings — GTK4 + Adwaita app.

Nested settings menu for system customization.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk

HOME = Path.home()
COLORS_CSS = HOME / ".config" / "waybar" / "colors.css"
WALL_DIR = HOME / "Pictures" / "Wallpaper"
HYPR_OS = Path(os.environ.get("HYPR_OS_DIR", HOME / "dev" / "hypr-os"))

# Resolve the real path (not through symlink) so magick writes correctly
FASTFETCH_DIR = (HOME / ".config" / "fastfetch").resolve()
FASTFETCH_LOGO = FASTFETCH_DIR / "logo.png"
CONF_FILE = HOME / ".config" / "hypr-os" / "settings.conf"

# Logo size in pixels
LOGO_W, LOGO_H = 320, 320


def read_color(name, fallback):
    if COLORS_CSS.exists():
        m = re.search(
            rf"@define-color\s+{re.escape(name)}\s+(#[0-9a-fA-F]{{6}})",
            COLORS_CSS.read_text(),
        )
        if m:
            return m.group(1)
    return fallback


def hex_to_rgba(h, a):
    h = h.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return f"rgba({r},{g},{b},{a})"


# ── Settings persistence ──

def read_settings():
    conf = {"terminal_image": "manual"}
    CONF_FILE.parent.mkdir(parents=True, exist_ok=True)
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    return conf


def write_settings(conf):
    CONF_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# hypr-os settings"]
    for k, v in conf.items():
        lines.append(f"{k}={v}")
    CONF_FILE.write_text("\n".join(lines) + "\n")


def set_terminal_image(source_path):
    """Resize image to fill logo area, crop overflow, preserve transparency."""
    FASTFETCH_DIR.mkdir(parents=True, exist_ok=True)
    try:
        # Resize to fit height, then crop width to clip overflow
        subprocess.run(
            ["magick", str(source_path),
             "-resize", f"x{LOGO_H}",
             "-gravity", "center",
             "-crop", f"{LOGO_W}x{LOGO_H}+0+0",
             "+repage",
             "-background", "none",
             str(FASTFETCH_LOGO)],
            capture_output=True, timeout=10, check=True,
        )
        # Clear fastfetch image cache so the new logo is picked up immediately
        cache_dir = HOME / ".cache" / "fastfetch" / "images"
        if cache_dir.exists():
            import shutil
            shutil.rmtree(cache_dir, ignore_errors=True)
        return True
    except Exception:
        return False


def set_from_wallpaper():
    """Set terminal image from current wallpaper."""
    wp_cache = HOME / ".cache" / "hypr" / "current_wallpaper"
    if wp_cache.exists():
        wp = wp_cache.read_text().strip()
        if wp and Path(wp).exists():
            return set_terminal_image(wp)
    return False


class SettingsApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="dev.hypros.settings",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.settings = read_settings()
        self._css_provider = None

    def _apply_theme(self):
        """Read current colors and apply CSS. Called on open and on theme change."""
        bg = read_color("bg", "#1a1b26")
        bg_hl = read_color("bg_highlight", "#24283b")
        fg = read_color("fg", "#c0caf5")
        fg_dim = read_color("fg_dim", "#565f89")
        accent = read_color("accent", "#7aa2f7")
        accent_dim = read_color("accent_dim", "#3d59a1")

        css = f"""
        window, window.background {{ background-color: {bg}; }}
        .settings-page {{ background-color: {bg}; padding: 16px; }}
        .cat-btn, .opt-btn {{
            background-color: transparent;
            border: 1px solid transparent;
            border-radius: 10px;
            padding: 14px 18px;
            color: {fg};
            font-size: 15px;
        }}
        .cat-btn:hover, .opt-btn:hover {{
            background-color: {hex_to_rgba(accent_dim, 0.4)};
        }}
        .section-title {{
            color: {accent};
            font-size: 13px;
            font-weight: bold;
            padding: 8px 4px 4px 4px;
        }}
        .back-btn {{
            background-color: transparent;
            color: {fg_dim};
            border: none;
        }}
        .back-btn:hover {{ color: {fg}; }}
        .preview-frame {{
            border: 1px solid {accent_dim};
            border-radius: 8px;
            padding: 4px;
            background-color: {hex_to_rgba(bg_hl, 0.5)};
        }}
        .status-label {{
            color: {fg_dim};
            font-size: 12px;
            padding: 4px 8px;
        }}
        .active-mode {{
            background-color: {hex_to_rgba(accent_dim, 0.3)};
            border-color: {accent};
        }}
        headerbar {{ background-color: {bg_hl}; color: {fg}; }}
        """
        display = Gdk.Display.get_default()
        if self._css_provider:
            Gtk.StyleContext.remove_provider_for_display(display, self._css_provider)
        self._css_provider = Gtk.CssProvider()
        self._css_provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            display, self._css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER + 100,
        )

    def do_activate(self):
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)

        win = Adw.ApplicationWindow(application=self)
        self._win = win
        win.set_title("Settings")
        win.set_default_size(500, 450)
        win.set_resizable(False)

        self._apply_theme()

        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)

        self._stack.add_named(self._build_main_menu(), "main")
        self._stack.add_named(self._build_theme_menu(), "theme")
        self._stack.add_named(self._build_performance_menu(), "performance")

        header = Adw.HeaderBar()
        self._back_btn = Gtk.Button(icon_name="go-previous-symbolic")
        self._back_btn.add_css_class("back-btn")
        self._back_btn.set_visible(False)
        self._back_btn.connect("clicked", lambda _: self._go_back())
        header.pack_start(self._back_btn)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        vbox.append(header)
        vbox.append(self._stack)
        win.set_content(vbox)

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        key_ctrl.connect("key-pressed", self._on_key)
        win.add_controller(key_ctrl)

        win.present()

    def _go_back(self):
        self._stack.set_visible_child_name("main")
        self._back_btn.set_visible(False)

    def _go_to(self, name):
        self._stack.set_visible_child_name(name)
        self._back_btn.set_visible(True)

    def _on_key(self, ctrl, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            if self._stack.get_visible_child_name() != "main":
                self._go_back()
            else:
                self.quit()
            return True
        return False

    # ── Main menu ──

    def _build_main_menu(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        page.add_css_class("settings-page")

        title = Gtk.Label(label="CATEGORIES")
        title.add_css_class("section-title")
        title.set_halign(Gtk.Align.START)
        page.append(title)

        btn = Gtk.Button(label="\uf53f   Theme")
        btn.add_css_class("cat-btn")
        btn.set_halign(Gtk.Align.FILL)
        btn.connect("clicked", lambda _: self._go_to("theme"))
        page.append(btn)

        btn2 = Gtk.Button(label="\uf625   Performance")
        btn2.add_css_class("cat-btn")
        btn2.set_halign(Gtk.Align.FILL)
        btn2.connect("clicked", lambda _: self._go_to("performance"))
        page.append(btn2)

        return page

    # ── Theme menu ──

    def _build_theme_menu(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        page.add_css_class("settings-page")
        page.set_vexpand(True)

        title = Gtk.Label(label="TERMINAL IMAGE")
        title.add_css_class("section-title")
        title.set_halign(Gtk.Align.START)
        page.append(title)

        # Mode buttons
        mode_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        mode_box.set_halign(Gtk.Align.FILL)
        mode_box.set_homogeneous(True)

        self._btn_manual = Gtk.Button(label="\uf03e  Choose Image")
        self._btn_manual.add_css_class("opt-btn")
        self._btn_manual.connect("clicked", self._on_pick_manual)
        mode_box.append(self._btn_manual)

        self._btn_wallpaper = Gtk.Button(label="\uf5aa  Use Wallpaper")
        self._btn_wallpaper.add_css_class("opt-btn")
        self._btn_wallpaper.connect("clicked", self._on_use_wallpaper)
        mode_box.append(self._btn_wallpaper)

        page.append(mode_box)

        # Highlight active mode
        self._update_mode_buttons()

        # Preview
        self._logo_preview = Gtk.Picture()
        self._logo_preview.set_size_request(180, 180)
        self._logo_preview.set_content_fit(Gtk.ContentFit.CONTAIN)
        self._logo_preview.add_css_class("preview-frame")
        self._logo_preview.set_halign(Gtk.Align.CENTER)
        self._logo_preview.set_margin_top(12)
        self._update_logo_preview()
        page.append(self._logo_preview)

        self._status = Gtk.Label()
        self._status.add_css_class("status-label")
        mode = self.settings.get("terminal_image", "manual")
        self._status.set_label(
            "Mode: follows wallpaper" if mode == "wallpaper" else "Mode: manual"
        )
        page.append(self._status)

        return page

    def _update_mode_buttons(self):
        mode = self.settings.get("terminal_image", "manual")
        if mode == "wallpaper":
            self._btn_wallpaper.add_css_class("active-mode")
            self._btn_manual.remove_css_class("active-mode")
        else:
            self._btn_manual.add_css_class("active-mode")
            self._btn_wallpaper.remove_css_class("active-mode")

    def _update_logo_preview(self):
        if FASTFETCH_LOGO.exists():
            try:
                # Force reload by reading fresh
                texture = Gdk.Texture.new_from_filename(str(FASTFETCH_LOGO))
                self._logo_preview.set_paintable(texture)
            except Exception:
                pass

    def _on_pick_manual(self, _btn):
        self.settings["terminal_image"] = "manual"
        write_settings(self.settings)
        self._update_mode_buttons()

        dialog = Gtk.FileDialog()
        dialog.set_title("Select Terminal Image")

        img_filter = Gtk.FileFilter()
        img_filter.set_name("Images")
        img_filter.add_mime_type("image/png")
        img_filter.add_mime_type("image/jpeg")
        img_filter.add_mime_type("image/webp")
        filters = Gio.ListStore.new(Gtk.FileFilter)
        filters.append(img_filter)
        dialog.set_filters(filters)
        dialog.set_default_filter(img_filter)

        if WALL_DIR.exists():
            dialog.set_initial_folder(Gio.File.new_for_path(str(WALL_DIR)))

        dialog.open(self._win, None, self._on_image_selected)

    def _on_image_selected(self, dialog, result):
        try:
            f = dialog.open_finish(result)
            path = f.get_path()
        except Exception:
            return

        if not path or not Path(path).exists():
            return

        if set_terminal_image(path):
            self._update_logo_preview()
            self._status.set_label(f"Set to: {Path(path).name}")
            subprocess.Popen(
                ["notify-send", "-t", "3000", "Settings",
                 f"Terminal image: {Path(path).name}"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            self._status.set_label("Failed to process image")

    def _on_use_wallpaper(self, _btn):
        self.settings["terminal_image"] = "wallpaper"
        write_settings(self.settings)
        self._update_mode_buttons()

        if set_from_wallpaper():
            self._update_logo_preview()
            self._status.set_label("Mode: follows wallpaper (updated)")
            subprocess.Popen(
                ["notify-send", "-t", "3000", "Settings",
                 "Terminal image now follows wallpaper"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
        else:
            self._status.set_label("Mode: follows wallpaper (no wallpaper found)")


    # ── Performance menu ──

    def _build_performance_menu(self):
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        page.add_css_class("settings-page")

        title = Gtk.Label(label="PERFORMANCE")
        title.add_css_class("section-title")
        title.set_halign(Gtk.Align.START)
        page.append(title)

        # Launcher pre-warm toggle
        prewarm_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        prewarm_box.add_css_class("opt-btn")
        prewarm_label = Gtk.Label(label="\uf135   Launcher Pre-warm")
        prewarm_label.set_hexpand(True)
        prewarm_label.set_halign(Gtk.Align.START)
        prewarm_box.append(prewarm_label)

        self._prewarm_switch = Gtk.Switch()
        self._prewarm_switch.set_valign(Gtk.Align.CENTER)
        self._prewarm_switch.set_active(self._is_prewarm_enabled())
        self._prewarm_switch.connect("notify::active", self._on_prewarm_toggled)
        prewarm_box.append(self._prewarm_switch)
        page.append(prewarm_box)

        prewarm_desc = Gtk.Label(
            label="Keeps launcher in memory for instant open (~25ms).\n"
                  "Disabled saves ~215 MB RAM, cold start takes ~600ms.\n"
                  "Requires logout to take effect."
        )
        prewarm_desc.add_css_class("status-label")
        prewarm_desc.set_halign(Gtk.Align.START)
        prewarm_desc.set_wrap(True)
        page.append(prewarm_desc)

        return page

    def _is_prewarm_enabled(self):
        autostart = HYPR_OS / "config" / "hypr" / "autostart.conf"
        if autostart.exists():
            for line in autostart.read_text().splitlines():
                if "launcher-app.py --hidden" in line and not line.strip().startswith("#"):
                    return True
        return False

    def _on_prewarm_toggled(self, switch, _pspec):
        autostart = HYPR_OS / "config" / "hypr" / "autostart.conf"
        if not autostart.exists():
            return
        lines = autostart.read_text().splitlines()
        new_lines = []
        for line in lines:
            if "launcher-app.py --hidden" in line:
                if switch.get_active():
                    # Enable: uncomment
                    new_lines.append(line.lstrip("# ").rstrip())
                else:
                    # Disable: comment out
                    if not line.strip().startswith("#"):
                        new_lines.append("# " + line)
                    else:
                        new_lines.append(line)
            else:
                new_lines.append(line)
        autostart.write_text("\n".join(new_lines) + "\n")

        state = "enabled" if switch.get_active() else "disabled"
        subprocess.Popen(
            ["notify-send", "-t", "3000", "Settings",
             f"Launcher pre-warm {state} (logout to apply)"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )


def main():
    app = SettingsApp()
    app.run(None)


if __name__ == "__main__":
    main()
