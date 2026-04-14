#!/usr/bin/env bash
# Keybind Cheatsheet -- rofi popup

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"

# Use pango markup with <tt> to force monospace columns
rofi -dmenu \
    -p " Keybinds" \
    -markup-rows \
    -i \
    -no-custom \
    -scroll-method 1 \
    -theme "$HYPR_OS_DIR/config/rofi/keybinds.rasi" \
    > /dev/null 2>&1 <<'KEYS'
<tt><b>─── Apps ──────────────────────────────────────────────────</b></tt>
<tt>  Terminal           Super + Return        Open kitty          </tt>
<tt>  Browser            Super + W             Open Firefox        </tt>
<tt>  Files              Super + E             Open Thunar         </tt>
<tt>  Launcher           Super + Space         App launcher        </tt>
<tt>  Close              Super + Q             Kill window         </tt>
<tt>  Exit               Super + M             Log out             </tt>
<tt><b>─── Windows ───────────────────────────────────────────────</b></tt>
<tt>  Full Width         Super + F             Max width, keep bar </tt>
<tt>  Fullscreen         Super + Alt + F       True fullscreen     </tt>
<tt>  Float              Super + V             Toggle floating     </tt>
<tt>  Pseudo             Super + P             Pseudo-tile         </tt>
<tt>  Split              Super + J             Toggle split        </tt>
<tt><b>─── Focus / Move ──────────────────────────────────────────</b></tt>
<tt>  Focus              Super + Arrows        Move focus          </tt>
<tt>  Move               Super + Shift + Arr   Move window         </tt>
<tt>  Resize             Super + Ctrl + Arr    Resize window       </tt>
<tt><b>─── Workspaces ────────────────────────────────────────────</b></tt>
<tt>  Switch             Super + 1-0           Go to workspace     </tt>
<tt>  Move to WS         Super + Shift + 1-0   Send to workspace   </tt>
<tt>  Scratchpad         Super + S             Toggle scratchpad   </tt>
<tt>  To Scratch         Super + Shift + S     Send to scratchpad  </tt>
<tt>  Scroll WS          Super + Scroll        Cycle workspaces    </tt>
<tt><b>─── Screenshots ───────────────────────────────────────────</b></tt>
<tt>  Region             Print                 Select + annotate   </tt>
<tt>  Full Screen        Super + Print         Capture all + edit  </tt>
<tt>  Window             Super + Shift + Prt   Active window       </tt>
<tt><b>─── Session ───────────────────────────────────────────────</b></tt>
<tt>  Lock               Super + L             Lock screen         </tt>
<tt>  Reload             Super + Shift + R     Reload Hyprland     </tt>
<tt>  Restart Bar        Super + Ctrl + R      Restart Waybar      </tt>
<tt>  Wallpaper          Super + B             Random + re-theme   </tt>
<tt>  Keybinds           Super + K             This cheatsheet     </tt>
<tt><b>─── Media ─────────────────────────────────────────────────</b></tt>
<tt>  Volume             Vol Keys              Up / Down / Mute    </tt>
<tt>  Playback           Media Keys            Play / Next / Prev  </tt>
<tt><b>─── Mouse ─────────────────────────────────────────────────</b></tt>
<tt>  Move Win           Super + LMB Drag      Drag to move        </tt>
<tt>  Resize Win         Super + RMB Drag      Drag to resize      </tt>
KEYS
