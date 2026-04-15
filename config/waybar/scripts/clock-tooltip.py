#!/usr/bin/env python3
"""Render a pango tooltip for the waybar clock module.

Layout:
    [LARGE TIME]        (uses theme accent)
    [date line]
                        (blank)
    [weather icon] [temp]  [conditions]
    [city, region · feels like]
    [humidity · wind]
                        (blank)
    [horizontal rule]
                        (blank)
    Su Mo Tu We Th Fr Sa
     1  2  3  4  5  6  7
       ...                (today highlighted with accent bg)

Theme colors are read from ~/.config/waybar/colors.css.
Weather location: HYPR_OS_WEATHER_LOCATION env, else
    ~/.config/hypr-os/weather-location (created with 93013 default).
Weather is cached at /tmp/hypr-os-weather.cache.json for 15 minutes.
"""

import calendar
import datetime
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

HOME = Path.home()
COLORS_CSS = HOME / ".config" / "waybar" / "colors.css"
LOC_FILE = HOME / ".config" / "hypr-os" / "weather-location"
CACHE_WEATHER = Path("/tmp/hypr-os-weather.cache.json")
WEATHER_CACHE_SECONDS = 15 * 60

DEFAULT_LOCATION = "Carpinteria,CA"


def read_color(name: str, fallback: str) -> str:
    """Pull a hex color from the waybar colors.css."""
    if COLORS_CSS.exists():
        m = re.search(
            rf"@define-color\s+{re.escape(name)}\s+(#[0-9a-fA-F]{{6}})",
            COLORS_CSS.read_text(),
        )
        if m:
            return m.group(1)
    return fallback


def get_location() -> str:
    env = os.environ.get("HYPR_OS_WEATHER_LOCATION", "").strip()
    if env:
        return env
    LOC_FILE.parent.mkdir(parents=True, exist_ok=True)
    if not LOC_FILE.exists():
        LOC_FILE.write_text(
            "# hypr-os weather location\n"
            "# Set to a ZIP, city name, airport code, or coordinates.\n"
            "# Leave commented to use auto-detect (IP geolocation).\n"
            f"{DEFAULT_LOCATION}\n"
        )
    for line in LOC_FILE.read_text().splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            return s
    return ""  # auto-detect


def fetch_weather() -> dict | None:
    """Return cached or freshly fetched wttr.in JSON."""
    if (
        CACHE_WEATHER.exists()
        and time.time() - CACHE_WEATHER.stat().st_mtime < WEATHER_CACHE_SECONDS
    ):
        try:
            return json.loads(CACHE_WEATHER.read_text())
        except Exception:
            pass

    location = get_location()
    url = f"https://wttr.in/{location}?format=j1"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
        CACHE_WEATHER.write_text(json.dumps(data))
        return data
    except Exception:
        return None


# Nerd-font Material Design weather icons (kept as escape sequences so the
# script survives any encoding round-trips).
WEATHER_ICONS = {
    "thunder": "\U000f0593",  # 󰖓
    "snow":    "\U000f0598",  # 󰖘
    "rain":    "\U000f0596",  # 󰖖
    "fog":     "\U000f0591",  # 󰖑
    "cloud":   "\U000f0590",  # 󰖐
    "partly":  "\U000f0595",  # 󰖕
    "clear":   "\U000f0599",  # 󰖙
    "default": "\U000f0590",
}


def weather_icon(desc: str) -> str:
    d = desc.lower()
    if any(k in d for k in ("thunder", "storm")):
        return WEATHER_ICONS["thunder"]
    if any(k in d for k in ("snow", "sleet", "ice", "blizzard")):
        return WEATHER_ICONS["snow"]
    if any(k in d for k in ("rain", "drizzle", "shower")):
        return WEATHER_ICONS["rain"]
    if any(k in d for k in ("fog", "mist", "haze", "smoke")):
        return WEATHER_ICONS["fog"]
    if any(k in d for k in ("partly", "broken")):
        return WEATHER_ICONS["partly"]
    if any(k in d for k in ("cloud", "overcast")):
        return WEATHER_ICONS["cloud"]
    if any(k in d for k in ("clear", "sunny")):
        return WEATHER_ICONS["clear"]
    return WEATHER_ICONS["default"]


def pango_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
    )


def render_weather(accent: str, dim: str, fg: str) -> str:
    data = fetch_weather()
    if not data:
        return f'   <span foreground="{dim}">Weather unavailable</span>'

    cur = data["current_condition"][0]
    near = data["nearest_area"][0]
    temp_f   = cur["temp_F"]
    feels    = cur["FeelsLikeF"]
    desc     = cur["weatherDesc"][0]["value"].strip()
    humidity = cur["humidity"]
    wind     = cur["windspeedMiles"]
    city     = near["areaName"][0]["value"]
    region   = near["region"][0]["value"]
    icon = weather_icon(desc)

    desc_e = pango_escape(desc)
    city_e = pango_escape(city)
    region_e = pango_escape(region)

    return (
        f'   <span size="x-large" foreground="{accent}">{icon}</span>  '
        f'<span size="large" weight="bold" foreground="{fg}">{temp_f}°F</span>  '
        f'<span foreground="{dim}">{desc_e}</span>\n'
        f'   <span foreground="{dim}">{city_e}, {region_e}  ·  Feels {feels}°F</span>\n'
        f'   <span foreground="{dim}">Humidity {humidity}%  ·  Wind {wind} mph</span>'
    )


def render_calendar(accent: str, accent_dim: str, dim: str, fg: str) -> str:
    now = datetime.date.today()
    cal = calendar.TextCalendar(calendar.SUNDAY)
    weeks = cal.monthdayscalendar(now.year, now.month)
    day_names = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    title = now.strftime("%B %Y")

    # 3-char cells (e.g. "  1") give more breathing room than 2-char cells.
    # Each row is 2 lead + 7 * 3 + 6 separators = 29 mono chars.
    CELL = 3
    GRID_WIDTH = 2 + 7 * CELL + 6

    header = "  " + " ".join(
        f'<span foreground="{dim}">{d:>{CELL}}</span>' for d in day_names
    )

    rows = [header]
    for week in weeks:
        cells = []
        for d in week:
            if d == 0:
                cells.append(" " * CELL)
            elif d == now.day:
                cells.append(
                    f'<span bgcolor="{accent_dim}" foreground="{accent}"><b>{d:>{CELL}}</b></span>'
                )
            else:
                cells.append(f'<span foreground="{fg}">{d:>{CELL}}</span>')
        rows.append("  " + " ".join(cells))

    # Center the month/year title over the grid.
    title_pad = " " * max(0, (GRID_WIDTH - len(title)) // 2)

    body = "\n".join(rows)
    # size="large" scales the calendar ~20% vs the rest of the tooltip.
    return (
        f'<span size="large">'
        f'{title_pad}<span foreground="{accent}"><b>{title}</b></span>\n\n'
        f'<tt>{body}</tt>'
        f'</span>'
    )


def main():
    accent     = read_color("accent",     "#5fa8d3")
    accent_dim = read_color("accent_dim", "#222258")
    fg         = read_color("fg",         "#c8d3e0")
    DIM = "#7a8390"
    RULE = "#3a4350"

    now = datetime.datetime.now()
    big_time  = now.strftime("%-I:%M %p")
    date_line = now.strftime("%A, %B %-d, %Y")

    weather = render_weather(accent, DIM, fg)
    cal_block = render_calendar(accent, accent_dim, DIM, fg)

    # The tooltip label width is set by the widest line (the calendar row,
    # ~36 mono chars). We pad the big time and date with leading spaces so
    # they look roughly centered. Pango/GTK has no text-align for labels.
    big_pad  = " " * 12
    date_pad = " " * 4

    sys.stdout.write(
        f'{big_pad}<span font_size="34pt" weight="bold" foreground="{accent}">{big_time}</span>\n'
        f'{date_pad}<span size="large" foreground="{DIM}">{date_line}</span>\n'
        f'\n'
        f'{weather}\n'
        f'\n'
        f'   <span foreground="{RULE}">────────────────────────────────────</span>\n'
        f'\n'
        f'{cal_block}'
    )


if __name__ == "__main__":
    main()
