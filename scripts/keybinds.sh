#!/usr/bin/env bash
# Keybind Cheatsheet -- rofi popup with fuzzy search

HYPR_OS_DIR="${HYPR_OS_DIR:-$HOME/dev/hypr-os}"

rofi -dmenu \
    -p "Keybinds" \
    -markup-rows \
    -i \
    -matching fuzzy \
    -scroll-method 1 \
    -theme "$HYPR_OS_DIR/config/rofi/keybinds.rasi" \
    > /dev/null 2>&1 <<'KEYS'
<tt><b>─── Apps ──────────────────────────────────────────────────────────────────────</b></tt>
<tt>  Terminal             Super + Return              Open kitty                      </tt>
<tt>  Browser              Super + W                   Open Firefox                    </tt>
<tt>  Files                Super + E                   Open Thunar file manager        </tt>
<tt>  Launcher             Super + Space               App launcher (rofi drun)        </tt>
<tt>  Close                Super + Q                   Close active window             </tt>
<tt>  Force Close          Super + Shift + Q           Close fullscreen window too     </tt>
<tt>  Exit                 Super + M                   Log out of Hyprland             </tt>
<tt><b>─── Windows ───────────────────────────────────────────────────────────────────</b></tt>
<tt>  Full Width           Super + F                   Maximize, keep bar visible      </tt>
<tt>  Fullscreen           Super + Alt + F             True fullscreen                 </tt>
<tt>  Float                Super + V                   Toggle floating                 </tt>
<tt>  Pseudo               Super + P                   Pseudo-tile mode                </tt>
<tt>  Split                Super + J                   Toggle split direction          </tt>
<tt><b>─── Focus / Move ──────────────────────────────────────────────────────────────</b></tt>
<tt>  Focus                Super + Arrows              Move focus between windows      </tt>
<tt>  Move                 Super + Shift + Arrows      Move window                     </tt>
<tt>  Resize               Super + Ctrl + Arrows       Resize active window            </tt>
<tt><b>─── Workspaces ────────────────────────────────────────────────────────────────</b></tt>
<tt>  Switch               Super + 1-0                 Go to workspace                 </tt>
<tt>  Move to WS           Super + Shift + 1-0         Send window to workspace        </tt>
<tt>  Scratchpad           Super + S                   Toggle scratchpad               </tt>
<tt>  To Scratch           Super + Shift + S           Send window to scratchpad       </tt>
<tt>  Scroll WS            Super + Scroll              Cycle workspaces                </tt>
<tt><b>─── Screenshots ───────────────────────────────────────────────────────────────</b></tt>
<tt>  Region               Print                       Select region + annotate        </tt>
<tt>  Full Screen          Super + Print               Capture all monitors + edit     </tt>
<tt>  Window               Super + Shift + Print       Capture active window           </tt>
<tt><b>─── Session ───────────────────────────────────────────────────────────────────</b></tt>
<tt>  Lock                 Super + L                   Lock screen (hyprlock)          </tt>
<tt>  Reload               Super + Shift + R           Reload Hyprland config          </tt>
<tt>  Restart Bar          Super + Ctrl + R            Restart Waybar                  </tt>
<tt>  Wallpaper            Super + B                   Random wallpaper + re-theme     </tt>
<tt>  Wallpaper Browse     Super + Alt + B             Grid of all wallpapers          </tt>
<tt>  Keybinds             Super + K                   This cheatsheet                 </tt>
<tt><b>─── Media ─────────────────────────────────────────────────────────────────────</b></tt>
<tt>  Volume               Vol Keys                    Up / Down / Mute                </tt>
<tt>  Playback             Media Keys                  Play / Next / Prev              </tt>
<tt><b>─── Mouse ─────────────────────────────────────────────────────────────────────</b></tt>
<tt>  Move Win             Super + LMB Drag            Drag to move                    </tt>
<tt>  Resize Win           Super + RMB Drag            Drag to resize                  </tt>
KEYS
