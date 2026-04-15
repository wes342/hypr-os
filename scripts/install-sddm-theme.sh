#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  Install the hypr-os SDDM greeter theme. │
# │  Symlinks the repo theme into            │
# │  /usr/share/sddm/themes/ so theme.sh     │
# │  can regenerate colors without sudo.     │
# └──────────────────────────────────────────┘

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME_SRC="$REPO_DIR/config/sddm/hypr-os"
THEME_DEST="/usr/share/sddm/themes/hypr-os"
CONF_DIR="/etc/sddm.conf.d"
CONF_FILE="$CONF_DIR/10-hypr-os.conf"

if [[ ! -d "$THEME_SRC" ]]; then
    error "Theme source missing: $THEME_SRC"
    exit 1
fi

if ! command -v sddm &>/dev/null; then
    error "sddm is not installed. Install it with: sudo pacman -S sddm"
    exit 1
fi

info "Linking $THEME_SRC -> $THEME_DEST"
sudo rm -rf "$THEME_DEST"
sudo ln -s "$THEME_SRC" "$THEME_DEST"

info "Writing $CONF_FILE"
sudo mkdir -p "$CONF_DIR"
sudo tee "$CONF_FILE" >/dev/null << EOF
[Theme]
Current=hypr-os
CursorTheme=Adwaita
Font=Iosevka Nerd Font

[General]
# Use Qt6 greeter so our Main.qml (QtQuick 6 imports) runs.
GreeterEnvironment=QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOF

info "Done. The new theme is active on the next reboot."
info "To preview without rebooting: sddm-greeter-qt6 --test-mode --theme $THEME_DEST"
