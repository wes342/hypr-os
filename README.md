# hypr-os

A clean, gaming-focused Hyprland desktop environment for Arch Linux with Nvidia + Wayland. Features wallpaper-driven dynamic theming that keeps all applications visually consistent.

## Features

- **Modular Hyprland config** -- split into logical files for easy customization
- **Dynamic theming** -- colors extracted from your wallpaper and applied across all apps
- **GTK4 app launcher** -- transparent overlay with blurred wallpaper, sidebar quick-launch icons, and instant open via D-Bus pre-warming (~25ms)
- **Wallpaper manager** -- GTK4 app for browsing local and Wallhaven wallpapers with auto-rotate timer
- **Gaming ready** -- Nvidia/Wayland optimized, Steam, Gamescope, MangoHud preconfigured
- **One-command install** -- clone and run `install.sh` on a fresh Arch install
- **Multi-monitor support** -- designed for 1440p primary with dedicated sensor panel on secondary display
- **Theme persistence** -- wallpaper and theme survive reboots, no random re-roll on login
- **Snapshot manager** -- btrfs/snapper GUI for create, restore, delete, compare
- **Auto-rotate wallpaper** -- configurable timer (1min--24hr) with systemd, manageable from wallpaper app

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
3. Installs systemd user units for wallpaper auto-rotate
4. Installs launcher and wallpaper manager to `~/.local/bin/`
5. Creates `~/Pictures/Wallpaper/` and seeds it with the included default
   wallpaper if empty
6. Runs `theme.sh` once to generate the initial color palette
7. Appends `HYPR_OS_DIR`, `starship`, and `zoxide` lines to your shell rc

After it finishes, log out and back into Hyprland.

## Applications

| Category | Apps |
|----------|------|
| **WM / Desktop** | hyprland, waybar, hyprpaper, hyprlock, hypridle, eww, nwg-dock-hyprland |
| **Launcher** | GTK4 app launcher (scripts/launcher-app.py) |
| **Wallpaper** | GTK4 wallpaper manager with Wallhaven integration (scripts/wallpaper-app.py) |
| **Terminals** | kitty, ghostty, alacritty |
| **File Manager** | thunar, ranger, tumbler, ffmpegthumbnailer, thunar-archive-plugin, ark |
| **Notifications** | swaync |
| **Shell** | starship, zoxide, fastfetch, fzf, bat, ble.sh |
| **System Monitors** | btop, htop, nvtop |
| **Media / Audio** | ncmpcpp, mpd, cava, playerctl, mpv, pavucontrol |
| **Screenshots** | grim, slurp, satty, hyprshot |
| **Eye Candy** | cmatrix, cbonsai, tty-clock |
| **Gaming** | steam, gamescope, mangohud, goverlay, wine, winetricks |
| **Other** | firefox, discord, code (VS Code), qalculate-gtk, imv, zathura |

### One-line install (everything above)

`install.sh --with-packages` already runs this for you. If you want to install
the full app set by hand:

```bash
# Official repos
sudo pacman -S --needed git base-devel hyprland waybar hyprpaper hyprlock hypridle \
  rofi-wayland swaync kitty alacritty btop htop lm_sensors nvtop \
  thunar thunar-archive-plugin tumbler ffmpegthumbnailer ark ranger imv \
  zathura zathura-pdf-mupdf imagemagick jq python curl bc socat \
  wl-clipboard cliphist grim slurp satty wf-recorder hyprpicker \
  starship zoxide fastfetch fzf bat chafa cmatrix \
  ncmpcpp mpd cava playerctl mpv \
  ttf-iosevka-nerd ttf-jetbrains-mono-nerd ttf-font-awesome \
  noto-fonts noto-fonts-cjk noto-fonts-emoji \
  papirus-icon-theme adwaita-icon-theme \
  pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol \
  qt5-wayland qt6-wayland \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk xdg-utils \
  polkit-gnome network-manager-applet blueman gvfs udisks2 \
  firefox discord code qalculate-gtk \
  steam gamescope mangohud lib32-mangohud goverlay wine winetricks

# AUR (requires yay/paru — enable [multilib] in /etc/pacman.conf first for gaming)
yay -S --needed eww ghostty hyprshot nwg-dock-hyprland blesh-git \
  spotify-launcher cbonsai tty-clock
```

## Keybindings

See [docs/KEYBINDS.md](docs/KEYBINDS.md) for the full list. Highlights:

| Key | Action |
|-----|--------|
| `SUPER + Return` | Terminal (kitty) |
| `SUPER + Space` | App launcher |
| `SUPER + Q` | Close window |
| `SUPER + F` | Full-width window |
| `SUPER + ALT + F` | Fullscreen |
| `SUPER + B` | Random wallpaper + re-theme |
| `SUPER + V` | Toggle floating |
| `SUPER + L` | Lock screen |
| `SUPER + K` | Keybind cheatsheet |
| `SUPER + ALT + S` | Snapper snapshot manager |
| `SUPER + ALT + B` | Wallpaper browser |
| `SUPER + ALT + E` | Eye candy effects |
| `SUPER + 1-0` | Switch workspace |

## Theming

The theme system extracts dominant colors from your current wallpaper using `imagemagick` and generates config snippets for each application. Press `SUPER + B` to pick a random wallpaper and automatically update the theme everywhere.

Themed applications: Hyprland borders, waybar, kitty, ghostty, alacritty, rofi, swaync, cava, btop, eww sensor panel, SDDM login screen, and the GTK4 launcher/wallpaper apps.

Wallpapers are read from `~/Pictures/Wallpaper/`. The wallpaper manager (`SUPER + ALT + B`) also supports browsing and downloading from Wallhaven.

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
| `wofi` | duplicate launcher | GTK4 launcher |
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
re-roll the wallpaper (SUPER + B) -- no sudo needed at re-theme time.

## Directory Structure

```
hypr-os/
├── config/
│   ├── hypr/           # Hyprland (modular config files)
│   ├── waybar/         # Bar config + styles
│   ├── rofi/           # Rofi themes (dmenu popups)
│   ├── eww/            # Sensor panel + waybar dropdowns
│   ├── kitty/          # Terminal
│   ├── ghostty/        # Terminal
│   ├── alacritty/      # Terminal
│   ├── swaync/         # Notifications
│   ├── fastfetch/      # System info
│   ├── starship/       # Shell prompt
│   ├── cava/           # Audio visualizer
│   ├── ncmpcpp/        # Music player
│   ├── mpv/            # Video player
│   ├── bash/           # Shell env (ble.sh, aliases, starship)
│   ├── hyprlock/       # Lock screen
│   ├── hypridle/       # Idle daemon
│   ├── systemd/        # Wallpaper auto-rotate timer
│   ├── gtk-3.0/        # GTK3 settings
│   ├── gtk-4.0/        # GTK4 settings
│   ├── sddm/          # Login screen theme
│   └── wallpapers/     # Default wallpaper (seed)
├── scripts/
│   ├── launcher-app.py # GTK4 app launcher
│   ├── launcher.sh     # Launcher toggle (D-Bus activation)
│   ├── wallpaper-app.py # GTK4 wallpaper manager
│   ├── wallpaper.sh    # Random wallpaper + theme update
│   ├── wallhaven.py    # Wallhaven API client
│   ├── theme.sh        # Generate and apply theme from colors
│   ├── launch.sh       # App launcher helper
│   ├── keybinds.sh     # Keybind cheatsheet
│   └── install-sddm-theme.sh
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
