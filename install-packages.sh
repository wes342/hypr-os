#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │   hypr-os package installer (Arch)       │
# │   Official repo + AUR dependencies       │
# └──────────────────────────────────────────┘

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; }

if ! command -v pacman &>/dev/null; then
    error "This script is for Arch / pacman-based systems only."
    exit 1
fi

# ── Official repo packages ───────────────────────────────
PACMAN_PKGS=(
    # Hyprland stack
    hyprland hyprpaper hyprlock hypridle

    # Bar, launcher, notifications
    waybar rofi-wayland swaync

    # Terminals + terminal-ish apps
    kitty btop

    # File manager
    thunar

    # System monitoring
    lm_sensors nvtop

    # Tooling the scripts rely on
    imagemagick jq python curl bc

    # Clipboard and screenshotting
    wl-clipboard cliphist grim slurp

    # Shell niceties (install.sh wires these into bashrc)
    starship zoxide

    # Fonts + icons
    ttf-iosevka-nerd ttf-font-awesome papirus-icon-theme adwaita-icon-theme

    # Audio (wpctl used by waybar/pulseaudio)
    pipewire pipewire-pulse wireplumber

    # XDG integration
    xdg-desktop-portal-hyprland xdg-utils

    # GTK / polkit / tray
    polkit-gnome network-manager-applet

    # For waybar eww widgets (kept for future — harmless to have)
    eww
)

# NVIDIA-specific bits (only if an NVIDIA GPU is present)
if lspci 2>/dev/null | grep -qi nvidia; then
    info "NVIDIA GPU detected — including nvidia-utils"
    PACMAN_PKGS+=(nvidia-utils)
fi

# ── AUR packages ────────────────────────────────────────
AUR_PKGS=(
    ghostty          # second terminal (may also be in extra on newer Arch)
    hyprshot         # screenshotting helper used by keybinds
)

# ── Install ─────────────────────────────────────────────
info "Installing official repo packages (${#PACMAN_PKGS[@]} packages)..."
sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# Detect AUR helper
AUR_HELPER=""
for h in paru yay; do
    if command -v "$h" &>/dev/null; then
        AUR_HELPER="$h"; break
    fi
done

if [[ -n "$AUR_HELPER" ]]; then
    info "Installing AUR packages via $AUR_HELPER (${#AUR_PKGS[@]} packages)..."
    "$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}" || \
        warn "Some AUR packages failed; you can retry individually."
else
    warn "No AUR helper (paru/yay) found."
    warn "Install paru or yay first, then install these manually:"
    for p in "${AUR_PKGS[@]}"; do
        echo "    $p"
    done
fi

info "Done. Run ./install.sh next to link configs."
