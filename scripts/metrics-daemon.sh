#!/usr/bin/env bash
# ┌──────────────────────────────────────────┐
# │  System Metrics Daemon                   │
# │  Writes JSON to /tmp/hypr-os-metrics/    │
# │  Used by waybar custom modules           │
# │  (text + rich pango tooltip + class)     │
# └──────────────────────────────────────────┘

set -uo pipefail

OUT="/tmp/hypr-os-metrics"
STATE="$OUT/state"
HIST_DIR="$OUT/history"
INTERVAL="${INTERVAL:-2}"
HIST_LEN=40
mkdir -p "$OUT" "$STATE" "$HIST_DIR"

# Pango status palette (kept fixed so they remain readable across themes)
COLOR_OK="#7daf5a"
COLOR_WARM="#e0a955"
COLOR_CRIT="#e06c75"
COLOR_DIM="#7a8390"
COLOR_RULE="#3a4350"
COLOR_BAR="#5fa8d3"

# ── Discover CPU temperature source (coretemp Package id 0) ──
CPU_TEMP_FILE=""
for h in /sys/class/hwmon/hwmon*; do
    [[ -r "$h/name" && "$(<"$h/name")" == "coretemp" ]] || continue
    for label in "$h"/temp*_label; do
        [[ -r "$label" ]] || continue
        if grep -q '^Package' "$label"; then
            CPU_TEMP_FILE="${label/_label/_input}"
            break 2
        fi
    done
done

CPU_MODEL=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo \
    | sed 's/(R)//g; s/(TM)//g; s/  */ /g; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

# ── helpers ─────────────────────────────────
write_atomic() {
    local file="$1"; shift
    local tmp="${file}.tmp.$$"
    "$@" > "$tmp" && mv "$tmp" "$file"
}

push_hist() {
    local name="$1" value="$2"
    local f="$HIST_DIR/$name.csv"
    local existing=""
    [[ -r "$f" ]] && existing=$(<"$f")
    local combined
    if [[ -z "$existing" ]]; then
        combined="$value"
    else
        combined="$existing,$value"
    fi
    awk -F',' -v n="$HIST_LEN" 'BEGIN{ORS=""} {
        s = NF - n + 1; if (s < 1) s = 1
        for (i=s; i<=NF; i++) printf "%s%s", (i==s?"":","), $i
    }' <<< "$combined" > "$f"
}

read_hist() {
    local f="$HIST_DIR/$1.csv"
    [[ -r "$f" ]] && cat "$f" || true
}

# Sparkline (▁▂▃▄▅▆▇█) from CSV of 0-100 values
sparkline() {
    local csv="$1"
    [[ -z "$csv" ]] && { printf '%s' "—"; return; }
    local -a chars=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
    local out="" v idx
    local IFS=','
    for v in $csv; do
        [[ "$v" =~ ^-?[0-9]+$ ]] || v=0
        (( v < 0 )) && v=0
        (( v > 100 )) && v=100
        idx=$(( v * 7 / 100 ))
        out+="${chars[$idx]}"
    done
    printf '%s' "$out"
}

# Horizontal bar (█...░...) for a percentage value
hbar() {
    local pct="$1" width="${2:-14}"
    [[ "$pct" =~ ^-?[0-9]+$ ]] || pct=0
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    local fill=$(( pct * width / 100 ))
    local empty=$(( width - fill ))
    local out=""
    while (( fill-- > 0 )); do out+="█"; done
    while (( empty-- > 0 )); do out+="░"; done
    printf '%s' "$out"
}

status_chip() {
    case "$1" in
        ok)          printf '<span foreground="%s"><b> OK </b></span>' "$COLOR_OK" ;;
        warm)        printf '<span foreground="%s"><b> WARM </b></span>' "$COLOR_WARM" ;;
        critical)    printf '<span foreground="%s"><b> CRIT </b></span>' "$COLOR_CRIT" ;;
        unavailable) printf '<span foreground="%s"><b> N/A </b></span>' "$COLOR_DIM" ;;
        *)           printf '<span foreground="%s"><b> -- </b></span>' "$COLOR_DIM" ;;
    esac
}

bar_color_for() {
    case "$1" in
        ok)       printf '%s' "$COLOR_OK" ;;
        warm)     printf '%s' "$COLOR_WARM" ;;
        critical) printf '%s' "$COLOR_CRIT" ;;
        *)        printf '%s' "$COLOR_BAR" ;;
    esac
}

rule() {
    printf '<span foreground="%s">────────────────────────────────────</span>' "$COLOR_RULE"
}

emit_module() {
    local kind="$1" text="$2" tooltip="$3" cls="$4"
    write_atomic "$OUT/${kind}.json" jq -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg cls "$cls" \
        '{text:$text,tooltip:$tooltip,class:$cls,alt:$cls}'
}

# ────────────────────────────────────────────
# CPU
# ────────────────────────────────────────────
collect_cpu() {
    local prev="$STATE/cpu.prev"
    local agg_total=0 agg_idle=0
    local cur_cores=""

    while read -r tag a b c d e f g h _; do
        case "$tag" in
            cpu)
                agg_total=$((a+b+c+d+e+f+g+h))
                agg_idle=$((d+e))
                ;;
            cpu[0-9]*)
                cur_cores+="$((a+b+c+d+e+f+g+h)):$((d+e)) "
                ;;
            *) break ;;
        esac
    done < /proc/stat

    local prev_total=0 prev_idle=0 prev_cores=""
    if [[ -r "$prev" ]]; then
        IFS='|' read -r prev_total prev_idle prev_cores < "$prev"
    fi

    local dt=$((agg_total - prev_total))
    local di=$((agg_idle - prev_idle))
    local usage=0
    (( dt > 0 )) && usage=$(( (100*(dt-di))/dt ))
    (( usage < 0 )) && usage=0
    (( usage > 100 )) && usage=100

    # Per-core %
    local cores_csv="" idx=0
    for pair in $cur_cores; do
        local ct="${pair%:*}" ci="${pair#*:}"
        local pp
        pp=$(echo "$prev_cores" | awk -v i=$((idx+1)) '{print $i}')
        local cpct=0
        if [[ -n "$pp" && "$pp" == *:* ]]; then
            local pt="${pp%:*}" pi="${pp#*:}"
            local cdt=$((ct-pt)) cdi=$((ci-pi))
            (( cdt > 0 )) && cpct=$(( (100*(cdt-cdi))/cdt ))
            (( cpct < 0 )) && cpct=0
            (( cpct > 100 )) && cpct=100
        fi
        cores_csv+="${cpct},"
        idx=$((idx+1))
    done
    cores_csv="${cores_csv%,}"

    printf '%s|%s|%s\n' "$agg_total" "$agg_idle" "$cur_cores" > "$prev"

    local temp=0
    [[ -n "$CPU_TEMP_FILE" && -r "$CPU_TEMP_FILE" ]] && temp=$(( $(<"$CPU_TEMP_FILE") / 1000 ))

    local freq
    freq=$(awk '/cpu MHz/{s+=$4; n++} END{if(n) printf "%d", s/n; else print 0}' /proc/cpuinfo)

    local nproc_count; nproc_count=$(nproc)

    local status="ok"
    if   (( temp >= 85 )); then status="critical"
    elif (( temp >= 75 )); then status="warm"
    fi

    push_hist "cpu" "$usage"
    local hist_csv; hist_csv=$(read_hist "cpu")

    local bar_color; bar_color=$(bar_color_for "$status")
    local usage_bar; usage_bar=$(hbar "$usage" 16)
    local core_spark; core_spark=$(sparkline "$cores_csv")
    local hist_spark; hist_spark=$(sparkline "$hist_csv")

    # Pango tooltip (use real newlines; jq encodes them as \n)
    local tt=""
    tt+=" <b>${CPU_MODEL}</b>   $(status_chip "$status")"$'\n'
    tt+=" $(rule)"$'\n'
    tt+=$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Usage</span>      <b>%3d%%</b>   <tt><span foreground=\"%s\">%s</span></tt>" \
        "$COLOR_DIM" "$usage" "$bar_color" "$usage_bar")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Temp</span>       <b>%3d°C</b>" "$COLOR_DIM" "$temp")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Frequency</span>  <b>%d MHz</b>" "$COLOR_DIM" "$freq")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Cores</span>      <b>%d</b>" "$COLOR_DIM" "$nproc_count")$'\n'
    tt+=$'\n'
    tt+=" <b>Per-core load</b>"$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${core_spark}</span></tt>"$'\n'
    tt+=$'\n'
    tt+=" <b>Usage history</b>"$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${hist_spark}</span></tt>"

    local wb_text=" ${temp}°"
    emit_module "cpu" "$wb_text" "$tt" "$status"
}

# ────────────────────────────────────────────
# GPU (NVIDIA)
# ────────────────────────────────────────────
collect_gpu() {
    local data
    data=$(nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,clocks.current.graphics,clocks.current.memory,fan.speed \
        --format=csv,noheader,nounits 2>/dev/null | head -1)

    if [[ -z "$data" ]]; then
        emit_module "gpu" " n/a" "<b>GPU not available</b>" "unavailable"
        return
    fi

    IFS=',' read -r name temp util util_mem mem_used mem_total power clk_gfx clk_mem fan <<< "$data"
    name="$(echo "$name" | sed 's/^ *//; s/ *$//; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
    local n
    for n in temp util util_mem mem_used mem_total clk_gfx clk_mem fan; do
        local v="${!n}"; v="$(echo "$v" | sed 's/^ *//; s/ *$//')"
        [[ "$v" =~ ^[0-9]+$ ]] || v=0
        printf -v "$n" '%s' "$v"
    done
    local power_int; power_int="$(echo "$power" | sed 's/^ *//; s/ *$//; s/\..*//')"
    [[ "$power_int" =~ ^[0-9]+$ ]] || power_int=0

    local mem_pct=0
    (( mem_total > 0 )) && mem_pct=$(( (100*mem_used)/mem_total ))

    local status="ok"
    if   (( temp >= 85 )); then status="critical"
    elif (( temp >= 75 )); then status="warm"
    fi

    push_hist "gpu" "$util"
    local hist_csv; hist_csv=$(read_hist "gpu")

    local bar_color; bar_color=$(bar_color_for "$status")
    local util_bar; util_bar=$(hbar "$util" 16)
    local mem_bar;  mem_bar=$(hbar "$mem_pct" 16)
    local hist_spark; hist_spark=$(sparkline "$hist_csv")

    local tt=""
    tt+=" <b>${name}</b>   $(status_chip "$status")"$'\n'
    tt+=" $(rule)"$'\n'
    tt+=$'\n'
    tt+=$(printf "  <span foreground=\"%s\">GPU Usage</span>  <b>%3d%%</b>   <tt><span foreground=\"%s\">%s</span></tt>" \
        "$COLOR_DIM" "$util" "$bar_color" "$util_bar")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Temp</span>       <b>%3d°C</b>" "$COLOR_DIM" "$temp")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Power</span>      <b>%d W</b>" "$COLOR_DIM" "$power_int")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Fan</span>        <b>%d%%</b>" "$COLOR_DIM" "$fan")$'\n'
    tt+=$'\n'
    tt+=" <b>VRAM</b>"$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Used</span>       <b>%d</b> / %d MiB  (%d%%)" \
        "$COLOR_DIM" "$mem_used" "$mem_total" "$mem_pct")$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${mem_bar}</span></tt>"$'\n'
    tt+=$'\n'
    tt+=$(printf "  <span foreground=\"%s\">GPU clock</span>  <b>%d MHz</b>" "$COLOR_DIM" "$clk_gfx")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Mem clock</span>  <b>%d MHz</b>" "$COLOR_DIM" "$clk_mem")$'\n'
    tt+=$'\n'
    tt+=" <b>Utilization history</b>"$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${hist_spark}</span></tt>"

    local wb_text=" ${temp}°"
    emit_module "gpu" "$wb_text" "$tt" "$status"
}

# ────────────────────────────────────────────
# RAM
# ────────────────────────────────────────────
collect_ram() {
    local total=0 free=0 available=0 buffers=0 cached=0 swap_total=0 swap_free=0
    while IFS=':' read -r k v; do
        v="${v// /}"; v="${v%kB}"
        case "$k" in
            MemTotal)     total=$v;;
            MemFree)      free=$v;;
            MemAvailable) available=$v;;
            Buffers)      buffers=$v;;
            Cached)       cached=$v;;
            SwapTotal)    swap_total=$v;;
            SwapFree)     swap_free=$v;;
        esac
    done < /proc/meminfo

    local used=$((total - available))
    local used_pct=0
    (( total > 0 )) && used_pct=$(( (100*used)/total ))
    local swap_used=$((swap_total - swap_free))
    local swap_pct=0
    (( swap_total > 0 )) && swap_pct=$(( (100*swap_used)/swap_total ))

    local total_gb used_gb available_gb cached_gb buffers_gb swap_used_gb swap_total_gb
    total_gb=$(awk -v v=$total 'BEGIN{printf "%.2f", v/1048576}')
    used_gb=$(awk -v v=$used 'BEGIN{printf "%.2f", v/1048576}')
    available_gb=$(awk -v v=$available 'BEGIN{printf "%.2f", v/1048576}')
    cached_gb=$(awk -v v=$cached 'BEGIN{printf "%.2f", v/1048576}')
    buffers_gb=$(awk -v v=$buffers 'BEGIN{printf "%.2f", v/1048576}')
    swap_used_gb=$(awk -v v=$swap_used 'BEGIN{printf "%.2f", v/1048576}')
    swap_total_gb=$(awk -v v=$swap_total 'BEGIN{printf "%.2f", v/1048576}')

    local status="ok"
    if   (( used_pct >= 90 )); then status="critical"
    elif (( used_pct >= 75 )); then status="warm"
    fi

    push_hist "ram" "$used_pct"
    local hist_csv; hist_csv=$(read_hist "ram")

    local bar_color; bar_color=$(bar_color_for "$status")
    local ram_bar;   ram_bar=$(hbar "$used_pct" 16)
    local swap_bar;  swap_bar=$(hbar "$swap_pct" 16)
    local hist_spark; hist_spark=$(sparkline "$hist_csv")

    local tt=""
    tt+=" <b>Memory</b>   $(status_chip "$status")"$'\n'
    tt+=" $(rule)"$'\n'
    tt+=$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Used</span>       <b>%s</b> GiB" "$COLOR_DIM" "$used_gb")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Available</span>  <b>%s</b> GiB" "$COLOR_DIM" "$available_gb")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Cached</span>     <b>%s</b> GiB" "$COLOR_DIM" "$cached_gb")$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Total</span>      <b>%s</b> GiB" "$COLOR_DIM" "$total_gb")$'\n'
    tt+=$'\n'
    tt+=$(printf "  <span foreground=\"%s\">RAM</span>        <b>%d%%</b>" "$COLOR_DIM" "$used_pct")$'\n'
    tt+="  <tt><span foreground=\"$bar_color\">${ram_bar}</span></tt>"$'\n'
    tt+=$(printf "  <span foreground=\"%s\">Swap</span>       <b>%s</b> / %s GiB (%d%%)" \
        "$COLOR_DIM" "$swap_used_gb" "$swap_total_gb" "$swap_pct")$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${swap_bar}</span></tt>"$'\n'
    tt+=$'\n'
    tt+=" <b>Usage history</b>"$'\n'
    tt+="  <tt><span foreground=\"$COLOR_BAR\">${hist_spark}</span></tt>"

    local wb_text="󰘚 ${used_pct}%"
    emit_module "ram" "$wb_text" "$tt" "$status"
}

# ────────────────────────────────────────────
# Storage
# ────────────────────────────────────────────
collect_storage() {
    local lines=()
    declare -A seen
    while read -r src mnt fstype size used avail pct; do
        [[ "$src" == "Filesystem" ]] && continue
        case "$fstype" in
            efivarfs|tmpfs|devtmpfs|squashfs|proc|sysfs|cgroup|cgroup2|autofs|overlay|ramfs|nsfs|configfs|debugfs|tracefs|securityfs|pstore|mqueue|hugetlbfs|bpf|binfmt_misc|fusectl|fuse.gvfsd-fuse|fuse.portal)
                continue ;;
        esac
        case "$mnt" in
            /sys/*|/proc/*|/run/*|/dev/*) continue ;;
        esac
        [[ -n "${seen[$src]:-}" ]] && continue
        seen[$src]=1

        local size_gb used_gb
        size_gb=$(awk -v v=$size 'BEGIN{printf "%.1f", v/1073741824}')
        used_gb=$(awk -v v=$used 'BEGIN{printf "%.1f", v/1073741824}')
        local pct_int="${pct%\%}"
        [[ "$pct_int" =~ ^[0-9]+$ ]] || pct_int=0

        lines+=("$src|$mnt|$fstype|$size_gb|$used_gb|$pct_int")
    done < <(df -B1 --output=source,target,fstype,size,used,avail,pcent 2>/dev/null)

    local root_pct
    root_pct=$(df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9')
    [[ -z "$root_pct" ]] && root_pct=0

    local status="ok"
    if   (( root_pct >= 90 )); then status="critical"
    elif (( root_pct >= 75 )); then status="warm"
    fi

    local tt=""
    tt+=" <b>Mounted volumes</b>   $(status_chip "$status")"$'\n'
    tt+=" $(rule)"$'\n'
    tt+=$'\n'
    local row src mnt fstype size_gb used_gb pct_int row_status row_color row_bar
    for row in "${lines[@]}"; do
        IFS='|' read -r src mnt fstype size_gb used_gb pct_int <<< "$row"
        row_status="ok"
        if   (( pct_int >= 90 )); then row_status="critical"
        elif (( pct_int >= 75 )); then row_status="warm"
        fi
        row_color=$(bar_color_for "$row_status")
        row_bar=$(hbar "$pct_int" 18)
        # Escape mount point and fstype just in case
        local mnt_esc fstype_esc
        mnt_esc=$(printf '%s' "$mnt" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        fstype_esc=$(printf '%s' "$fstype" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
        tt+=$(printf "  <b>%s</b>  <span foreground=\"%s\">%s</span>" "$mnt_esc" "$COLOR_DIM" "$fstype_esc")$'\n'
        tt+=$(printf "  <tt><span foreground=\"%s\">%s</span></tt>  <b>%d%%</b>  <span foreground=\"%s\">%s / %s GiB</span>" \
            "$row_color" "$row_bar" "$pct_int" "$COLOR_DIM" "$used_gb" "$size_gb")$'\n'
        tt+=$'\n'
    done
    # Trim trailing newline
    tt="${tt%$'\n'}"

    local wb_text="󰋊 ${root_pct}%"
    emit_module "storage" "$wb_text" "$tt" "$status"
}

# ────────────────────────────────────────────
# Main loop
# ────────────────────────────────────────────
trap 'exit 0' INT TERM
COUNTER=0
collect_cpu
sleep 0.5
while true; do
    collect_cpu
    collect_gpu
    collect_ram
    if (( COUNTER % 8 == 0 )); then
        collect_storage
    fi
    COUNTER=$((COUNTER+1))
    sleep "$INTERVAL"
done
