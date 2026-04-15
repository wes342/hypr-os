# Setup Guide

Full walkthrough for setting up hypr-os on a fresh Arch Linux install.

## Prerequisites

- Arch Linux installed with a working user account
- Nvidia GPU with proprietary drivers installed
- Internet connection
- `git` and `base-devel` installed

## Step 1: Install Nvidia Drivers

```bash
sudo pacman -S nvidia nvidia-utils nvidia-settings lib32-nvidia-utils
```

Add kernel parameters for Wayland support. Edit `/etc/default/grub`:

```
GRUB_CMDLINE_LINUX_DEFAULT="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
```

Then regenerate grub:

```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

Enable early KMS loading. Add to `/etc/mkinitcpio.conf` MODULES:

```
MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
```

Then regenerate initramfs:

```bash
sudo mkinitcpio -P
```

Reboot after this step.

## Step 2: Install Packages

### Core Desktop

```bash
sudo pacman -S hyprland waybar hyprpaper hyprlock hypridle \
  rofi-wayland swaync nwg-dock-hyprland \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  qt5-wayland qt6-wayland
```

### Terminals

```bash
sudo pacman -S kitty ghostty
```

### File Management

```bash
sudo pacman -S thunar thunar-archive-plugin tumbler ffmpegthumbnailer ark ranger
```

### Shell Tools

```bash
sudo pacman -S starship zoxide fastfetch htop
```

### Media

```bash
sudo pacman -S ncmpcpp cava playerctl mpd
```

### Audio mixer (waybar speaker icon)

The waybar volume icon's left-click handler launches a GUI mixer.
Two options:

```bash
# Classic PulseAudio mixer (always in [extra], reliable):
sudo pacman -S pavucontrol

# OR the lighter PipeWire-native UI (from AUR):
yay -S pwvucontrol
```

Install at least one. The handler prefers `pwvucontrol` when both are
present, so you can install `pwvucontrol` later and it'll take over
without any config change.

### Theming Dependencies

```bash
sudo pacman -S imagemagick jq python
```

### Browsers & Apps

```bash
sudo pacman -S firefox discord code
```

### Fonts

```bash
sudo pacman -S ttf-iosevka-nerd ttf-jetbrains-mono-nerd ttf-font-awesome noto-fonts noto-fonts-cjk noto-fonts-emoji
```

### Gaming

```bash
sudo pacman -S steam gamescope mangohud lib32-mangohud goverlay wine winetricks
```

### AUR Packages (using yay or paru)

```bash
# Install an AUR helper first if you don't have one
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si

# AUR packages
yay -S wl-clipboard
```

## Step 3: Clone and Install Dotfiles

```bash
git clone https://github.com/<your-user>/hypr-os.git ~/dev/hypr-os
cd ~/dev/hypr-os
chmod +x install.sh
./install.sh
```

The install script will:
1. Back up existing configs to `~/.config-backup-<date>/`
2. Symlink all configs from this repo to `~/.config/`
3. Create `~/Pictures/Wallpaper/` if it doesn't exist
4. Set an initial wallpaper and generate the theme

## Step 4: Reboot

```bash
reboot
```

Select Hyprland from your display manager, or if using TTY login:

```bash
Hyprland
```

## Step 5: Post-Install

1. Add wallpapers to `~/Pictures/Wallpaper/`
2. Press `SUPER + B` to pick a random wallpaper and apply theming
3. Configure Firefox, Discord, Steam etc. to your preference

## Cleanup: remove duplicates installed by archinstall's Hyprland profile

archinstall's Hyprland preset installs a handful of apps that overlap
with hypr-os's choices. After hypr-os is up and running you can drop
them:

```bash
sudo pacman -Rns wofi dolphin dunst polkit-kde-agent hyprpolkitagent
```

What each one is and what hypr-os uses instead:

- `wofi` -> replaced by `rofi-wayland` (launcher, power menu, wallpaper
  browser, keybinds cheatsheet all use rofi)
- `dolphin` -> replaced by `thunar`
- `dunst` -> replaced by `swaync`
- `polkit-kde-agent` and `hyprpolkitagent` -> redundant; hypr-os
  autostarts `polkit-gnome` from `config/hypr/autostart.conf`. Pick
  one polkit agent and remove the others.

Other things archinstall or its presets may have left around that you
likely don't need on a Wayland-only Hyprland setup:

- `xorg-server`, `xorg-xinit` -- pure Wayland; Steam, Wine etc. pull
  in `xwayland` (a separate, much smaller package). Only keep these
  if you want an X11 fallback session.
- `wireless_tools` -- legacy `iwconfig`. NetworkManager + iwd cover
  wireless on a modern Arch install.
- The stock `linux` kernel -- if your bootloader only boots
  `linux-zen`, the stock kernel + headers can be removed. Confirm
  with `cat /etc/limine.conf` (or `/boot/loader/entries/*.conf` for
  systemd-boot) before removing.
- `nano` *or* `vim` -- whichever you don't actually use.
- `*-debug` packages (`yay-bin-debug`, `eww-git-debug`, ...) --
  symbols only useful if you're attaching gdb to that specific tool.

After removing anything, mop up orphaned dependencies:

```bash
sudo pacman -Qdtq | sudo pacman -Rns -
```

## Updating

Pull the latest changes and re-run the install:

```bash
cd ~/dev/hypr-os
git pull
./install.sh
```

## Troubleshooting

### Screen tearing / flickering on Nvidia

Make sure the environment variables in `config/hypr/env.conf` are set correctly. The config includes Nvidia-specific Wayland variables by default.

### Waybar not showing

Check if waybar is running: `pgrep waybar`. Try restarting it: `killall waybar && waybar &`.

### Rofi not launching

Make sure you have `rofi-wayland` (not `rofi`) installed.

### No sound in games

```bash
sudo pacman -S pipewire pipewire-pulse pipewire-alsa wireplumber
systemctl --user enable --now pipewire pipewire-pulse wireplumber
```
