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

# ── Enable multilib repo (needed for 32-bit libs / some AUR builds) ──
if ! pacman -Sl multilib &>/dev/null; then
    info "Enabling [multilib] repo in /etc/pacman.conf..."
    sudo sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
    sudo pacman -Sy
else
    info "[multilib] already enabled."
fi

# ── Nicer pacman output: color + progress bar + verbose lists ──
if ! grep -q '^Color' /etc/pacman.conf; then
    info "Enabling Color / ILoveCandy / VerbosePkgLists in pacman.conf..."
    sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
    sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
    if ! grep -q '^ILoveCandy' /etc/pacman.conf; then
        sudo sed -i '/^Color$/a ILoveCandy' /etc/pacman.conf
    fi
fi

# ── Official repo packages ───────────────────────────────
PACMAN_PKGS=(
    # Build prerequisites (needed for AUR helper bootstrap + makepkg)
    git base-devel

    # Hyprland stack
    hyprland hyprpaper hyprlock hypridle

    # Bar, launcher, notifications
    waybar rofi-wayland swaync

    # Terminals
    kitty alacritty

    # System / process monitors
    btop htop lm_sensors nvtop

    # File manager + thumbnailers + archives
    thunar thunar-archive-plugin tumbler ffmpegthumbnailer ark ranger

    # Tooling the scripts rely on
    imagemagick jq python curl bc

    # Clipboard and screenshotting
    wl-clipboard cliphist grim slurp satty

    # Shell niceties (install.sh wires these into bashrc)
    starship zoxide fastfetch fzf bat chafa

    # Media / audio
    ncmpcpp mpd cava playerctl

    # Fonts + icons
    ttf-iosevka-nerd ttf-jetbrains-mono-nerd ttf-font-awesome
    noto-fonts noto-fonts-cjk noto-fonts-emoji
    papirus-icon-theme adwaita-icon-theme

    # Audio stack (wpctl used by waybar) + GUI mixer
    pipewire pipewire-pulse pipewire-alsa wireplumber pwvucontrol

    # Qt/Wayland + XDG portals
    qt5-wayland qt6-wayland
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils

    # GTK / polkit / tray
    polkit-gnome network-manager-applet

    # Browsers + everyday apps
    firefox discord code

    # Gaming (needs multilib)
    steam gamescope mangohud lib32-mangohud goverlay wine winetricks
)

# NVIDIA-specific bits (only if an NVIDIA GPU is present)
if lspci 2>/dev/null | grep -qi nvidia; then
    info "NVIDIA GPU detected — including nvidia-utils"
    PACMAN_PKGS+=(nvidia-utils)
fi

# ── AUR packages ────────────────────────────────────────
AUR_PKGS=(
    eww                    # widget toolkit for waybar dropdowns (AUR-only)
    ghostty                # second terminal
    hyprshot               # screenshotting helper used by keybinds
    nwg-dock-hyprland      # dock
    blesh-git              # ble.sh: fish-style autosuggestions for bash
)

# ── Install ─────────────────────────────────────────────
info "Installing official repo packages (${#PACMAN_PKGS[@]} packages)..."
sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"

# Detect AUR helper; bootstrap yay if none is present
AUR_HELPER=""
for h in paru yay; do
    if command -v "$h" &>/dev/null; then
        AUR_HELPER="$h"; break
    fi
done

if [[ -z "$AUR_HELPER" ]]; then
    info "No AUR helper found — bootstrapping yay from AUR..."
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/yay-bin.git "$TMPDIR/yay-bin"
    (cd "$TMPDIR/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$TMPDIR"
    if command -v yay &>/dev/null; then
        AUR_HELPER="yay"
        info "yay installed."
    else
        warn "yay bootstrap failed — install an AUR helper manually, then rerun."
    fi
fi

if [[ -n "$AUR_HELPER" ]]; then
    info "Installing AUR packages via $AUR_HELPER (${#AUR_PKGS[@]} packages)..."
    "$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}" || \
        warn "Some AUR packages failed; you can retry individually."
else
    warn "Skipping AUR packages. Install these manually once an AUR helper is available:"
    for p in "${AUR_PKGS[@]}"; do
        echo "    $p"
    done
fi

info "Done. Run ./install.sh next to link configs."
