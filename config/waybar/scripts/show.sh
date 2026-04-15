#!/usr/bin/env bash
# Emits one-shot JSON for a waybar custom module.
# Reads from the metrics daemon's output; falls back to a placeholder.

kind="${1:?usage: show.sh <cpu|gpu|ram|storage>}"
file="/tmp/hypr-os-metrics/${kind}.json"

if [[ -r "$file" ]]; then
    cat "$file"
else
    case "$kind" in
        cpu)     echo '{"text":" --","tooltip":"loading…","class":"loading"}' ;;
        gpu)     echo '{"text":" --","tooltip":"loading…","class":"loading"}' ;;
        ram)     echo '{"text":" --","tooltip":"loading…","class":"loading"}' ;;
        storage) echo '{"text":"󰋊 --","tooltip":"loading…","class":"loading"}' ;;
        *)       echo '{"text":"--","tooltip":"unknown","class":"loading"}' ;;
    esac
fi
