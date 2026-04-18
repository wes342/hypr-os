#!/usr/bin/env python3
"""Wallhaven API client for hypr-os wallpaper browser.

Usage:
    wallhaven.py search [--query Q] [--page N]   Print rofi entries (label\\0icon\\x1fpath)
    wallhaven.py download <url> [--dest DIR]      Download full image, print local path
    wallhaven.py random                           Fetch one random wallpaper, download, print path
    wallhaven.py settings                         Print current settings as key=value

Config: ~/.config/hypr-os/wallhaven.conf
Cache:  ~/.cache/hypr-os/wallhaven/thumbs/
"""

import hashlib
import json
import os
import sys
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# ── Paths ──

HOME = Path.home()
CONF_FILE = HOME / ".config/hypr-os/wallhaven.conf"
THUMB_DIR = HOME / ".cache/hypr-os/wallhaven/thumbs"
DEST_DIR = HOME / ".cache/hypr-os/wallhaven/full"

DEFAULTS = {
    "api_key": "",
    "query": "",
    "categories": "111",      # 1=general, 1=anime, 1=people
    "purity": "100",          # 1=sfw, 0=sketchy, 0=nsfw
    "sorting": "random",      # random, toplist, hot, latest, relevance
    "atleast": "2560x1440",
    "ratios": "16x9",
    "source": "local",        # local, wallhaven, both
}


def read_conf() -> dict:
    """Read config, creating with defaults if missing."""
    conf = dict(DEFAULTS)
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


def write_conf(conf: dict):
    """Write config file."""
    CONF_FILE.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# hypr-os Wallhaven settings",
        "# Edit via SUPER+ALT+B → Alt+s, or manually.",
        "",
    ]
    for k, v in conf.items():
        lines.append(f"{k}={v}")
    CONF_FILE.write_text("\n".join(lines) + "\n")


def api_search(conf: dict, query: str = "", page: int = 1) -> list:
    """Search Wallhaven, return list of result dicts."""
    params = {
        "categories": conf["categories"],
        "purity": conf["purity"],
        "sorting": conf["sorting"],
        "atleast": conf["atleast"],
        "ratios": conf["ratios"],
        "page": str(page),
    }
    q = query or conf.get("query", "")
    if q:
        params["q"] = q
    if conf.get("api_key"):
        params["apikey"] = conf["api_key"]

    url = "https://wallhaven.cc/api/v1/search?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        return data.get("data", [])
    except Exception as e:
        print(f"API error: {e}", file=sys.stderr)
        return []


def download_file(url: str, dest: Path) -> bool:
    """Download a URL to a local path. Returns True on success."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(resp.read())
        return True
    except Exception as e:
        print(f"Download failed {url}: {e}", file=sys.stderr)
        return False


def thumb_path(item: dict) -> Path:
    """Return the local cache path for a wallpaper's thumbnail."""
    wid = item.get("id", "unknown")
    ext = item.get("file_type", "image/jpeg").split("/")[-1]
    if ext == "jpeg":
        ext = "jpg"
    return THUMB_DIR / f"{wid}.{ext}"


def fetch_thumbs(items: list) -> dict:
    """Download missing thumbnails in parallel. Returns {id: local_path}."""
    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    result = {}

    def dl(item):
        tp = thumb_path(item)
        if tp.exists():
            return item["id"], tp
        thumb_url = item.get("thumbs", {}).get("large", "")
        if thumb_url and download_file(thumb_url, tp):
            return item["id"], tp
        return item["id"], None

    with ThreadPoolExecutor(max_workers=8) as pool:
        futures = {pool.submit(dl, it): it for it in items}
        for f in as_completed(futures):
            wid, path = f.result()
            if path:
                result[wid] = path
    return result


def cmd_search(args: list):
    """Print rofi-compatible entries for search results."""
    conf = read_conf()
    query = ""
    page = 1
    i = 0
    while i < len(args):
        if args[i] == "--query" and i + 1 < len(args):
            query = args[i + 1]; i += 2
        elif args[i] == "--page" and i + 1 < len(args):
            page = int(args[i + 1]); i += 2
        else:
            i += 1

    items = api_search(conf, query=query, page=page)
    if not items:
        sys.stdout.write("(no results)\n")
        return

    thumbs = fetch_thumbs(items)

    for item in items:
        wid = item["id"]
        res = item.get("resolution", "?")
        cat = item.get("category", "?")
        label = f"{wid}  {res}  {cat}"
        tp = thumbs.get(wid)
        if tp:
            sys.stdout.buffer.write(
                f"{label}\0icon\x1f{tp}\n".encode()
            )
        else:
            sys.stdout.write(f"{label}\n")


def cmd_download(args: list):
    """Download a full wallpaper by URL, print the local path."""
    conf = read_conf()
    url = args[0] if args else ""
    dest_dir = DEST_DIR
    i = 0
    while i < len(args):
        if args[i] == "--dest" and i + 1 < len(args):
            dest_dir = Path(args[i + 1]); i += 2
        else:
            i += 1

    if not url or url.startswith("--"):
        # Treat first positional as the wallhaven ID; look up the URL.
        print("Usage: wallhaven.py download <full-image-url>", file=sys.stderr)
        sys.exit(1)

    fname = url.rsplit("/", 1)[-1]
    dest = dest_dir / fname
    if dest.exists():
        print(str(dest))
        return
    dest_dir.mkdir(parents=True, exist_ok=True)
    if download_file(url, dest):
        print(str(dest))
    else:
        sys.exit(1)


def cmd_random(_args: list):
    """Fetch one random wallpaper, download, print local path."""
    conf = read_conf()
    conf_copy = dict(conf)
    conf_copy["sorting"] = "random"
    items = api_search(conf_copy)
    if not items:
        print("No results from Wallhaven.", file=sys.stderr)
        sys.exit(1)

    import random as rnd
    item = rnd.choice(items)
    full_url = item.get("path", "")
    if not full_url:
        print("No image URL in result.", file=sys.stderr)
        sys.exit(1)

    fname = full_url.rsplit("/", 1)[-1]
    dest = DEST_DIR / fname
    DEST_DIR.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        if not download_file(full_url, dest):
            sys.exit(1)
    print(str(dest))


def cmd_resolve(args: list):
    """Given a wallhaven ID, fetch the full image URL and print it."""
    if not args:
        sys.exit(1)
    wid = args[0]
    conf = read_conf()
    params = {}
    if conf.get("api_key"):
        params["apikey"] = conf["api_key"]
    url = f"https://wallhaven.cc/api/v1/w/{wid}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "hypr-os/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read())
        full_url = data.get("data", {}).get("path", "")
        if full_url:
            print(full_url)
        else:
            sys.exit(1)
    except Exception as e:
        print(f"Resolve error: {e}", file=sys.stderr)
        sys.exit(1)


def cmd_settings(_args: list):
    """Print current settings."""
    conf = read_conf()
    for k, v in conf.items():
        print(f"{k}={v}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    cmd = sys.argv[1]
    rest = sys.argv[2:]
    if cmd == "search":
        cmd_search(rest)
    elif cmd == "download":
        cmd_download(rest)
    elif cmd == "random":
        cmd_random(rest)
    elif cmd == "resolve":
        cmd_resolve(rest)
    elif cmd == "settings":
        cmd_settings(rest)
    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
