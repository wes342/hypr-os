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

WITH_PACKAGES=false
DESKTOP="hyprland"
for arg in "$@"; do
    case "$arg" in
        --with-packages|-p) WITH_PACKAGES=true ;;
        --desktop=*) DESKTOP="${arg#*=}" ;;
        -h|--help)
            echo "Usage: ./install.sh [--desktop hyprland|sway] [--with-packages]"
            echo ""
            echo "  --desktop hyprland    Install Hyprland configs (default)."
            echo "  --desktop sway        Install Sway/SwayFX configs."
            echo "  --with-packages, -p   Also install system dependencies via"
            echo "                        install-packages.sh (requires sudo)."
            exit 0
            ;;
        --desktop)
            # handled by the index-based parser below
            ;;
    esac
done

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--desktop" ]]; then
        DESKTOP="${args[$((i + 1))]:-}"
    fi
done

case "$DESKTOP" in
    hyprland|sway) ;;
    *)
        error "Unknown desktop '$DESKTOP'. Use hyprland or sway."
        exit 1
        ;;
esac

echo "╔══════════════════════════════════════╗"
echo "║         hypr-os installer            ║"
echo "╚══════════════════════════════════════╝"
echo ""
info "Desktop target: $DESKTOP"

if [[ "$DESKTOP" == "sway" ]]; then
    for stale in hypr hyprlock hypridle; do
        [[ -L "$CONFIG_DEST/$stale" ]] && rm "$CONFIG_DEST/$stale"
    done
else
    [[ -L "$CONFIG_DEST/sway" ]] && rm "$CONFIG_DEST/sway"
    [[ -L "$CONFIG_DEST/swaylock" ]] && rm "$CONFIG_DEST/swaylock"
fi

# ── Optional: install system packages ────
if [[ "$WITH_PACKAGES" == true ]]; then
    if [[ -x "$SCRIPT_DIR/install-packages.sh" ]]; then
        info "Running install-packages.sh..."
        "$SCRIPT_DIR/install-packages.sh" --desktop "$DESKTOP"
        echo ""
    else
        error "install-packages.sh missing or not executable."
    fi
fi

# ── Backup existing configs ───────────────
BACKED_UP=false
for dir in "$CONFIG_SRC"/*/; do
    name=$(basename "$dir")
    if [[ "$DESKTOP" == "hyprland" && "$name" =~ ^(sway|swaylock)$ ]]; then
        continue
    fi
    if [[ "$DESKTOP" == "sway" && "$name" =~ ^(hypr|hyprlock|hypridle)$ ]]; then
        continue
    fi
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
mkdir -p "$CONFIG_DEST"
for dir in "$CONFIG_SRC"/*/; do
    name=$(basename "$dir")
    if [[ "$DESKTOP" == "hyprland" && "$name" =~ ^(sway|swaylock)$ ]]; then
        continue
    fi
    if [[ "$DESKTOP" == "sway" && "$name" =~ ^(hypr|hyprlock|hypridle)$ ]]; then
        continue
    fi
    target="$CONFIG_DEST/$name"

    ln -sf "$dir" "$target"
    info "Linked: $name -> $target"
done

if [[ "$DESKTOP" == "hyprland" ]]; then
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

# ── Seed default wallpaper if user's wallpaper dir is empty ──
if [[ -d "$CONFIG_SRC/wallpapers" ]] && \
   [[ -z "$(find "$HOME/Pictures/Wallpaper" -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null)" ]]; then
    info "Seeding default wallpaper into ~/Pictures/Wallpaper/"
    cp -n "$CONFIG_SRC/wallpapers/"*.{jpg,jpeg,png,webp} "$HOME/Pictures/Wallpaper/" 2>/dev/null || true
fi

# ── Make scripts executable ──────────────
chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/install-packages.sh" 2>/dev/null || true
chmod +x "$CONFIG_SRC/hypr/scripts/"*.sh 2>/dev/null || true
chmod +x "$CONFIG_SRC/sway/scripts/"*.sh 2>/dev/null || true
chmod +x "$CONFIG_SRC/waybar/scripts/"*.sh 2>/dev/null || true
chmod +x "$CONFIG_SRC/waybar/scripts/"*.py 2>/dev/null || true
chmod +x "$CONFIG_SRC/eww/scripts/"*.sh 2>/dev/null || true
chmod +x "$SCRIPT_DIR/scripts/"*.py 2>/dev/null || true
info "Scripts marked executable"

# ── Install systemd user units for wallpaper auto-rotate ──
SYSTEMD_USER="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER"
for unit in wallpaper-rotate.service wallpaper-rotate.timer; do
    src="$CONFIG_SRC/systemd/user/$unit"
    dest="$SYSTEMD_USER/$unit"
    if [[ "$(readlink -f "$src")" != "$(readlink -f "$dest" 2>/dev/null || true)" ]]; then
        cp -f "$src" "$dest"
    fi
done
systemctl --user daemon-reload 2>/dev/null || true
info "Installed wallpaper-rotate systemd units"

# ── Install wallpaper manager to ~/.local/bin ──
mkdir -p "$HOME/.local/bin"
cp -f "$SCRIPT_DIR/scripts/wallpaper-app.py" "$HOME/.local/bin/hypr-wallpaper"
cp -f "$SCRIPT_DIR/scripts/wallhaven.py" "$HOME/.local/bin/hypr-wallhaven"
cp -f "$SCRIPT_DIR/scripts/launcher-app.py" "$HOME/.local/bin/hypr-launcher"
chmod +x "$HOME/.local/bin/hypr-wallpaper" "$HOME/.local/bin/hypr-wallhaven" "$HOME/.local/bin/hypr-launcher"
info "Installed wallpaper manager and launcher to ~/.local/bin/"

# ── Set HYPR_OS_DIR for theme script ─────
SHELL_RC="$HOME/.bashrc"
[[ -f "$HOME/.zshrc" ]] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "HYPR_OS_DIR" "$SHELL_RC" 2>/dev/null; then
    {
        echo ""
        echo "# hypr-os"
        echo "export HYPR_OS_DIR=\"$SCRIPT_DIR\""
        echo "[ -r \"\$HYPR_OS_DIR/config/bash/bashrc.hypros\" ] && source \"\$HYPR_OS_DIR/config/bash/bashrc.hypros\""
    } >> "$SHELL_RC"
    info "Added shell config to $SHELL_RC"
fi

# ── Generate the initial theme so colors.css etc. exist ──
if command -v magick &>/dev/null; then
    # Use any wallpaper we can find (including the seed we just copied)
    SEED=$(find "$HOME/Pictures/Wallpaper" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        2>/dev/null | head -1)
    if [[ -n "$SEED" ]]; then
        info "Generating initial theme from $(basename "$SEED")..."
        echo "$SEED" > "$HOME/.cache/hypr/current_wallpaper"
        HYPR_OS_DIR="$SCRIPT_DIR" "$SCRIPT_DIR/scripts/theme.sh" "$SEED" || \
            warn "theme.sh failed — run it manually after first login."
    fi
else
    warn "imagemagick not installed — theme generation skipped."
    warn "Run './install.sh --with-packages' or install dependencies first."
fi

echo ""
info "Installation complete!"
if [[ "$DESKTOP" == "sway" ]]; then
    info "Log out and start the SwayFX/Sway session to apply changes."
else
    info "Reboot or restart Hyprland to apply changes."
fi
info "Press SUPER+B to re-roll the wallpaper and theme."
echo ""

if [[ "$BACKED_UP" == true ]]; then
    warn "Your old configs were backed up to: $BACKUP_DIR/"
fi
