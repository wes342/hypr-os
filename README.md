# hypr-os

A clean, gaming-focused Hyprland desktop environment for Arch Linux with Nvidia + Wayland. Features wallpaper-driven dynamic theming that keeps all applications visually consistent.

## Features

- **Modular Hyprland config** -- split into logical files for easy customization
- **Dynamic theming** -- colors extracted from your wallpaper and applied across all apps
- **Gaming ready** -- Nvidia/Wayland optimized, Steam, Gamescope, MangoHud preconfigured
- **One-command install** -- clone and run `install.sh` on a fresh Arch install
- **Multi-monitor support** -- designed for 1440p primary with easy second monitor expansion

## Quick Start

Fresh Arch install:

```bash
git clone https://github.com/wes342/hypr-os.git ~/dev/hypr-os
cd ~/dev/hypr-os
./install.sh --with-packages      # pulls in hyprland/waybar/fonts/etc. (sudo)
```

If packages are already installed, just run:

```bash
./install.sh
```

What `install.sh` does:

1. Backs up any existing `~/.config/{hypr,waybar,...}` directories
2. Symlinks every `config/*` dir into `~/.config/`
3. Creates `~/Pictures/Wallpaper/` and seeds it with the included default
   wallpaper if empty
4. Runs `theme.sh` once to generate the initial color palette
5. Appends `HYPR_OS_DIR`, `starship`, and `zoxide` lines to your shell rc

After it finishes, log out and back into Hyprland.

## Applications

| Category | Apps |
|----------|------|
| **WM / Desktop** | hyprland, waybar, hyprpaper, hyprlock, hypridle, nwg-dock-hyprland |
| **Launcher** | rofi |
| **Terminals** | kitty, ghostty |
| **File Manager** | thunar, ranger, tumbler, ffmpegthumbnailer, thunar-archive-plugin, ark |
| **Notifications** | swaync |
| **Shell** | starship, zoxide, fastfetch |
| **Media / Audio** | ncmpcpp, cava, playerctl, pavucontrol (or `pwvucontrol` from AUR for the lighter PipeWire-native mixer) |
| **Gaming** | steam, gamescope, mangohud, goverlay, wine, winetricks |
| **Other** | firefox, discord, code (VS Code), htop |

### One-line install (everything above)

`install.sh --with-packages` already runs this for you. If you want to install
the full app set by hand:

```bash
# Official repos
sudo pacman -S --needed git base-devel hyprland waybar hyprpaper hyprlock hypridle \
  rofi-wayland swaync kitty btop htop lm_sensors nvtop thunar thunar-archive-plugin \
  tumbler ffmpegthumbnailer ark ranger imagemagick jq python curl bc wl-clipboard \
  cliphist grim slurp starship zoxide fastfetch ncmpcpp mpd cava playerctl \
  ttf-iosevka-nerd ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts \
  noto-fonts-cjk noto-fonts-emoji papirus-icon-theme adwaita-icon-theme \
  pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol qt5-wayland qt6-wayland \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils polkit-gnome \
  network-manager-applet firefox discord code steam gamescope mangohud \
  lib32-mangohud goverlay wine winetricks

# AUR (requires yay/paru — enable [multilib] in /etc/pacman.conf first for gaming)
yay -S --needed eww ghostty hyprshot nwg-dock-hyprland
```

## Keybindings

See [docs/KEYBINDS.md](docs/KEYBINDS.md) for the full list. Highlights:

| Key | Action |
|-----|--------|
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + Space` | App launcher (rofi) |
| `SUPER + Q` | Close window |
| `SUPER + F` | Full-width window |
| `SUPER + ALT + F` | Fullscreen |
| `SUPER + B` | Random wallpaper + re-theme |
| `SUPER + V` | Toggle floating |
| `SUPER + 1-0` | Switch workspace |

## Theming

The theme system extracts dominant colors from your current wallpaper using `imagemagick` and generates config snippets for each application. Press `SUPER + B` to pick a random wallpaper and automatically update the theme everywhere.

Wallpapers are read from `~/Pictures/Wallpaper/`.

See [docs/THEMING.md](docs/THEMING.md) for details.

## Cleanup: packages you can remove

`archinstall`'s Hyprland profile bundles a few apps that hypr-os
replaces with its own picks. After installing hypr-os you can safely
remove the duplicates:

```bash
sudo pacman -Rns wofi dolphin dunst polkit-kde-agent hyprpolkitagent
```

| Removable | Why | hypr-os uses |
|-----------|-----|--------------|
| `wofi` | duplicate launcher | `rofi-wayland` |
| `dolphin` | duplicate file manager | `thunar` |
| `dunst` | duplicate notification daemon | `swaync` |
| `polkit-kde-agent` | redundant polkit agent | `polkit-gnome` (autostarted) |
| `hyprpolkitagent` | redundant polkit agent | `polkit-gnome` |

Likely safe (verify first):

| Removable | Why |
|-----------|-----|
| `xorg-server`, `xorg-xinit` | hypr-os is pure Wayland; Steam uses `xwayland` (separate package). Remove unless you want an X11 fallback session. |
| `wireless_tools` | legacy `iwconfig`; NetworkManager + iwd handle wireless |
| `linux` (the stock kernel) | only if your bootloader exclusively boots `linux-zen` |
| `nano` *or* `vim` | pick whichever editor you actually use |
| `yay-bin-debug`, `*-debug` | debug symbol packages; only needed if debugging that specific tool |

After any removal, sweep up orphaned dependencies:

```bash
sudo pacman -Qdtq | sudo pacman -Rns -
```

## Login screen (SDDM)

A matching SDDM greeter theme ships in `config/sddm/hypr-os/`. Install it
once with:

```bash
./scripts/install-sddm-theme.sh     # asks for sudo
```

This symlinks the theme into `/usr/share/sddm/themes/hypr-os/` and sets
`Current=hypr-os` in `/etc/sddm.conf.d/10-hypr-os.conf`. After that
`theme.sh` updates the login screen colors automatically whenever you
re-roll the wallpaper (SUPER + B) — no sudo needed at re-theme time.

## Directory Structure

```
hypr-os/
├── config/
│   ├── hypr/           # Hyprland (modular config files)
│   ├── waybar/         # Bar config + styles
│   ├── rofi/           # App launcher
│   ├── kitty/          # Terminal
│   ├── ghostty/        # Terminal
│   ├── swaync/         # Notifications
│   ├── fastfetch/      # System info
│   ├── starship/       # Shell prompt
│   ├── cava/           # Audio visualizer
│   ├── ncmpcpp/        # Music player
│   ├── ranger/         # File manager (TUI)
│   ├── htop/           # Process viewer
│   ├── hyprlock/       # Lock screen
│   └── hypridle/       # Idle daemon
├── scripts/
│   ├── wallpaper.sh    # Random wallpaper + theme update
│   └── theme.sh        # Generate and apply theme from colors
├── docs/               # Documentation
└── install.sh          # One-command setup
```

## Docs

- [Setup Guide](docs/SETUP.md) -- full installation walkthrough
- [App Reference](docs/APPS.md) -- per-app config notes
- [Keybindings](docs/KEYBINDS.md) -- all keyboard shortcuts
- [Theming](docs/THEMING.md) -- how the dynamic theme system works
- [Gaming](docs/GAMING.md) -- gaming-specific setup (Nvidia, Steam, Gamescope)
- [Custom Apps](docs/CUSTOM-APPS.md) -- FL Studio, Overwatch 2, and other app-specific setup

## License

MIT
