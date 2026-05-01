# Theming System

hypr-os uses a wallpaper-driven dynamic theming system. Colors are extracted from your current wallpaper and applied across all configured applications for a unified look.

## How It Works

1. **Wallpaper selection** -- `SUPER + B` picks a random image from `~/Pictures/Wallpaper/`
2. **Color extraction** -- `imagemagick` extracts a 16-color palette from the wallpaper
3. **Theme generation** -- `scripts/theme.sh` maps the palette to named color roles (background, foreground, accent, etc.)
4. **Config updates** -- theme snippets are written for each app (kitty, rofi, waybar, etc.)
5. **Live reload** -- apps that support it are reloaded automatically (Hyprland/Sway, waybar, mako)

## Color Roles

The theme system generates the following named colors:

| Role | Usage |
|------|-------|
| `bg` | Primary background |
| `bg_dim` | Slightly lighter background (panels, bars) |
| `bg_highlight` | Selection/hover background |
| `fg` | Primary text |
| `fg_dim` | Secondary/muted text |
| `accent` | Active borders, highlights |
| `accent_dim` | Inactive borders |
| `color0-15` | Terminal 16-color palette |

## Generated Files

The theme script writes the following files:

| File | App |
|------|-----|
| `config/hypr/theme.conf` | Hyprland border colors |
| `config/sway/theme.conf` | Sway/SwayFX client and effect colors |
| `config/swaylock/config` | Sway lock screen colors |
| `config/kitty/current-theme.conf` | Kitty terminal colors |
| `config/waybar/colors.css` | Waybar CSS variables |
| `config/rofi/colors.rasi` | Rofi color variables |
| `config/mako/config` | Notification colors |
| `config/cava/config` | Cava visualizer colors |

## Manual Theming

To apply a specific wallpaper:

```bash
./scripts/wallpaper.sh /path/to/wallpaper.jpg
```

To regenerate the theme from the current wallpaper without changing it:

```bash
./scripts/theme.sh
```

## Adding Custom Themes

You can override the auto-generated theme by editing the generated files directly. They won't be overwritten until the next `SUPER + B` press or `wallpaper.sh` run.

## Dependencies

- `imagemagick` -- color extraction (`convert` command)
- `jq` -- JSON manipulation for config files
