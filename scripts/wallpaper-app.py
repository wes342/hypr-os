#!/usr/bin/env python3
"""
hypr-os Wallpaper Manager — GTK4 + Adwaita app.

Browse local wallpapers and Wallhaven, apply wallpapers, toggle
re-theming, and configure Wallhaven settings — all with real widgets.
Reads accent colors from ~/.config/waybar/colors.css so the window
matches the current wallpaper palette.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, Gtk

# ── Paths ──

HOME = Path.home()
WALL_DIR = HOME / "Pictures" / "Wallpaper"
CACHE_DIR = HOME / ".cache" / "hypr-os" / "thumbs"
WH_CACHE = HOME / ".cache" / "hypr-os" / "wallhaven" / "thumbs"
WH_FULL_CACHE = HOME / ".cache" / "hypr-os" / "wallhaven" / "full"  # applied but not saved
WH_SAVED = WALL_DIR / "wallhaven"  # explicitly saved to library
COLORS_CSS = HOME / ".config" / "waybar" / "colors.css"
CONF_FILE = HOME / ".config" / "hypr-os" / "wallhaven.conf"
STATE_FILE = HOME / ".cache" / "hypr-os" / "wallpaper-browser.state"
HYPR_OS = Path(os.environ.get("HYPR_OS_DIR", HOME / "dev" / "hypr-os"))
THEME_SH = HYPR_OS / "scripts" / "theme.sh"
THUMB_SIZE = 320

CONF_DEFAULTS = {
    "api_key": "", "query": "", "categories": "111", "purity": "100",
    "sorting": "random", "atleast": "2560x1440", "ratios": "16x9",
    "source": "local", "auto_rotate": "off", "rotate_interval": "30",
}

# Interval options: label -> minutes
ROTATE_INTERVALS = [
    ("1 minute", "1"),
    ("5 minutes", "5"),
    ("10 minutes", "10"),
    ("15 minutes", "15"),
    ("30 minutes", "30"),
    ("1 hour", "60"),
    ("2 hours", "120"),
    ("4 hours", "240"),
    ("12 hours", "720"),
    ("24 hours", "1440"),
]


# ── Config helpers ──

def read_conf():
    conf = dict(CONF_DEFAULTS)
    CONF_FILE.parent.mkdir(parents=True, exist_ok=True)
    if CONF_FILE.exists():
        for line in CONF_FILE.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                conf[k.strip()] = v.strip()
    else:
        write_conf(conf)
    return conf


def write_conf(conf):
    CONF_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# hypr-os Wallhaven settings", ""]
    for k, v in conf.items():
        lines.append(f"{k}={v}")
    CONF_FILE.write_text("\n".join(lines) + "\n")


def read_theme_state():
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    if STATE_FILE.exists():
        return STATE_FILE.read_text().strip() == "on"
    return True


def write_theme_state(on: bool):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text("on" if on else "off")


# ── Auto-rotate (systemd timer) helpers ──

TIMER_UNIT = "wallpaper-rotate.timer"
SERVICE_UNIT = "wallpaper-rotate.service"
SYSTEMD_USER_DIR = HOME / ".config" / "systemd" / "user"


def is_timer_active():
    try:
        result = subprocess.run(
            ["systemctl", "--user", "is-active", TIMER_UNIT],
            capture_output=True, text=True, timeout=3,
        )
        return result.stdout.strip() == "active"
    except Exception:
        return False


def set_timer_interval(minutes):
    """Rewrite the timer unit with the given interval and reload."""
    timer_path = SYSTEMD_USER_DIR / TIMER_UNIT
    timer_path.parent.mkdir(parents=True, exist_ok=True)
    timer_path.write_text(
        f"[Unit]\nDescription=Auto-rotate wallpaper on interval\n\n"
        f"[Timer]\nOnActiveSec={minutes}min\nOnUnitActiveSec={minutes}min\n"
        f"AccuracySec=1min\n\n[Install]\nWantedBy=timers.target\n"
    )
    subprocess.run(["systemctl", "--user", "daemon-reload"],
                    capture_output=True, timeout=5)


def enable_timer(minutes):
    set_timer_interval(minutes)
    subprocess.run(["systemctl", "--user", "enable", "--now", TIMER_UNIT],
                    capture_output=True, timeout=5)


def disable_timer():
    subprocess.run(["systemctl", "--user", "disable", "--now", TIMER_UNIT],
                    capture_output=True, timeout=5)


def read_color(name, fallback):
    if COLORS_CSS.exists():
        m = re.search(
            rf"@define-color\s+{re.escape(name)}\s+(#[0-9a-fA-F]{{6}})",
            COLORS_CSS.read_text(),
        )
        if m:
            return m.group(1)
    return fallback


# ── Thumbnail helpers ──

THUMB_H = int(THUMB_SIZE * 9 / 16)  # 16:9 landscape


def make_thumb(src: Path) -> Path:
    rel = str(src.relative_to(WALL_DIR))
    mtime = int(src.stat().st_mtime)
    h = hashlib.md5(rel.encode()).hexdigest()[:10]
    thumb = CACHE_DIR / f"{THUMB_SIZE}x{THUMB_H}_{mtime}_{h}.png"
    if not thumb.exists():
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        for old in CACHE_DIR.glob(f"*_{h}.png"):
            old.unlink(missing_ok=True)
        subprocess.run(
            ["magick", str(src), "-resize", f"{THUMB_SIZE}x{THUMB_H}^",
             "-gravity", "center", "-extent", f"{THUMB_SIZE}x{THUMB_H}",
             "-strip", str(thumb)],
            capture_output=True,
        )
    return thumb


def list_local_wallpapers(folder=None):
    """List wallpapers. If folder is set, only from that subfolder."""
    exts = {".jpg", ".jpeg", ".png", ".webp"}
    if not WALL_DIR.exists():
        return []
    search_dir = WALL_DIR / folder if folder else WALL_DIR
    return sorted(
        p for p in search_dir.rglob("*") if p.suffix.lower() in exts and p.is_file()
    )


def list_wallpaper_folders():
    """Return sorted list of subfolder names that contain at least one wallpaper."""
    exts = {".jpg", ".jpeg", ".png", ".webp"}
    if not WALL_DIR.exists():
        return []
    folders = []
    for d in sorted(WALL_DIR.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        # Check if folder has any wallpapers (recursive)
        has_images = any(
            f.suffix.lower() in exts for f in d.rglob("*") if f.is_file()
        )
        if has_images:
            folders.append(d.name)
    return folders


# ── Wallhaven API ──

def wh_search(conf, query="", page=1):
    params = {
        "categories": conf["categories"], "purity": conf["purity"],
        "sorting": conf["sorting"], "atleast": conf["atleast"],
        "ratios": conf["ratios"], "page": str(page),
    }
    if query:
        params["q"] = query
    if conf.get("api_key"):
        params["apikey"] = conf["api_key"]
    url = "https://wallhaven.cc/api/v1/search?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read()).get("data", [])
    except Exception as e:
        print(f"Wallhaven API error: {e}", file=sys.stderr)
        return []


def wh_thumb_path(item):
    wid = item["id"]
    ext = item.get("file_type", "image/jpeg").split("/")[-1]
    if ext == "jpeg":
        ext = "jpg"
    return WH_CACHE / f"{wid}.{ext}"


def wh_download_thumb(item):
    tp = wh_thumb_path(item)
    if tp.exists():
        return tp
    WH_CACHE.mkdir(parents=True, exist_ok=True)
    url = item.get("thumbs", {}).get("large", "")
    if not url:
        return None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            tp.write_bytes(resp.read())
        return tp
    except Exception:
        return None


def wh_download_full(item, dest_dir=None):
    """Download full wallpaper. dest_dir defaults to cache (not library)."""
    if dest_dir is None:
        dest_dir = WH_FULL_CACHE
    dest_dir.mkdir(parents=True, exist_ok=True)
    wid = item["id"]
    conf = read_conf()
    params = {}
    if conf.get("api_key"):
        params["apikey"] = conf["api_key"]
    url = f"https://wallhaven.cc/api/v1/w/{wid}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
        full_url = data.get("data", {}).get("path", "")
    except Exception:
        return None
    if not full_url:
        return None
    fname = full_url.rsplit("/", 1)[-1]
    dest = dest_dir / fname
    if dest.exists():
        return dest
    try:
        req = urllib.request.Request(full_url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            dest.write_bytes(resp.read())
        return dest
    except Exception:
        return None


# ── Cache cleanup ──

def _get_current_wallpaper():
    cp = HOME / ".cache" / "hypr" / "current_wallpaper"
    if cp.exists():
        return cp.read_text().strip()
    return ""


def clean_wh_full_cache():
    """Remove cached full-size Wallhaven downloads except the current wallpaper."""
    if not WH_FULL_CACHE.exists():
        return 0
    current = _get_current_wallpaper()
    removed = 0
    for f in WH_FULL_CACHE.iterdir():
        if f.is_file() and str(f) != current:
            f.unlink(missing_ok=True)
            removed += 1
    return removed


def clean_wh_thumbs(keep_ids=None):
    """Remove Wallhaven thumbnail cache, keeping only IDs in keep_ids."""
    if not WH_CACHE.exists():
        return 0
    keep = set(keep_ids or [])
    removed = 0
    for f in WH_CACHE.iterdir():
        if f.is_file():
            # Thumbnail filenames are {id}.{ext}
            fid = f.stem
            if fid not in keep:
                f.unlink(missing_ok=True)
                removed += 1
    return removed


def cache_size_str():
    """Return human-readable size of all Wallhaven cache dirs."""
    total = 0
    for d in [WH_CACHE, WH_FULL_CACHE]:
        if d.exists():
            for f in d.rglob("*"):
                if f.is_file():
                    total += f.stat().st_size
    if total < 1024:
        return f"{total} B"
    elif total < 1024 * 1024:
        return f"{total / 1024:.1f} KB"
    elif total < 1024 * 1024 * 1024:
        return f"{total / (1024 * 1024):.1f} MB"
    return f"{total / (1024 * 1024 * 1024):.1f} GB"


def clear_all_wh_cache():
    """Remove all Wallhaven cached files (thumbs + full) except current wallpaper."""
    clean_wh_thumbs(keep_ids=[])
    clean_wh_full_cache()


# ── Apply wallpaper ──

def apply_wallpaper(path: Path, retheme: bool, callback=None):
    """Apply wallpaper. If retheme, runs theme.sh synchronously so the
    callback can refresh the app's CSS afterwards."""
    path_str = str(path)
    cache = HOME / ".cache" / "hypr" / "current_wallpaper"
    cache.parent.mkdir(parents=True, exist_ok=True)
    cache.write_text(path_str)

    # Write hyprpaper.conf
    try:
        monitors = json.loads(
            subprocess.check_output(["hyprctl", "monitors", "-j"], timeout=3)
        )
        mon_names = [m["name"] for m in monitors]
    except Exception:
        mon_names = ["DP-3"]

    hpc = HYPR_OS / "config" / "hypr" / "hyprpaper.conf"
    lines = ["splash = false", "ipc = on", ""]
    for m in mon_names:
        lines += [f"wallpaper {{", f"    monitor = {m}", f"    path = {path_str}", "}", ""]
    hpc.write_text("\n".join(lines))

    subprocess.run(["killall", "hyprpaper"], capture_output=True)
    subprocess.Popen(["hyprpaper"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    if retheme:
        subprocess.run(
            [str(THEME_SH), path_str],
            env={**os.environ, "HYPR_OS_DIR": str(HYPR_OS)},
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if callback:
            GLib.idle_add(callback)


# ── GTK App ──

IGNORE_FILE = HOME / ".config" / "hypr-os" / "wallhaven-ignore.txt"


def read_ignores():
    if IGNORE_FILE.exists():
        return set(IGNORE_FILE.read_text().splitlines())
    return set()


def add_ignore(wid):
    ignores = read_ignores()
    ignores.add(wid)
    IGNORE_FILE.parent.mkdir(parents=True, exist_ok=True)
    IGNORE_FILE.write_text("\n".join(sorted(ignores)) + "\n")


class WallpaperTile(Gtk.FlowBoxChild):
    def __init__(self, thumb_path, label, full_path=None, wh_item=None,
                 on_save=None, on_ignore=None, on_delete=None):
        super().__init__()
        self.full_path = full_path
        self.wh_item = wh_item
        self._on_save = on_save
        self._on_ignore = on_ignore
        self._on_delete = on_delete

        # Right-click gesture for context menu
        rc = Gtk.GestureClick(button=3)
        rc.connect("pressed", self._on_right_click)
        self.add_controller(rc)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)

        if thumb_path and thumb_path.exists():
            try:
                texture = Gdk.Texture.new_from_filename(str(thumb_path))
                img = Gtk.Picture.new_for_paintable(texture)
                img.set_content_fit(Gtk.ContentFit.COVER)
            except Exception:
                img = Gtk.Image.new_from_icon_name("image-missing")
                img.set_pixel_size(THUMB_SIZE)
        else:
            img = Gtk.Image.new_from_icon_name("image-loading")
            img.set_pixel_size(THUMB_SIZE)

        img.set_size_request(THUMB_SIZE, THUMB_H)
        img.add_css_class("wallpaper-thumb")
        box.append(img)

        lbl = Gtk.Label(label=label)
        lbl.set_ellipsize(3)  # PANGO_ELLIPSIZE_END
        lbl.set_max_width_chars(20)
        lbl.add_css_class("wallpaper-label")
        box.append(lbl)

        self.set_child(box)

    def _on_right_click(self, gesture, _n, x, y):
        menu = Gio.Menu()
        action_group = Gio.SimpleActionGroup()

        if self.wh_item:
            menu.append("Save to library", "tile.save")
            save_action = Gio.SimpleAction.new("save", None)
            save_action.connect("activate", lambda *_: self._on_save(self.wh_item) if self._on_save else None)
            action_group.add_action(save_action)

            menu.append("Ignore this wallpaper", "tile.ignore")
            ignore_action = Gio.SimpleAction.new("ignore", None)
            ignore_action.connect("activate", lambda *_: self._on_ignore(self.wh_item) if self._on_ignore else None)
            action_group.add_action(ignore_action)

        if self.full_path:
            menu.append("Delete wallpaper", "tile.delete")
            delete_action = Gio.SimpleAction.new("delete", None)
            delete_action.connect("activate", lambda *_: self._on_delete(self) if self._on_delete else None)
            action_group.add_action(delete_action)

        if menu.get_n_items() == 0:
            return

        self.insert_action_group("tile", action_group)
        popover = Gtk.PopoverMenu.new_from_model(menu)
        popover.set_parent(self)
        popover.set_pointing_to(Gdk.Rectangle(int(x), int(y), 1, 1))
        popover.popup()


class WallpaperApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="dev.hypros.wallpaper-manager")
        self.conf = read_conf()
        self.retheme = read_theme_state()
        self.wh_page = 1
        self.wh_items = []

    def do_activate(self):
        win = Adw.ApplicationWindow(application=self)
        win.set_title("Wallpaper Manager")
        win.set_default_size(1400, 850)

        # ── Custom CSS from theme ──
        self._apply_theme_css(win)

        # ── Header bar ──
        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(True)

        # Theme toggle
        self.theme_check = Gtk.CheckButton(label="Re-theme")
        self.theme_check.set_active(self.retheme)
        self.theme_check.connect("toggled", self._on_theme_toggled)
        header.pack_start(self.theme_check)

        # Auto-rotate toggle (header shortcut)
        self.rotate_check = Gtk.CheckButton(label="Auto-rotate")
        self.rotate_check.set_active(self.conf.get("auto_rotate", "off") == "on")
        self.rotate_check.set_tooltip_text("Automatically change wallpaper on a timer")
        self.rotate_check.connect("toggled", self._on_header_rotate_toggled)
        header.pack_start(self.rotate_check)

        # Settings button
        settings_btn = Gtk.Button(icon_name="emblem-system-symbolic")
        settings_btn.set_tooltip_text("Settings")
        settings_btn.connect("clicked", self._on_settings_clicked)
        header.pack_end(settings_btn)

        # ── Tab switcher ──
        self.stack = Adw.ViewStack()
        switcher = Adw.ViewSwitcher(stack=self.stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)

        # ── Tabs ──
        local_page = self._build_local_tab()
        self.stack.add_titled(local_page, "local", "📁 Local")

        wh_page = self._build_wallhaven_tab()
        self.stack.add_titled(wh_page, "wallhaven", "🌐 Wallhaven")

        both_page = self._build_both_tab()
        self.stack.add_titled(both_page, "both", "📁+🌐 Both")

        # Auto-select tab based on source config
        source = self.conf.get("source", "local")
        if source in ("local", "wallhaven", "both"):
            self.stack.set_visible_child_name(source)

        # Sync filters when switching tabs
        self.stack.connect("notify::visible-child", self._on_tab_changed)

        # ── Assemble ──
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        main_box.append(header)
        main_box.append(self.stack)
        win.set_content(main_box)
        win.present()

        # Load tiles in background
        threading.Thread(target=self._load_local_tiles, daemon=True).start()
        threading.Thread(target=self._load_wh_results,
                         args=(self.conf.get("query", ""),), daemon=True).start()

    def _on_tab_changed(self, stack, _pspec):
        """Sync filters when switching tabs."""
        current = stack.get_visible_child_name()
        if current == "both":
            folder = self._get_selected_folder(self.local_folder_dropdown, self._local_folder_labels)
            self._sync_folder_dropdown(self.both_folder_dropdown, self._both_folder_labels, folder)
            self._apply_both_filter()
        elif current == "local":
            folder = self._get_selected_folder(self.both_folder_dropdown, self._both_folder_labels)
            self._sync_folder_dropdown(self.local_folder_dropdown, self._local_folder_labels, folder)
            self._apply_local_filter()

    def _apply_theme_css(self, win):
        bg = read_color("bg", "#1a1b26")
        bg_hl = read_color("bg_highlight", "#24283b")
        fg = read_color("fg", "#c0caf5")
        fg_dim = read_color("fg_dim", "#565f89")
        accent = read_color("accent", "#7aa2f7")
        accent_dim = read_color("accent_dim", "#3d59a1")

        css = f"""
        window, .main-box {{
            background-color: {bg};
            color: {fg};
        }}
        headerbar {{
            background-color: {bg_hl};
            color: {fg};
        }}
        .wallpaper-thumb {{
            border-radius: 8px;
        }}
        .wallpaper-label {{
            color: {fg_dim};
            font-size: 11px;
        }}
        flowboxchild {{
            border-radius: 10px;
            padding: 4px;
            border: 2px solid transparent;
        }}
        flowboxchild:selected {{
            border-color: {accent};
            background-color: {bg_hl};
        }}
        flowboxchild:hover {{
            background-color: {accent_dim};
            border-radius: 10px;
        }}
        entry {{
            background-color: {bg_hl};
            color: {fg};
            border-radius: 6px;
            padding: 6px 10px;
            border: 1px solid {accent_dim};
            caret-color: {fg};
        }}
        entry:focus {{
            border-color: {accent};
        }}
        button {{
            background-color: {bg_hl};
            color: {fg};
            border-radius: 6px;
            border: 1px solid {accent_dim};
        }}
        button:hover {{
            background-color: {accent_dim};
        }}
        checkbutton {{
            color: {fg};
        }}
        .navigation-sidebar row, stackswitcher button {{
            color: {fg};
        }}
        .navigation-sidebar row:selected, stackswitcher button:checked {{
            background-color: {accent_dim};
            color: {fg};
        }}
        scrolledwindow {{
            background-color: {bg};
        }}
        .settings-group {{
            background-color: {bg_hl};
            border-radius: 10px;
            padding: 12px;
            margin: 6px 0;
        }}
        .settings-label {{
            color: {fg_dim};
            font-size: 12px;
        }}
        .settings-value {{
            color: {fg};
        }}
        .sort-btn {{
            min-width: 36px;
            min-height: 36px;
            padding: 4px 8px;
            font-size: 18px;
            border-radius: 8px;
            background-color: {bg_hl};
            color: {fg_dim};
            border: 1px solid transparent;
        }}
        .sort-btn:hover {{
            background-color: {accent_dim};
            color: {fg};
        }}
        .sort-active {{
            background-color: {accent_dim};
            color: {accent};
            border-color: {accent};
        }}
        """
        provider = Gtk.CssProvider()
        provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    # ── Local tab ──

    def _build_folder_dropdown(self):
        """Build a dropdown with 'All' + each subfolder in ~/Pictures/Wallpaper/."""
        folders = list_wallpaper_folders()
        labels = ["All"] + folders
        model = Gtk.StringList.new(labels)
        dropdown = Gtk.DropDown(model=model)
        dropdown.set_selected(0)
        return dropdown, labels

    def _build_local_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_start(10)
        box.set_margin_end(10)
        box.set_margin_top(8)

        # Filter bar: folder dropdown + search
        filter_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)

        self.local_folder_dropdown, self._local_folder_labels = self._build_folder_dropdown()
        self.local_folder_dropdown.set_tooltip_text("Filter by folder")
        # Restore saved folder selection
        saved_folder = self.conf.get("local_folder", "")
        if saved_folder and saved_folder in self._local_folder_labels:
            self.local_folder_dropdown.set_selected(self._local_folder_labels.index(saved_folder))
        self.local_folder_dropdown.connect("notify::selected", self._on_local_folder_changed)
        filter_box.append(self.local_folder_dropdown)

        self.local_search = Gtk.SearchEntry(placeholder_text="Search local wallpapers...")
        self.local_search.set_hexpand(True)
        self.local_search.connect("search-changed", self._on_local_search)
        filter_box.append(self.local_search)

        box.append(filter_box)

        # Grid
        scroll = Gtk.ScrolledWindow(vexpand=True)
        self.local_flow = Gtk.FlowBox()
        self.local_flow.set_valign(Gtk.Align.START)
        self.local_flow.set_max_children_per_line(5)
        self.local_flow.set_min_children_per_line(3)
        self.local_flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.local_flow.set_homogeneous(True)
        self.local_flow.connect("child-activated", self._on_local_activated)
        scroll.set_child(self.local_flow)
        box.append(scroll)

        # Status
        self.local_status = Gtk.Label(label="Loading...")
        self.local_status.add_css_class("settings-label")
        box.append(self.local_status)

        return box

    def _load_local_tiles(self):
        walls = list_local_wallpapers()
        current = ""
        cp = HOME / ".cache" / "hypr" / "current_wallpaper"
        if cp.exists():
            current = cp.read_text().strip()

        for wall in walls:
            thumb = make_thumb(wall)
            rel = str(wall.relative_to(WALL_DIR))
            label = rel.rsplit(".", 1)[0]
            GLib.idle_add(self._add_local_tile, thumb, label, wall)

        GLib.idle_add(self.local_status.set_label, f"{len(walls)} wallpapers")
        # Apply folder filter after all tiles are added (delay to ensure queue is flushed)
        GLib.timeout_add(500, self._apply_local_filter_once)

    def _add_local_tile(self, thumb, label, full_path, flow=None):
        target = flow or self.local_flow
        tile = WallpaperTile(thumb, label, full_path=full_path,
                             on_delete=self._delete_local)
        target.append(tile)
        return False

    def _get_selected_folder(self, dropdown, labels):
        """Return the selected folder name, or None for 'All'."""
        idx = dropdown.get_selected()
        if idx == 0 or idx >= len(labels):
            return None
        return labels[idx]

    def _filter_local_flow(self, flow, folder, query):
        """Show/hide tiles in a flow based on folder and search query."""
        child = flow.get_first_child()
        while child:
            visible = True
            # Folder filter
            if folder and hasattr(child, 'full_path') and child.full_path:
                try:
                    rel = child.full_path.relative_to(WALL_DIR)
                    visible = rel.parts[0] == folder if len(rel.parts) > 1 else False
                except ValueError:
                    visible = False
            # Text search filter
            if visible and query:
                box = child.get_child()
                lbl = None
                c = box.get_first_child()
                while c:
                    if isinstance(c, Gtk.Label):
                        lbl = c
                        break
                    c = c.get_next_sibling()
                if lbl:
                    visible = query in lbl.get_label().lower()
            child.set_visible(visible)
            child = child.get_next_sibling()

    def _on_local_folder_changed(self, dropdown, _pspec):
        if getattr(self, '_syncing_folders', False):
            return
        folder = self._get_selected_folder(self.local_folder_dropdown, self._local_folder_labels)
        self._conf_update("local_folder", folder or "")
        self._sync_folder_dropdown(self.both_folder_dropdown, self._both_folder_labels, folder)
        self._apply_local_filter()
        self._apply_both_filter()

    def _sync_folder_dropdown(self, dropdown, labels, folder):
        """Set a dropdown to match a folder name, skip if already matching."""
        target_idx = 0  # "All"
        if folder and folder in labels:
            target_idx = labels.index(folder)
        if dropdown.get_selected() != target_idx:
            self._syncing_folders = True
            dropdown.set_selected(target_idx)
            self._syncing_folders = False

    def _on_local_search(self, entry):
        self._apply_local_filter()

    def _apply_local_filter(self):
        folder = self._get_selected_folder(self.local_folder_dropdown, self._local_folder_labels)
        query = self.local_search.get_text().lower()
        self._filter_local_flow(self.local_flow, folder, query)

    def _apply_local_filter_once(self):
        self._apply_local_filter()
        return False  # don't repeat

    def _on_local_activated(self, flow, child):
        if child.full_path:
            threading.Thread(
                target=apply_wallpaper,
                args=(child.full_path, self.retheme, self._refresh_theme_css),
                daemon=True,
            ).start()
            self.local_status.set_label(f"Applied: {child.full_path.name}")

    def _delete_local(self, tile):
        """Show confirmation dialog then delete the wallpaper file."""
        if not tile.full_path:
            return
        dialog = Adw.AlertDialog()
        dialog.set_heading("Delete wallpaper?")
        dialog.set_body(f"Permanently delete:\n{tile.full_path.name}")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("delete", "Delete")
        dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(dlg, response):
            if response == "delete" and tile.full_path and tile.full_path.exists():
                tile.full_path.unlink()
                # Remove tile from all flows that contain it
                for flow in [self.local_flow, self.both_flow]:
                    child = flow.get_first_child()
                    while child:
                        nxt = child.get_next_sibling()
                        if hasattr(child, 'full_path') and child.full_path == tile.full_path:
                            flow.remove(child)
                        child = nxt
                self.local_status.set_label(f"Deleted: {tile.full_path.name}")

        dialog.connect("response", on_response)
        dialog.present(self.get_active_window())

    # ── Both tab ──

    def _build_both_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_start(10)
        box.set_margin_end(10)
        box.set_margin_top(8)

        # Filter bar: local folder dropdown + wallhaven sort + search
        filter_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        # Folder filter for local wallpapers
        self.both_folder_dropdown, self._both_folder_labels = self._build_folder_dropdown()
        self.both_folder_dropdown.set_tooltip_text("Filter local by folder")
        saved_folder = self.conf.get("local_folder", "")
        if saved_folder and saved_folder in self._both_folder_labels:
            self.both_folder_dropdown.set_selected(self._both_folder_labels.index(saved_folder))
        self.both_folder_dropdown.connect("notify::selected", self._on_both_folder_changed)
        filter_box.append(self.both_folder_dropdown)

        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep.set_margin_start(4)
        sep.set_margin_end(4)
        filter_box.append(sep)

        # Wallhaven sort buttons (same icons as Wallhaven tab)
        self._both_sort_buttons = {}
        for sort_id, icon, tooltip in [
            ("date_added", self._wh_sort_icons.get("date_added", "L"), "Latest"),
            ("toplist", self._wh_sort_icons.get("toplist", "T"), "Top rated"),
            ("hot", self._wh_sort_icons.get("hot", "H"), "Trending"),
            ("random", self._wh_sort_icons.get("random", "R"), "Random"),
        ]:
            btn = Gtk.Button(label=icon)
            btn.set_tooltip_text(tooltip)
            btn.add_css_class("sort-btn")
            btn.connect("clicked", self._on_sort_clicked, sort_id)
            filter_box.append(btn)
            self._both_sort_buttons[sort_id] = btn

        sep2 = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep2.set_margin_start(4)
        sep2.set_margin_end(4)
        filter_box.append(sep2)

        # Search sort dropdown for Wallhaven results in Both tab
        both_sort_model = Gtk.StringList.new(self._search_sort_labels)
        self.both_search_sort = Gtk.DropDown(model=both_sort_model)
        self.both_search_sort.set_tooltip_text("Sort search results")
        current_ss = self.conf.get("search_sorting", "date_added")
        if current_ss in self._search_sort_opts:
            self.both_search_sort.set_selected(self._search_sort_opts.index(current_ss))
        filter_box.append(self.both_search_sort)

        self.both_search = Gtk.SearchEntry(placeholder_text="Search all...")
        self.both_search.set_hexpand(True)
        self.both_search.connect("search-changed", self._on_both_search)
        self.both_search.connect("activate", self._on_both_search_activate)

        both_search_btn = Gtk.Button(label="Search")
        both_search_btn.connect("clicked", self._on_both_search_activate)

        filter_box.append(self.both_search)
        filter_box.append(both_search_btn)

        box.append(filter_box)

        scroll = Gtk.ScrolledWindow(vexpand=True)
        self.both_flow = Gtk.FlowBox()
        self.both_flow.set_valign(Gtk.Align.START)
        self.both_flow.set_max_children_per_line(5)
        self.both_flow.set_min_children_per_line(3)
        self.both_flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.both_flow.set_homogeneous(True)
        self.both_flow.connect("child-activated", self._on_both_activated)
        scroll.set_child(self.both_flow)
        box.append(scroll)

        self.both_status = Gtk.Label(label="Loading...")
        self.both_status.add_css_class("settings-label")
        box.append(self.both_status)

        return box

    def _populate_both_tab(self):
        """Called after local + wallhaven tiles are loaded."""
        # Clear existing tiles on main thread and wait for it
        event = threading.Event()
        def do_clear():
            self._clear_flow(self.both_flow)
            event.set()
            return False
        GLib.idle_add(do_clear)
        event.wait(timeout=2)

        # Add local tiles
        walls = list_local_wallpapers()
        for wall in walls:
            thumb = make_thumb(wall)
            rel = str(wall.relative_to(WALL_DIR))
            label = rel.rsplit(".", 1)[0]
            GLib.idle_add(self._add_local_tile, thumb, label, wall, self.both_flow)

        # Add wallhaven tiles
        if self.wh_items:
            ignores = read_ignores()
            for item in self.wh_items:
                if item["id"] in ignores:
                    continue
                tp = wh_thumb_path(item)
                label = f"\U0001f310 {item['id']}  {item.get('resolution', '?')}"
                GLib.idle_add(self._add_wh_both_tile, tp, label, item)

        GLib.idle_add(self.both_status.set_label, f"{len(walls)} local + wallhaven results")
        # Apply folder filter after all tiles are added (delay to ensure queue is flushed)
        GLib.timeout_add(500, self._apply_both_filter_once)

    def _clear_flow(self, flow):
        """Remove all children from a FlowBox."""
        while True:
            child = flow.get_first_child()
            if child is None:
                break
            flow.remove(child)
        return False

    def _add_wh_both_tile(self, tp, label, item):
        tile = WallpaperTile(tp, label, wh_item=item,
                             on_save=self._save_wh_only,
                             on_ignore=self._ignore_wh)
        self.both_flow.append(tile)
        return False

    def _on_both_folder_changed(self, dropdown, _pspec):
        if getattr(self, '_syncing_folders', False):
            return
        folder = self._get_selected_folder(self.both_folder_dropdown, self._both_folder_labels)
        self._conf_update("local_folder", folder or "")
        self._sync_folder_dropdown(self.local_folder_dropdown, self._local_folder_labels, folder)
        self._apply_both_filter()
        self._apply_local_filter()

    def _on_both_search(self, entry):
        """Live filter local tiles by text as you type."""
        self._apply_both_filter()

    def _on_both_search_activate(self, *_args):
        """Enter/Search button — trigger Wallhaven search and sync with WH tab."""
        query = self.both_search.get_text()
        search_sorting = self._search_sort_opts[self.both_search_sort.get_selected()]
        # Sync to Wallhaven tab
        self.wh_search.set_text(query)
        self.wh_search_sort.set_selected(self._search_sort_opts.index(search_sorting))
        # Trigger the shared search
        self.wh_page = 1
        self._wh_browse_mode = False
        self._wh_current_query = query
        self._wh_current_sorting = search_sorting
        self.both_status.set_label("Searching...")
        self.conf["query"] = query
        self.conf["search_sorting"] = search_sorting
        write_conf(self.conf)
        threading.Thread(
            target=self._load_wh_results, args=(query, search_sorting), daemon=True
        ).start()

    def _apply_both_filter(self):
        folder = self._get_selected_folder(self.both_folder_dropdown, self._both_folder_labels)
        query = self.both_search.get_text().lower()
        child = self.both_flow.get_first_child()
        while child:
            visible = True
            is_local = child.full_path is not None and child.wh_item is None

            if is_local:
                # Folder filter for local wallpapers
                if folder:
                    try:
                        rel = child.full_path.relative_to(WALL_DIR)
                        visible = rel.parts[0] == folder if len(rel.parts) > 1 else False
                    except ValueError:
                        visible = False
                # Text search for local wallpapers (by filename)
                if visible and query:
                    box = child.get_child()
                    lbl = None
                    c = box.get_first_child()
                    while c:
                        if isinstance(c, Gtk.Label):
                            lbl = c
                            break
                        c = c.get_next_sibling()
                    if lbl:
                        visible = query in lbl.get_label().lower()
            # Wallhaven tiles: always show (filtered by API search, not locally)

            child.set_visible(visible)
            child = child.get_next_sibling()

    def _apply_both_filter_once(self):
        self._apply_both_filter()
        return False  # don't repeat

    def _on_both_activated(self, flow, child):
        if child.wh_item:
            self.both_status.set_label(f"Downloading {child.wh_item['id']}...")
            threading.Thread(
                target=self._download_and_apply_wh, args=(child.wh_item,), daemon=True
            ).start()
        elif child.full_path:
            threading.Thread(
                target=apply_wallpaper,
                args=(child.full_path, self.retheme, self._refresh_theme_css),
                daemon=True,
            ).start()
            self.both_status.set_label(f"Applied: {child.full_path.name}")

    # ── Wallhaven tab ──

    def _build_wallhaven_tab(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_start(10)
        box.set_margin_end(10)
        box.set_margin_top(8)

        # Sorting buttons + search bar
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)

        # Sorting quick-buttons
        self._sort_buttons = {}
        self._wh_sort_icons = {}
        sort_items = [
            ("date_added",  "\U000f00ed", "Latest uploads"),
            ("toplist", "\U000f04ce", "Top rated"),
            ("hot",     "\U000f0238", "Trending"),
            ("random",  "\U000f049d", "Random"),
        ]
        for sort_id, icon, tooltip in sort_items:
            self._wh_sort_icons[sort_id] = icon
            btn = Gtk.Button(label=icon)
            btn.set_tooltip_text(tooltip)
            btn.add_css_class("sort-btn")
            btn.connect("clicked", self._on_sort_clicked, sort_id)
            search_box.append(btn)
            self._sort_buttons[sort_id] = btn

        # Highlight the active sort button
        self._update_sort_buttons()

        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep.set_margin_start(4)
        sep.set_margin_end(4)
        search_box.append(sep)

        # Search sort dropdown (filters search results only, not browse buttons)
        self._search_sort_opts = ["date_added", "toplist", "hot", "random", "relevance"]
        self._search_sort_labels = ["Latest", "Top Rated", "Trending", "Random", "Relevance"]
        search_sort_model = Gtk.StringList.new(self._search_sort_labels)
        self.wh_search_sort = Gtk.DropDown(model=search_sort_model)
        self.wh_search_sort.set_tooltip_text("Sort search results")
        current_ss = self.conf.get("search_sorting", "date_added")
        if current_ss in self._search_sort_opts:
            self.wh_search_sort.set_selected(self._search_sort_opts.index(current_ss))
        search_box.append(self.wh_search_sort)

        self.wh_search = Gtk.SearchEntry(placeholder_text="Search Wallhaven...")
        self.wh_search.set_text(self.conf.get("query", ""))
        self.wh_search.set_hexpand(True)
        self.wh_search.connect("activate", self._on_wh_search)
        search_box.append(self.wh_search)

        search_btn = Gtk.Button(label="Search")
        search_btn.connect("clicked", self._on_wh_search)
        search_box.append(search_btn)
        box.append(search_box)

        # Track active view state for pagination
        self._wh_browse_mode = True
        self._wh_current_query = ""
        self._wh_current_sorting = self.conf.get("sorting", "date_added")

        # Grid
        self.wh_scroll = Gtk.ScrolledWindow(vexpand=True)
        self.wh_flow = Gtk.FlowBox()
        self.wh_flow.set_valign(Gtk.Align.START)
        self.wh_flow.set_max_children_per_line(5)
        self.wh_flow.set_min_children_per_line(3)
        self.wh_flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.wh_flow.set_homogeneous(True)
        self.wh_flow.connect("child-activated", self._on_wh_activated)
        self.wh_scroll.set_child(self.wh_flow)
        box.append(self.wh_scroll)

        # Pagination
        page_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        page_box.set_halign(Gtk.Align.CENTER)
        page_box.set_margin_bottom(8)

        prev_btn = Gtk.Button(label="◀ Prev")
        prev_btn.connect("clicked", lambda _: self._wh_change_page(-1))
        page_box.append(prev_btn)

        self.wh_page_label = Gtk.Label(label="Page 1")
        page_box.append(self.wh_page_label)

        next_btn = Gtk.Button(label="Next ▶")
        next_btn.connect("clicked", lambda _: self._wh_change_page(1))
        page_box.append(next_btn)

        box.append(page_box)

        # Status
        self.wh_status = Gtk.Label(label="Press Search or Enter to browse")
        self.wh_status.add_css_class("settings-label")
        box.append(self.wh_status)

        return box

    def _on_sort_clicked(self, _btn, sort_id):
        """Browse button: show ALL wallpapers with this sorting, no query."""
        self.conf["sorting"] = sort_id
        write_conf(self.conf)
        self._update_sort_buttons()
        self.wh_page = 1
        self._wh_browse_mode = True
        self._wh_current_query = ""
        self._wh_current_sorting = sort_id
        self.wh_status.set_label(f"Loading {sort_id}...")
        threading.Thread(
            target=self._load_wh_results, args=("", sort_id), daemon=True
        ).start()

    def _update_sort_buttons(self):
        """Highlight the active sort button in both Wallhaven and Both tabs."""
        current = self.conf.get("sorting", "date_added")
        for buttons in [self._sort_buttons, getattr(self, '_both_sort_buttons', {})]:
            for sid, btn in buttons.items():
                if sid == current:
                    btn.add_css_class("sort-active")
                else:
                    btn.remove_css_class("sort-active")

    def _on_wh_search(self, *_args):
        query = self.wh_search.get_text()
        search_sorting = self._search_sort_opts[self.wh_search_sort.get_selected()]
        self.wh_page = 1
        self._wh_browse_mode = False
        self._wh_current_query = query
        self._wh_current_sorting = search_sorting
        self.wh_status.set_label("Searching..." if query.strip() else "Loading...")
        self.conf["query"] = query
        self.conf["search_sorting"] = search_sorting
        write_conf(self.conf)
        threading.Thread(
            target=self._load_wh_results, args=(query, search_sorting), daemon=True
        ).start()

    def _load_wh_results(self, query, sorting=None):
        self.conf = read_conf()
        # Use the explicit sorting for this request (browse button or search
        # dropdown) so the two modes stay independent of conf["sorting"].
        conf = dict(self.conf)
        if sorting:
            conf["sorting"] = sorting
        items = wh_search(conf, query=query, page=self.wh_page)
        self.wh_items = items

        # Download thumbs for current results
        for item in items:
            wh_download_thumb(item)

        # Clean up thumbnails not in current results
        keep_ids = {item["id"] for item in items}
        clean_wh_thumbs(keep_ids=keep_ids)

        GLib.idle_add(self._populate_wh_grid, items)

        # Refresh both tab with new wallhaven results
        threading.Thread(target=self._populate_both_tab, daemon=True).start()

    def _populate_wh_grid(self, items):
        # Clear existing
        while True:
            child = self.wh_flow.get_first_child()
            if child is None:
                break
            self.wh_flow.remove(child)

        ignores = read_ignores()
        shown = 0
        for item in items:
            if item["id"] in ignores:
                continue
            tp = wh_thumb_path(item)
            res = item.get("resolution", "?")
            label = f"{item['id']}  {res}"
            tile = WallpaperTile(tp, label, wh_item=item,
                                 on_save=self._save_wh_only,
                                 on_ignore=self._ignore_wh)
            self.wh_flow.append(tile)
            shown += 1

        self.wh_page_label.set_label(f"Page {self.wh_page}")
        self.wh_status.set_label(f"{shown} results  ·  right-click for options")

        # Scroll to top
        adj = self.wh_scroll.get_vadjustment()
        if adj:
            adj.set_value(0)
        return False

    def _wh_change_page(self, delta):
        self.wh_page = max(1, self.wh_page + delta)
        self.wh_status.set_label("Loading...")
        threading.Thread(
            target=self._load_wh_results,
            args=(self._wh_current_query, self._wh_current_sorting),
            daemon=True,
        ).start()

    def _on_wh_activated(self, flow, child):
        if child.wh_item:
            self.wh_status.set_label(f"Downloading {child.wh_item['id']}...")
            threading.Thread(
                target=self._download_and_apply_wh, args=(child.wh_item,), daemon=True
            ).start()

    def _download_and_apply_wh(self, item):
        path = wh_download_full(item)
        if path:
            apply_wallpaper(path, self.retheme, callback=self._refresh_theme_css)
            # Clean up other cached full-size downloads (keep only current)
            removed = clean_wh_full_cache()
            msg = f"Applied: {path.name}"
            if removed:
                msg += f"  ({removed} cached file{'s' if removed != 1 else ''} cleaned)"
            GLib.idle_add(self.wh_status.set_label, msg)
        else:
            GLib.idle_add(self.wh_status.set_label, "Download failed")

    def _save_wh_only(self, item):
        """Context menu: download to ~/Pictures/Wallpaper/wallhaven/ (library)."""
        self.wh_status.set_label(f"Saving {item['id']} to library...")
        def do_save():
            path = wh_download_full(item, dest_dir=WH_SAVED)
            if path:
                GLib.idle_add(self.wh_status.set_label, f"Saved to library: {path.name}")
            else:
                GLib.idle_add(self.wh_status.set_label, "Save failed")
        threading.Thread(target=do_save, daemon=True).start()

    def _ignore_wh(self, item):
        """Context menu: add to ignore list and remove tile from grid."""
        wid = item["id"]
        add_ignore(wid)
        # Remove the tile from the grid
        child = self.wh_flow.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            if hasattr(child, 'wh_item') and child.wh_item and child.wh_item.get("id") == wid:
                self.wh_flow.remove(child)
                break
            child = nxt
        self.wh_status.set_label(f"Ignored: {wid}")

    def _refresh_theme_css(self):
        """Re-read colors.css and reload app styling after a theme change."""
        win = self.get_active_window()
        if win:
            self._apply_theme_css(win)

    # ── Theme toggle ──

    def _on_theme_toggled(self, btn):
        self.retheme = btn.get_active()
        write_theme_state(self.retheme)

    def _on_header_rotate_toggled(self, btn):
        active = btn.get_active()
        self._conf_update("auto_rotate", "on" if active else "off")
        if active:
            interval = self.conf.get("rotate_interval", "30")
            threading.Thread(target=enable_timer, args=(interval,), daemon=True).start()
        else:
            threading.Thread(target=disable_timer, daemon=True).start()

    # ── Settings ──

    def _on_settings_clicked(self, _btn):
        dialog = Adw.Dialog()
        dialog.set_title("Wallhaven Settings")
        dialog.set_content_width(480)
        dialog.set_content_height(560)

        self.conf = read_conf()

        page = Adw.PreferencesPage()

        # ── Source group ──
        src_group = Adw.PreferencesGroup(title="Source")
        source_row = Adw.ComboRow(title="Wallpaper source")
        source_model = Gtk.StringList.new(["Local only", "Wallhaven only", "Both"])
        source_row.set_model(source_model)
        src_map = {"local": 0, "wallhaven": 1, "both": 2}
        source_row.set_selected(src_map.get(self.conf.get("source", "local"), 0))
        source_row.connect("notify::selected", self._on_source_changed)
        src_group.add(source_row)
        page.add(src_group)

        # ── Auto-rotate group ──
        rotate_group = Adw.PreferencesGroup(title="Auto-rotate")

        self._rotate_switch = Adw.SwitchRow(title="Change wallpaper automatically")
        self._rotate_switch.set_subtitle("Periodically pick a new random wallpaper and theme")
        auto_on = self.conf.get("auto_rotate", "off") == "on"
        self._rotate_switch.set_active(auto_on)
        rotate_group.add(self._rotate_switch)

        interval_row = Adw.ComboRow(title="Change every")
        interval_model = Gtk.StringList.new([label for label, _ in ROTATE_INTERVALS])
        interval_row.set_model(interval_model)
        current_interval = self.conf.get("rotate_interval", "30")
        interval_vals = [v for _, v in ROTATE_INTERVALS]
        interval_row.set_selected(
            interval_vals.index(current_interval) if current_interval in interval_vals else 3
        )
        self._interval_row = interval_row
        rotate_group.add(interval_row)

        # Connect signals after initial setup to avoid triggering on load
        self._rotate_switch.connect("notify::active", self._on_rotate_toggled)
        interval_row.connect("notify::selected", self._on_interval_changed)

        page.add(rotate_group)

        # ── Search group ──
        search_group = Adw.PreferencesGroup(title="Search")

        query_row = Adw.EntryRow(title="Default query")
        query_row.set_text(self.conf.get("query", ""))
        query_row.connect("changed", lambda r: self._conf_update("query", r.get_text()))
        search_group.add(query_row)

        sort_row = Adw.ComboRow(title="Sorting")
        sort_model = Gtk.StringList.new(["random", "toplist", "hot", "date_added", "relevance"])
        sort_row.set_model(sort_model)
        sort_opts = ["random", "toplist", "hot", "date_added", "relevance"]
        current_sort = self.conf.get("sorting", "date_added")
        sort_row.set_selected(sort_opts.index(current_sort) if current_sort in sort_opts else 0)
        sort_row.connect("notify::selected", lambda r, _:
            self._conf_update("sorting", sort_opts[r.get_selected()]))
        search_group.add(sort_row)
        page.add(search_group)

        # ── Filters group ──
        filter_group = Adw.PreferencesGroup(title="Filters")

        cats = self.conf.get("categories", "111")
        self._cat_checks = {}
        for i, name in enumerate(["General", "Anime", "People"]):
            row = Adw.SwitchRow(title=name)
            row.set_active(len(cats) > i and cats[i] == "1")
            row.connect("notify::active", self._on_cat_toggled)
            self._cat_checks[i] = row
            filter_group.add(row)

        pur = self.conf.get("purity", "100")
        self._pur_checks = {}
        for i, name in enumerate(["SFW", "Sketchy", "NSFW"]):
            row = Adw.SwitchRow(title=name)
            row.set_active(len(pur) > i and pur[i] == "1")
            row.connect("notify::active", self._on_pur_toggled)
            self._pur_checks[i] = row
            filter_group.add(row)

        res_row = Adw.ComboRow(title="Min resolution")
        res_model = Gtk.StringList.new(["2560x1440", "3840x2160", "1920x1080", "Any"])
        res_row.set_model(res_model)
        res_opts = ["2560x1440", "3840x2160", "1920x1080", ""]
        current_res = self.conf.get("atleast", "2560x1440")
        res_row.set_selected(res_opts.index(current_res) if current_res in res_opts else 0)
        res_row.connect("notify::selected", lambda r, _:
            self._conf_update("atleast", res_opts[r.get_selected()]))
        filter_group.add(res_row)

        ratio_row = Adw.ComboRow(title="Aspect ratio")
        ratio_model = Gtk.StringList.new(["16x9", "21x9", "16x10", "Any"])
        ratio_row.set_model(ratio_model)
        ratio_opts = ["16x9", "21x9", "16x10", ""]
        current_ratio = self.conf.get("ratios", "16x9")
        ratio_row.set_selected(ratio_opts.index(current_ratio) if current_ratio in ratio_opts else 0)
        ratio_row.connect("notify::selected", lambda r, _:
            self._conf_update("ratios", ratio_opts[r.get_selected()]))
        filter_group.add(ratio_row)
        page.add(filter_group)

        # ── Account group ──
        acct_group = Adw.PreferencesGroup(title="Account")
        key_row = Adw.PasswordEntryRow(title="API key")
        key_row.set_text(self.conf.get("api_key", ""))
        key_row.connect("changed", lambda r: self._conf_update("api_key", r.get_text()))
        acct_group.add(key_row)
        page.add(acct_group)

        # ── Cache group ──
        cache_group = Adw.PreferencesGroup(title="Cache")

        self._cache_size_row = Adw.ActionRow(
            title="Wallhaven cache size",
            subtitle=cache_size_str(),
        )
        cache_group.add(self._cache_size_row)

        clear_btn_row = Adw.ActionRow(title="Clear all cached downloads and thumbnails")
        clear_btn = Gtk.Button(label="Clear Cache")
        clear_btn.set_valign(Gtk.Align.CENTER)
        clear_btn.connect("clicked", self._on_clear_cache)
        clear_btn_row.add_suffix(clear_btn)
        cache_group.add(clear_btn_row)

        page.add(cache_group)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        toolbar.set_content(page)
        dialog.set_child(toolbar)

        win = self.get_active_window()
        dialog.present(win)

    def _on_source_changed(self, row, _pspec):
        src_map = {0: "local", 1: "wallhaven", 2: "both"}
        self._conf_update("source", src_map.get(row.get_selected(), "local"))

    def _on_rotate_toggled(self, row, _pspec):
        active = row.get_active()
        self._conf_update("auto_rotate", "on" if active else "off")
        if active:
            interval = self.conf.get("rotate_interval", "30")
            threading.Thread(target=enable_timer, args=(interval,), daemon=True).start()
        else:
            threading.Thread(target=disable_timer, daemon=True).start()

    def _on_interval_changed(self, row, _pspec):
        interval_vals = [v for _, v in ROTATE_INTERVALS]
        selected = interval_vals[row.get_selected()]
        self._conf_update("rotate_interval", selected)
        # If auto-rotate is active, restart the timer with new interval
        if self.conf.get("auto_rotate", "off") == "on":
            threading.Thread(target=enable_timer, args=(selected,), daemon=True).start()

    def _on_cat_toggled(self, *_args):
        cats = "".join("1" if self._cat_checks[i].get_active() else "0" for i in range(3))
        self._conf_update("categories", cats)

    def _on_pur_toggled(self, *_args):
        pur = "".join("1" if self._pur_checks[i].get_active() else "0" for i in range(3))
        self._conf_update("purity", pur)

    def _on_clear_cache(self, _btn):
        clear_all_wh_cache()
        if hasattr(self, '_cache_size_row'):
            self._cache_size_row.set_subtitle(cache_size_str())

    def _conf_update(self, key, value):
        self.conf[key] = value
        write_conf(self.conf)


def main():
    app = WallpaperApp()
    app.run(None)


if __name__ == "__main__":
    main()
