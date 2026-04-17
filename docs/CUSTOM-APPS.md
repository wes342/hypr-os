# Custom App Setup

Per-app installation and configuration for apps that need extra steps
beyond `pacman -S`. Updated as we discover new setups.

---

## FL Studio (via Bottles)

FL Studio is a Windows DAW. We run it inside **Bottles** (a Wine
management GUI) from Flatpak.

### Install Bottles

```bash
# If you have two flathub remotes (system + user), remove the empty one:
#   sudo flatpak remote-delete --system flathub
# Then:
flatpak install flathub com.usebottles.bottles
```

### Create the bottle

1. Launch: `flatpak run com.usebottles.bottles`
2. "Create a new bottle" → Name: `FL Studio`, Environment: **Application**
3. Bottle settings → **Dependencies** → install:
   - `allfonts` (fixes missing/broken fonts)
   - `dotnet48`
   - `vcredist2019`

### Fix menus, popups, and slider interaction

FL Studio's popup menus and sliders break on Wayland because Wine's
multi-window handling doesn't receive input correctly.

**Fix:** Bottle settings → **Display** → enable **Virtual Desktop** →
set resolution to **1920x1080** (or your monitor resolution).

This wraps all Wine windows in a single container and fixes:
- Popup menus not receiving clicks
- Dropdown menus disappearing
- Slider dragging not registering
- Dialog boxes not responding

### Install FL Studio

1. Download the Windows installer from
   [image-line.com](https://www.image-line.com/fl-studio-download/)
2. In your bottle → "Run Executable" → select the `.exe`
3. Follow the install wizard

### Activate / unlock

The Wine browser can't redirect back to FL Studio, so browser-based
unlock won't work. Use offline activation instead:

1. Open FL Studio inside Bottles → **Help → About**
2. Copy the **machine code** shown
3. In Firefox (real browser), go to image-line.com → My Account →
   FL Studio → "Unlock using machine code"
4. Paste the code, download the resulting `.reg` file
5. In Bottles → "Run Executable" → select the `.reg` file (imports
   into Wine's registry)
6. Restart FL Studio — should show as registered

If your account page offers a "Download Registration File / Regkey"
link instead, download that `.reg` and import the same way.

### Installing Windows VST plugins

1. Download your VST `.exe` or `.msi` installer (Windows version)
2. In Bottles → FL Studio bottle → "Run Executable" → select installer
3. Follow the VST install wizard — it installs into the Wine prefix's
   `C:\Program Files\Common Files\VST3\` (or wherever it defaults)
4. In FL Studio → **Options → File Settings** → set "VST plugins
   extra search path" to the VST install directory
5. FL Studio scans and finds them

### Audio tips

- Bottle settings → **Runner**: try `wine-ge` or `caffe` (often more
  stable than stock Wine)
- FL Studio → **Options → Audio** → select "FL Studio ASIO"
- If audio crackles, increase buffer size in ASIO settings
- Bottles audio defaults to PulseAudio, which works with PipeWire

---

## Overwatch 2 / Battle.net (via Steam + Proton)

Overwatch 2 runs through Steam with Proton. Common issues below.

### Mouse stutter / raw input fix

Wayland doesn't expose raw mouse input to XWayland games by default,
causing micro-stutters and floaty aim.

**Fix: use Gamescope with `--force-grab-cursor`**

Set Overwatch 2's Steam launch options to:

```
gamescope -W 2560 -H 1440 -r 180 -f --force-grab-cursor -- mangohud %command%
```

- `--force-grab-cursor` locks the cursor inside Gamescope's window,
  eliminating jitter from Wayland's pointer protocol.
- `-r 180` caps at your monitor's refresh (adjust to your hz).
- `mangohud` shows the FPS overlay (remove if you don't want it).

If not using Gamescope, try these env overrides instead:

```
env SDL_VIDEODRIVER=x11 __GL_SYNC_TO_VBLANK=0 %command%
```

**In-game settings that help:**
- Video → **Reduce Buffering: ON**
- Video → **Limit FPS: match your monitor refresh or Off**
- Video → **NVIDIA Reflex: Enabled + Boost** (if available)

### Battle.net won't launch / crashes

If Battle.net fails under default Proton:

1. Steam → Overwatch 2 → Properties → Compatibility
2. Force a specific Proton version: try **Proton Experimental** or
   **GE-Proton** (better game compatibility than stock Proton)
3. Install GE-Proton via ProtonUp-Qt:
   ```bash
   flatpak install flathub net.davidotek.pupgui2
   ```
   Launch ProtonUp-Qt, download latest GE-Proton, select it in Steam.

### Competitive-game tips

- **Close heavy overlays** — Discord overlay and browser tabs add
  input latency.
- **Monitor GPU temps** via the waybar GPU dropdown — thermal
  throttling causes frame drops.
- **Enable VRR / G-Sync** if your monitor supports it:
  ```
  # config/hypr/monitors.conf
  monitor = DP-3, 2560x1440@180, 0x0, 1, vrr, 1
  ```

---

*Add new app entries below as you discover them.*
