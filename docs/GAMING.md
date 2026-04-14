# Gaming Setup

Nvidia + Wayland gaming configuration for Arch Linux.

## Nvidia Driver Setup

Ensure you have the proprietary drivers:

```bash
sudo pacman -S nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
```

The Hyprland env config (`config/hypr/env.conf`) sets the necessary Nvidia/Wayland environment variables automatically.

## Steam

Install from pacman:

```bash
sudo pacman -S steam
```

### Launch Options

For MangoHud overlay on any game:
```
mangohud %command%
```

For Gamescope (useful for resolution scaling):
```
gamescope -W 2560 -H 1440 -r 180 -f -- %command%
```

For both:
```
gamescope -W 2560 -H 1440 -r 180 -f -- mangohud %command%
```

### Proton / Wine

Steam handles Proton automatically. For non-Steam games, use `wine` and `winetricks`:

```bash
sudo pacman -S wine winetricks
```

## Gamescope

Nested compositor optimized for gaming. Key flags:

| Flag | Description |
|------|-------------|
| `-W` | Output width |
| `-H` | Output height |
| `-r` | Refresh rate limit |
| `-f` | Fullscreen |
| `--force-grab-cursor` | Better cursor handling |
| `--adaptive-sync` | Enable VRR/G-Sync |

## MangoHud

FPS/performance overlay. Configure via GOverlay (GUI) or edit `~/.config/MangoHud/MangoHud.conf`.

Key metrics to display: FPS, frametime, CPU/GPU usage, temps, VRAM.

```bash
sudo pacman -S mangohud lib32-mangohud goverlay
```

## Window Rules

The Hyprland config includes gaming-specific window rules:

- Steam windows float by default (friends list, settings, etc.)
- Games get immediate focus and no border rounding
- Gamescope windows are treated as fullscreen

## Performance Tips

1. **Disable compositor for fullscreen games** -- Hyprland does this automatically
2. **Use Gamescope** for better VRR/adaptive sync support
3. **Set `allow_tearing = true`** in Hyprland for tear-free or tearing-allowed per game
4. **Enable VRR** in your monitor config if your monitor supports it
