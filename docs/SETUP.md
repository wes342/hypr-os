# Setup Guide

Full walkthrough for setting up hypr-os on a fresh Arch Linux install. The installer supports either Hyprland or Sway/SwayFX.

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

The recommended path is to let the repo select the right package set:

```bash
# Hyprland
./install.sh --desktop hyprland --with-packages

# Sway/SwayFX
./install.sh --desktop sway --with-packages
```

### Core Desktop

Hyprland:

```bash
sudo pacman -S hyprland waybar hyprpaper hyprlock hypridle \
  rofi-wayland mako \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  qt5-wayland qt6-wayland
```

Sway/SwayFX:

```bash
sudo pacman -S swaybg swayidle waybar rofi-wayland mako \
  xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
  qt5-wayland qt6-wayland
yay -S swayfx swaylock-effects
```

### Terminals

```bash
sudo pacman -S kitty
```

### File Management

```bash
sudo pacman -S thunar thunar-archive-plugin tumbler ffmpegthumbnailer ark
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

1. Add wallpapers to `~/Pictures/Wallpaper/` (subfolders work too)
2. Press `SUPER + B` to pick a random wallpaper and apply theming
3. Configure Firefox, Discord, Steam etc. to your preference

### Snapper snapshots (btrfs)

If your system uses btrfs with snapper (the archinstall btrfs profile
sets this up), enable user-level access so the snapshot manager works
without sudo:

```bash
sudo sed -i 's/ALLOW_USERS=""/ALLOW_USERS="YOUR_USERNAME"/' \
    /etc/snapper/configs/root /etc/snapper/configs/home
```

Then press `SUPER + ALT + S` to open the snapshot manager. It supports:
- **Create** snapshots (root or home) with optional descriptions
- **List** all snapshots with date, type, and description
- **Delete** snapshots (with confirmation)
- **Restore** to a previous snapshot (with double confirmation)
- **Compare** two snapshots (shows file diff)

Recommended: create a snapshot before major system changes
(kernel upgrades, big package installs, config experiments).

## Cleanup: remove duplicates installed by archinstall's Hyprland profile

archinstall's Hyprland preset installs a handful of apps that overlap
with hypr-os's choices. After hypr-os is up and running you can drop
them:

```bash
sudo pacman -Rns wofi dolphin dunst polkit-kde-agent hyprpolkitagent
```

What each one is and what hypr-os uses instead:

- `wofi` -> replaced by GTK4 app launcher and `rofi-wayland` (menus)
- `dolphin` -> replaced by `thunar`
- `dunst` -> replaced by `mako`
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

## Extra Setup

### Internal storage drive (NTFS)

If you have a secondary internal drive (SATA/NVMe), mount it permanently
via fstab. Find the drive's UUID:

```bash
lsblk -f
```

Create the mount point and add to fstab:

```bash
sudo mkdir -p /mnt/Storage
echo 'UUID=YOUR_DRIVE_UUID  /mnt/Storage  ntfs3  rw,uid=1000,gid=1000,nofail  0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/Storage
```

### TrueNAS / NFS network share

To mount a TrueNAS (or any NFS) share, install the NFS tools and add
an fstab entry:

```bash
sudo pacman -S --needed nfs-utils smbclient
```

Find available NFS exports on your server:

```bash
showmount -e YOUR_SERVER_IP
```

Create the mount point and add to fstab:

```bash
sudo mkdir -p /mnt/TrueNAS
echo 'YOUR_SERVER_IP:/mnt/path/to/share  /mnt/TrueNAS  nfs  rw,soft,timeo=10,nofail,_netdev  0 0' | sudo tee -a /etc/fstab
sudo systemctl daemon-reload
sudo mount /mnt/TrueNAS
```

Key mount options:
- `nofail` -- system boots normally if the drive/server is unavailable
- `_netdev` -- waits for network before attempting NFS mount
- `soft,timeo=10` -- times out gracefully if server is unreachable

### Thunar sidebar bookmarks

Add mounted drives and network shares to Thunar's sidebar by editing
`~/.config/gtk-3.0/bookmarks`:

```
file:///mnt/Storage Storage
file:///mnt/TrueNAS TrueNAS
```

These also appear in GTK file picker dialogs.

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
