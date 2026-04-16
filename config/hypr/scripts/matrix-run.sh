#!/usr/bin/env bash
# Wrapper around cmatrix that restarts the rain on terminal resize.
# cmatrix 2.0 ships a SIGWINCH handler but it doesn't fully redraw
# when kitty/ghostty reshape the grid (e.g. docking the window),
# so the columns end up clipped or the bottom half is blank. We kill
# and relaunch on every resize instead -- imperceptible and reliable.

resized=0

cleanup() {
    kill "${CPID-}" 2>/dev/null
    tput cnorm clear 2>/dev/null
    exit 0
}
trap cleanup INT TERM HUP

on_winch() {
    resized=1
    kill "${CPID-}" 2>/dev/null
}
trap on_winch WINCH

while true; do
    resized=0
    cmatrix -ab -C green -u 4 &
    CPID=$!
    wait "$CPID" 2>/dev/null

    # Kill from the WINCH handler -> restart.
    # Clean exit (user pressed q) -> break.
    (( resized )) || break
done

cleanup
