# hypr-os

A clean, gaming-focused Hyprland desktop environment for Arch Linux with Nvidia + Wayland. Features wallpaper-driven dynamic theming that keeps all applications visually consistent.

## Features

- **Modular Hyprland config** -- split into logical files for easy customization
- **Dynamic theming** -- colors extracted from your wallpaper and applied across all apps
- **Gaming ready** -- Nvidia/Wayland optimized, Steam, Gamescope, MangoHud preconfigured
- **One-command install** -- clone and run `install.sh` on a fresh Arch install
- **Multi-monitor support** -- designed for 1440p primary with easy second monitor expansion

## Quick Start

```bash
git clone https://github.com/<your-user>/hypr-os.git ~/dev/hypr-os
cd ~/dev/hypr-os
chmod +x install.sh
./install.sh
```

## Applications

| Category | Apps |
|----------|------|
| **WM / Desktop** | hyprland, waybar, hyprpaper, hyprlock, hypridle, nwg-dock-hyprland |
| **Launcher** | rofi |
| **Terminals** | kitty, ghostty |
| **File Manager** | thunar, ranger, tumbler, ffmpegthumbnailer, thunar-archive-plugin, ark |
| **Notifications** | swaync |
| **Shell** | starship, zoxide, fastfetch |
| **Media / Audio** | ncmpcpp, cava, playerctl |
| **Gaming** | steam, gamescope, mangohud, goverlay, wine, winetricks |
| **Other** | firefox, discord, code (VS Code), htop |

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

## License

MIT
