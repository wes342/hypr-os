#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │        hypr-os install script            │
# │  Symlinks dotfiles to ~/.config/         │
# └──────────────────────────────────────────┘

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config"
CONFIG_DEST="$HOME/.config"
BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

echo "╔══════════════════════════════════════╗"
echo "║         hypr-os installer            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Backup existing configs ───────────────
BACKED_UP=false
for dir in "$CONFIG_SRC"/*/; do
    name=$(basename "$dir")
    target="$CONFIG_DEST/$name"

    if [[ -e "$target" && ! -L "$target" ]]; then
        if [[ "$BACKED_UP" == false ]]; then
            info "Backing up existing configs to $BACKUP_DIR/"
            mkdir -p "$BACKUP_DIR"
            BACKED_UP=true
        fi
        mv "$target" "$BACKUP_DIR/$name"
        warn "Backed up: $name"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi
done

# ── Create symlinks ──────────────────────
info "Creating symlinks..."
for dir in "$CONFIG_SRC"/*/; do
    name=$(basename "$dir")
    target="$CONFIG_DEST/$name"

    ln -sf "$dir" "$target"
    info "Linked: $name -> $target"
done

# ── Special: hyprpaper and hyprlock go inside hypr dir ──
# They're already in config/hypr/ via the symlink, but some apps
# expect them at specific paths
for conf in hyprpaper.conf; do
    if [[ -f "$CONFIG_SRC/hypr/$conf" ]]; then
        info "  hypr/$conf included via symlink"
    fi
done

# Symlink hyprlock config
if [[ -d "$CONFIG_SRC/hyprlock" ]]; then
    ln -sf "$CONFIG_SRC/hyprlock/hyprlock.conf" "$CONFIG_DEST/hypr/hyprlock.conf" 2>/dev/null || true
fi

# ── Starship config ──────────────────────
if [[ -f "$CONFIG_SRC/starship/starship.toml" ]]; then
    ln -sf "$CONFIG_SRC/starship/starship.toml" "$CONFIG_DEST/starship.toml"
    info "Linked: starship.toml"
fi

# ── Create directories ───────────────────
mkdir -p "$HOME/Pictures/Wallpaper"
mkdir -p "$HOME/Pictures/Screenshots"
mkdir -p "$HOME/.cache/hypr"

info "Created ~/Pictures/Wallpaper/ and ~/Pictures/Screenshots/"

# ── Make scripts executable ──────────────
chmod +x "$SCRIPT_DIR/scripts/"*.sh
chmod +x "$CONFIG_SRC/hypr/scripts/"*.sh 2>/dev/null || true
info "Scripts marked executable"

# ── Set HYPR_OS_DIR for theme script ─────
SHELL_RC="$HOME/.bashrc"
[[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "HYPR_OS_DIR" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# hypr-os" >> "$SHELL_RC"
    echo "export HYPR_OS_DIR=\"$SCRIPT_DIR\"" >> "$SHELL_RC"
    echo 'export STARSHIP_CONFIG="$HOME/.config/starship.toml"' >> "$SHELL_RC"
    echo 'eval "$(starship init bash)"' >> "$SHELL_RC"
    echo 'eval "$(zoxide init bash)"' >> "$SHELL_RC"
    info "Added shell config to $SHELL_RC"
fi

echo ""
info "Installation complete!"
info "Reboot or restart Hyprland to apply changes."
info "Press SUPER+B to set a random wallpaper and apply theming."
echo ""

if [[ "$BACKED_UP" == true ]]; then
    warn "Your old configs were backed up to: $BACKUP_DIR/"
fi
