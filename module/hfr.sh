#!/system/bin/sh
# ============================================================
#  真·全局高刷 · 核心引擎 (Global HFR Engine)
#  Author : 颖哥
#  Desc   : 设备识别 / 刷新率档位扫描 / 全局锁定 / 动态刷新率
#           触控加速 / 状态核验 / 开机守护 / 配置持久化
# ============================================================

MODID=global_hfr
SELF_DIR=$(cd "${0%/*}" 2>/dev/null && pwd)
MODDIR=${MODDIR:-$SELF_DIR}
if [ ! -f "$MODDIR/module.prop" ]; then
    for d in /data/adb/modules/$MODID /data/adb/modules_update/$MODID; do
        if [ -f "$d/module.prop" ]; then MODDIR=$d; break; fi
    done
fi

DATA=${HFR_DATA:-/data/adb/global_hfr}
CONF=$DATA/config.conf
MODES=$DATA/modes.tsv
STATE=$DATA/state.conf
LOG=$DATA/run.log
ORIG=$DATA/orig.conf
TOUCHBAK=$DATA/touch.backup
TOUCHSTATE=$DATA/touch.state
REV=$DATA/rev

PATH=/system/bin:/system/xbin:/vendor/bin:/sbin:$PATH
export PATH
umask 022

TAB=$(printf '\t')
VER=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)
[ -n "$VER" ] || VER=v1.2.0

mkdir -p "$DATA" 2>/dev/null

# ------------------------------------------------------------
#  基础工具
# ------------------------------------------------------------
log() {
    [ -d "$DATA" ] || return 0
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 131072 ] 2>/dev/null; then
        tail -n 300 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
    fi
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

now() { date +%s; }

is_num() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

jesc() {
    printf '%s' "$1" | tr -d '\r\n\t' | sed 's/["\\]//g' 2>/dev/null
}

prop() {
    v=$(getprop "$1" 2>/dev/null)
    printf '%s' "$v" | tr -d '\r\n'
}

put_setting() {
    ns=$1; key=$2; val=$3; i=0
    while [ "$i" -lt 3 ]; do
        if settings put "$ns" "$key" "$val" >/dev/null 2>&1; then return 0; fi
        i=$((i + 1))
        sleep 1
    done
    log "settings put $ns/$key=$val 失败"
    return 1
}

# ------------------------------------------------------------
#  配置
# ------------------------------------------------------------
profile=fixed
fixed_hz=0
dyn_min=60
dyn_max=0
touch=1
touch_level=standard
deep_lock=1
overlay=0
daemon=1
auto_boot=1
oplus_props=0
sampling=0

last_verified_hz=""
measured_hz=""
sampling_applied=0
sampling_method=""

load_conf() {
    profile=fixed; fixed_hz=0; dyn_min=60; dyn_max=0
    touch=1; touch_level=standard; deep_lock=1; overlay=0
    daemon=1; auto_boot=1; oplus_props=0; sampling=0
    [ -f "$CONF" ] || return 0
    while IFS='=' read -r k v; do
        v=$(printf '%s' "$v" | tr -d ' \t\r')
        case "$k" in
            profile) case "$v" in fixed|dynamic|off) profile=$v ;; esac ;;
            fixed_hz) is_num "$v" && fixed_hz=$v ;;
            dyn_min) is_num "$v" && dyn_min=$v ;;
            dyn_max) is_num "$v" && dyn_max=$v ;;
            touch) case "$v" in 0|1) touch=$v ;; esac ;;
            touch_level) case "$v" in standard|esports) touch_level=$v ;; esac ;;
            deep_lock) case "$v" in 0|1) deep_lock=$v ;; esac ;;
            overlay) case "$v" in 0|1) overlay=$v ;; esac ;;
            daemon) case "$v" in 0|1) daemon=$v ;; esac ;;
            auto_boot) case "$v" in 0|1) auto_boot=$v ;; esac ;;
            oplus_props) case "$v" in 0|1) oplus_props=$v ;; esac ;;
            sampling) case "$v" in 0|120|240|360|480) sampling=$v ;; esac ;;
        esac
    done < "$CONF"
}

save_conf_key() {
    k=$1; v=$2
    [ -f "$CONF" ] || : > "$CONF"
    if grep -q "^$k=" "$CONF" 2>/dev/null; then
        sed -i "s|^$k=.*|$k=$v|" "$CONF" 2>/dev/null
    else
        echo "$k=$v" >> "$CONF"
    fi
}

# 校验并写入一项配置，成功返回 0
set_conf() {
    k=$1; v=$2
    case "$k" in
        profile) case "$v" in fixed|dynamic|off) ;; *) return 2 ;; esac ;;
        fixed_hz|dyn_min|dyn_max) is_num "$v" || return 2 ;;
        touch|deep_lock|overlay|daemon|auto_boot|oplus_props) case "$v" in 0|1) ;; *) return 2 ;; esac ;;
        sampling) case "$v" in 0|120|240|360|480) ;; *) return 2 ;; esac ;;
        touch_level) case "$v" in standard|esports) ;; *) return 2 ;; esac ;;
        *) return 2 ;;
    esac
    save_conf_key "$k" "$v"
    now > "$REV" 2>/dev/null
    return 0
}

# ------------------------------------------------------------
#  设备信息
# ------------------------------------------------------------
rom_name() {
    v=$(prop ro.mi.os.version.name)
    [ -n "$v" ] && { echo "HyperOS $v"; return; }
    v=$(prop ro.miui.ui.version.name)
    [ -n "$v" ] && { echo "MIUI $v"; return; }
    v=$(prop ro.build.version.oplusrom)
    [ -n "$v" ] && { echo "ColorOS $v"; return; }
    v=$(prop ro.build.version.opporom)
    [ -n "$v" ] && { echo "ColorOS $v"; return; }
    v=$(prop ro.build.version.oxygenos)
    [ -n "$v" ] && { echo "OxygenOS $v"; return; }
    v=$(prop ro.build.version.realmeui)
    [ -n "$v" ] && { echo "realme UI $v"; return; }
    prop ro.build.display.id
}

platform_name() {
    p=$(prop ro.board.platform)
    [ -n "$p" ] || p=$(prop ro.hardware)
    case "$p" in
        *mt*|*MT*) echo "mediatek" ;;
        *sm*|*msm*|*MSM*|*kalama*|*taro*|*crow*|*pineapple*|*sun*|*blair*|*parrot*) echo "qualcomm" ;;
        *) echo "unknown" ;;
    esac
}

device_market() {
    v=$(prop ro.product.market.name)
    [ -n "$v" ] || v=$(prop ro.vendor.oplus.market.name)
    [ -n "$v" ] || v=$(prop ro.product.model)
    echo "$v"
}

# ------------------------------------------------------------
#  刷新率档位
# ------------------------------------------------------------
scan_modes() {
    tmp=$DATA/.modes.$$
    dumpsys SurfaceFlinger 2>/dev/null | awk '
        {
            line = $0
            if (line !~ /id=[0-9]+/) next
            if (line !~ /resolution=[0-9]+x[0-9]+/) next
            if (line !~ /(vsyncRate|refreshRate)=[0-9.]+/) next
            id = ""; w = ""; h = ""; f = ""
            if (match(line, /id=[0-9]+,/)) id = substr(line, RSTART + 3, RLENGTH - 4)
            if (match(line, /resolution=[0-9]+x[0-9]+/)) {
                s = substr(line, RSTART + 11, RLENGTH - 11)
                split(s, a, "x"); w = a[1]; h = a[2]
            }
            if (match(line, /(vsyncRate|refreshRate)=[0-9.]+/)) {
                s = substr(line, RSTART, RLENGTH); sub(/.*=/, "", s); f = s + 0
            }
            if (id != "" && f > 0) printf "%s\t%s\t%s\t%.0f\n", id, w, h, f
        }' > "$tmp" 2>/dev/null

    if [ ! -s "$tmp" ]; then
        # 备用解析：dumpsys display 的 Display.Mode{...}
        dumpsys display 2>/dev/null | awk '
            {
                line = $0
                while (match(line, /id=[0-9]+, width=[0-9]+, height=[0-9]+, refreshRate=[0-9.]+/)) {
                    s = substr(line, RSTART, RLENGTH)
                    split(s, a, ",")
                    id = a[1]; sub(/.*id=/, "", id)
                    w = a[2]; sub(/.*width=/, "", w)
                    h = a[3]; sub(/.*height=/, "", h)
                    f = a[4]; sub(/.*refreshRate=/, "", f)
                    printf "%s\t%s\t%s\t%.0f\n", id, w, h, f + 0
                    line = substr(line, RSTART + RLENGTH)
                }
            }' > "$tmp" 2>/dev/null
    fi

    if [ ! -s "$tmp" ]; then
        # 备用解析：部分 ROM 的 dumpsys 使用 "Mode ID: N, Resolution: WxH, Refresh Rate: F"
        { dumpsys display 2>/dev/null; dumpsys SurfaceFlinger 2>/dev/null; } | awk '
            {
                line = $0
                if (line !~ /Mode ID:/) next
                id = ""; w = ""; h = ""; f = ""
                if (match(line, /Mode ID:[ \t]*[0-9]+/)) {
                    s = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", s); id = s
                }
                if (match(line, /Resolution:[ \t]*[0-9]+x[0-9]+/)) {
                    s = substr(line, RSTART, RLENGTH); sub(/.*Resolution:[ \t]*/, "", s)
                    split(s, a, "x"); w = a[1]; h = a[2]
                }
                if (match(line, /Refresh Rate:[ \t]*[0-9.]+/)) {
                    s = substr(line, RSTART, RLENGTH); sub(/.*Refresh Rate:[ \t]*/, "", s); f = s + 0
                }
                if (id != "" && f > 0) printf "%s\t%s\t%s\t%.0f\n", id, w, h, f
            }' > "$tmp" 2>/dev/null
    fi

    awk -F'\t' '!seen[$1]++' "$tmp" 2>/dev/null | sort -k4,4n > "$MODES.tmp" 2>/dev/null
    rm -f "$tmp"
    if [ -s "$MODES.tmp" ]; then
        mv -f "$MODES.tmp" "$MODES"
        log "扫描到 $(wc -l < "$MODES") 个显示档位"
        return 0
    fi
    rm -f "$MODES.tmp"
    return 1
}

ensure_modes() {
    [ -s "$MODES" ] || scan_modes
}

max_hz() {
    [ -s "$MODES" ] || return 1
    awk -F'\t' 'BEGIN{m=0} {if ($4+0 > m) m = $4+0} END{if (m > 0) printf "%.0f\n", m}' "$MODES" 2>/dev/null
}

# 选择最接近目标刷新率的档位，输出 "id hz"
pick_mode() {
    want=$1
    [ -s "$MODES" ] || return 1
    awk -F'\t' -v t="$want" '
        function abs(x) { return x < 0 ? -x : x }
        {
            d = abs($4 - t); px = $2 * $3
            if (!found || d < bd - 0.001 || (d <= bd + 0.001 && px > bp)) {
                found = 1; best = $1; bd = d; bp = px; bh = $4
            }
        }
        END { if (found && bd <= 3) printf "%s %.0f\n", best, bh }
    ' "$MODES" 2>/dev/null
}

# ------------------------------------------------------------
#  当前刷新率读取（多路回退）
# ------------------------------------------------------------
current_hz() {
    v=""
    v=$(dumpsys display 2>/dev/null | sed -n 's/.*refreshRate[ =:]*\([0-9][0-9.]*\).*/\1/p' | head -n 1)
    if [ -z "$v" ]; then
        v=$(dumpsys SurfaceFlinger 2>/dev/null | sed -n 's/.*[Rr]efresh[- ]*[Rr]ate[:= ]*\([0-9][0-9.]*\).*/\1/p' | head -n 1)
    fi
    if [ -z "$v" ]; then
        v=$(dumpsys SurfaceFlinger 2>/dev/null | sed -n 's/.*Refresh Rate:[ \t]*\([0-9][0-9.]*\).*/\1/p' | head -n 1)
    fi
    if [ -z "$v" ]; then
        ns=$(dumpsys SurfaceFlinger 2>/dev/null | sed -n 's/.*[Vv]sync period[:= ]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
        if [ -n "$ns" ] && [ "$ns" -gt 0 ] 2>/dev/null; then
            v=$(awk -v n="$ns" 'BEGIN{printf "%.0f", 1000000000 / n}')
        fi
    fi
    if [ -z "$v" ]; then
        mid=$(dumpsys display 2>/dev/null | sed -n 's/.*mActiveModeId[ =:]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
        if [ -n "$mid" ] && [ -s "$MODES" ]; then
            v=$(awk -F'\t' -v i="$mid" '$1 == i {print $4; exit}' "$MODES")
        fi
    fi
    if [ -z "$v" ]; then
        v=$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n')
    fi
    case "$v" in
        ''|null|*[!0-9.]*) echo "" ;;
        *) awk -v x="$v" 'BEGIN{printf "%.0f", x}' 2>/dev/null ;;
    esac
}

screen_on() {
    w=$(dumpsys power 2>/dev/null | sed -n 's/.*\(mWakefulness=[A-Za-z]*\).*/\1/p' | head -n 1)
    case "$w" in
        *=Asleep|*=Dozing|*=Dreaming) return 1 ;;
    esac
    return 0
}

# ------------------------------------------------------------
#  显示控制
# ------------------------------------------------------------
sf_set() {
    out=$(service call SurfaceFlinger 1035 i32 "$1" 2>&1)
    case "$out" in
        *Exception*|*Error*|*error*|*"Failed"*) log "SF 1035($1) 返回: $out"; return 1 ;;
    esac
    return 0
}

clear_backdoor() {
    # 非法档位会让 SurfaceFlinger 清掉 backdoor 标志，从而交还 DisplayManager 策略
    service call SurfaceFlinger 1035 i32 65535 >/dev/null 2>&1
    sleep 0.15
}

backup_orig() {
    [ -f "$ORIG" ] && return 0
    {
        echo "peak=$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n')"
        echo "min=$(settings get system min_refresh_rate 2>/dev/null | tr -d '\r\n')"
        echo "user=$(settings get system user_refresh_rate 2>/dev/null | tr -d '\r\n')"
    } > "$ORIG" 2>/dev/null
}

restore_orig() {
    if [ ! -f "$ORIG" ]; then
        settings delete system peak_refresh_rate >/dev/null 2>&1
        settings delete system min_refresh_rate >/dev/null 2>&1
        return 0
    fi
    peak=$(sed -n 's/^peak=//p' "$ORIG" | head -n 1)
    min=$(sed -n 's/^min=//p' "$ORIG" | head -n 1)
    case "$peak" in
        ''|null) settings delete system peak_refresh_rate >/dev/null 2>&1 ;;
        *) settings put system peak_refresh_rate "$peak" >/dev/null 2>&1 ;;
    esac
    case "$min" in
        ''|null) settings delete system min_refresh_rate >/dev/null 2>&1 ;;
        *) settings put system min_refresh_rate "$min" >/dev/null 2>&1 ;;
    esac
    if grep -q '^user=' "$ORIG" 2>/dev/null; then
        user=$(sed -n 's/^user=//p' "$ORIG" | head -n 1)
        case "$user" in
            ''|null) settings delete system user_refresh_rate >/dev/null 2>&1 ;;
            *) settings put system user_refresh_rate "$user" >/dev/null 2>&1 ;;
        esac
    fi
    rm -f "$ORIG"
    log "已恢复系统原始刷新率设置 peak=$peak min=$min"
}

restore_user_rate() {
    [ -f "$ORIG" ] || return 0
    grep -q '^user=' "$ORIG" 2>/dev/null || return 0
    user=$(sed -n 's/^user=//p' "$ORIG" | head -n 1)
    case "$user" in
        ''|null) settings delete system user_refresh_rate >/dev/null 2>&1 ;;
        *) settings put system user_refresh_rate "$user" >/dev/null 2>&1 ;;
    esac
}

active_mode_id() {
    v=$(dumpsys display 2>/dev/null | sed -n 's/.*mActiveModeId[ =:]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
    [ -n "$v" ] || v=$(dumpsys SurfaceFlinger 2>/dev/null | sed -n 's/.*[Aa]ctiveModeId[ =:]*\([0-9][0-9]*\).*/\1/p' | head -n 1)
    echo "$v"
}

verify_target() {
    want=$1; mid=$2
    last_verified_hz=""
    sleep 0.2
    c=$(current_hz)
    if [ -n "$c" ]; then
        d=$((c - want)); [ "$d" -lt 0 ] && d=$((-d))
        [ "$d" -le 2 ] && { last_verified_hz=$c; return 0; }
    fi
    if [ -n "$mid" ]; then
        am=$(active_mode_id)
        [ "$am" = "$mid" ] && { last_verified_hz=$want; return 0; }
    fi
    i=0
    while [ "$i" -lt 3 ]; do
        sleep 0.3
        c=$(current_hz)
        if [ -n "$c" ]; then
            d=$((c - want)); [ "$d" -lt 0 ] && d=$((-d))
            [ "$d" -le 2 ] && { last_verified_hz=$c; return 0; }
        fi
        i=$((i + 1))
    done
    return 1
}

apply_display() {
    method=""
    verified=0
    target_hz=0
    measured_hz=""
    last_verified_hz=""
    case "$profile" in
        off)
            clear_backdoor
            restore_orig
            method="系统默认"
            verified=1
            ;;
        dynamic)
            lo=$dyn_min; hi=$dyn_max
            is_num "$lo" || lo=60
            if ! is_num "$hi" || [ "$hi" -eq 0 ]; then hi=$(max_hz); fi
            [ -z "$hi" ] && hi=120
            [ "$hi" -le "$lo" ] && hi=$((lo + 1))
            clear_backdoor
            backup_orig
            restore_user_rate
            put_setting system min_refresh_rate "$lo"
            put_setting system peak_refresh_rate "$hi"
            sleep 0.35
            target_hz=$hi
            method="动态 ${lo}-${hi}Hz"
            verified=1
            ;;
        *)
            t=$fixed_hz
            is_num "$t" || t=0
            if [ "$t" -eq 0 ]; then t=$(max_hz); fi
            [ -z "$t" ] && t=120
            set -- $(pick_mode "$t")
            mid=$1; mhz=$2
            if [ -z "$mid" ]; then
                method="未检测到 ${t}Hz 档位"
                log "$method"
                return 1
            fi
            if [ "$deep_lock" != 1 ]; then
                clear_backdoor
            fi
            backup_orig
            put_setting system min_refresh_rate "$mhz"
            put_setting system peak_refresh_rate "$mhz"
            put_setting system user_refresh_rate "$mhz"
            sleep 0.15
            target_hz=$mhz
            if [ "$deep_lock" = 1 ]; then
                if sf_set "$mid"; then method="SurfaceFlinger · mode $mid"; fi
                sleep 0.3
            fi
            if verify_target "$mhz" "$mid"; then
                verified=1
                [ -n "$method" ] || method="Settings · ${mhz}Hz"
            else
                cmd display set-user-preferred-display-mode "$mid" >/dev/null 2>&1
                sleep 0.4
                if verify_target "$mhz" "$mid"; then
                    verified=1
                    method="DisplayManager · mode $mid"
                fi
            fi
            if [ "$verified" = 1 ]; then
                measured_hz=${last_verified_hz:-$mhz}
            fi
            if [ "$verified" = 0 ]; then
                [ -n "$method" ] || method="Settings"
                method="$method · 未确认"
                log "锁定 ${mhz}Hz 未通过核验"
            fi
            ;;
    esac
    return 0
}

# ------------------------------------------------------------
#  触控增强
# ------------------------------------------------------------
TOUCH_SPEC="touchboost|/sys/module/msm_performance/parameters/touchboost|1|0
touchboost_alt|/sys/kernel/msm_performance/parameters/touchboost|1|0
input_boost|/sys/module/cpu_boost/parameters/input_boost_enabled|1|0
adreno_idler|/sys/module/adreno_idler/parameters/adreno_idler_active|0|1
mtk_fpsgo|/sys/kernel/fpsgo/common/force_onoff|1|0
x_gpu_gov|/sys/class/kgsl/kgsl-3d0/devfreq/governor|performance|
x_sched_boost|/proc/sys/kernel/sched_boost|1|0"

SAMPLINGBAK=$DATA/sampling.backup
SAMPLING_NODES="/sys/class/touch/touch_dev/touch_thp_ic_cmd /sys/class/touch/touch_dev/touch_ic_cmd"

sampling_node() {
    for p in $SAMPLING_NODES; do
        [ -e "$p" ] && { echo "$p"; return 0; }
    done
    return 1
}

apply_sampling() {
    sampling_applied=0
    sampling_method=""
    case "$sampling" in
        0|'') return 0 ;;
    esac
    node=$(sampling_node)
    [ -n "$node" ] || return 1

    if [ ! -f "$SAMPLINGBAK" ]; then
        v=$(cat "$node" 2>/dev/null | tr -d '\r\n')
        printf '%s\t%s\n' "$node" "$v" > "$SAMPLINGBAK" 2>/dev/null
    fi

    # Xiaomi thp 协议：8 3007 <rate> 1（不能带换行）
    if printf '%s' "8 3007 $sampling 1" > "$node" 2>/dev/null; then
        sampling_applied=1
        sampling_method="thp $sampling"
        log "触控采样率写入 ${sampling}Hz -> $node"
        return 0
    fi
    log "触控采样率写入失败 -> $node"
    return 1
}

restore_sampling() {
    node=$(sampling_node)
    if [ -f "$SAMPLINGBAK" ]; then
        while IFS=$TAB read -r p v; do
            [ -n "$p" ] || continue
            if [ -n "$v" ]; then
                printf '%s' "$v" > "$p" 2>/dev/null
            elif [ -n "$node" ]; then
                printf '%s' "8 3007 120 1" > "$node" 2>/dev/null
            fi
            break
        done < "$SAMPLINGBAK"
        rm -f "$SAMPLINGBAK"
    fi
    sampling_applied=0
    sampling_method=""
}

backup_touch_node() {
    p=$1
    [ -f "$TOUCHBAK" ] || : > "$TOUCHBAK"
    if awk -F'\t' -v p="$p" '$1 == p {f=1} END{exit !f}' "$TOUCHBAK" 2>/dev/null; then
        return 0
    fi
    v=$(cat "$p" 2>/dev/null | tr -d ' \t\r\n')
    printf '%s\t%s\n' "$p" "$v" >> "$TOUCHBAK" 2>/dev/null
}

write_node() {
    p=$1; v=$2
    [ -e "$p" ] || return 1
    echo "$v" > "$p" 2>/dev/null || return 1
    got=$(cat "$p" 2>/dev/null | tr -d ' \t\r\n')
    [ "$got" = "$v" ]
}

renice_touch() {
    prio=$1
    hit=0
    for n in surfaceflinger vendor-oplus-hardware-touch-V2-service \
             vendor-oplus-hardware-touch-V2-hbp5-service vendor.touch-aidl-2 touchDaemon; do
        pid=$(pidof "$n" 2>/dev/null | awk '{print $1}')
        if [ -n "$pid" ]; then
            renice -n "$prio" -p "$pid" >/dev/null 2>&1 && hit=$((hit + 1))
        fi
    done
    echo "$hit"
}

restore_touch() {
    restore_sampling
    if [ -f "$TOUCHBAK" ]; then
        while IFS=$TAB read -r p v; do
            [ -n "$p" ] || continue
            echo "$v" > "$p" 2>/dev/null
        done < "$TOUCHBAK"
        rm -f "$TOUCHBAK"
    fi
    renice_touch 0 >/dev/null 2>&1
    rm -f "$TOUCHSTATE"
    touch_applied=0
}

apply_touch() {
    touch_applied=0
    # 先还原上一轮（含电竞档）写入的节点，避免降档后 GPU/调度 boost 残留
    restore_touch
    if [ "$touch" != 1 ]; then
        return 0
    fi
    : > "$TOUCHSTATE" 2>/dev/null

    while IFS='|' read -r name p on off; do
        [ -n "$name" ] || continue
        [ -e "$p" ] || continue
        case "$name" in
            x_*) [ "$touch_level" = esports ] || continue ;;
        esac
        backup_touch_node "$p"
        if write_node "$p" "$on"; then
            printf '%s|%s|1|%s\n' "$name" "$p" "$on" >> "$TOUCHSTATE"
            touch_applied=$((touch_applied + 1))
        else
            printf '%s|%s|0|%s\n' "$name" "$p" "$on" >> "$TOUCHSTATE"
        fi
    done <<EOF
$TOUCH_SPEC
EOF

    if [ "$touch_level" = esports ]; then
        prio=-15
    else
        prio=-8
    fi
    n=$(renice_touch "$prio")
    if [ "$n" -gt 0 ] 2>/dev/null; then
        printf 'renice|touch HAL|1|%s\n' "$prio" >> "$TOUCHSTATE"
        touch_applied=$((touch_applied + 1))
    fi
    apply_sampling
    [ "$sampling_applied" = 1 ] && touch_applied=$((touch_applied + 1))
    log "触控增强 level=$touch_level 生效节点=$touch_applied renice=$n sampling=$sampling"
}

# ------------------------------------------------------------
#  状态
# ------------------------------------------------------------
write_state() {
    cur=$1
    [ -n "$cur" ] || cur=$(current_hz)
    [ -n "$cur" ] || cur=0
    {
        echo "ts=$(now)"
        echo "profile=$profile"
        echo "target=$target_hz"
        echo "current=$cur"
        echo "verified=$verified"
        echo "method=$method"
        echo "touch_applied=$touch_applied"
        echo "sampling_applied=$sampling_applied"
        echo "sampling_method=$sampling_method"
    } > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
}

apply_all() {
    ensure_modes
    apply_display
    apply_touch
    if [ "$overlay" = 1 ]; then
        service call SurfaceFlinger 1034 i32 1 >/dev/null 2>&1
    else
        service call SurfaceFlinger 1034 i32 0 >/dev/null 2>&1
    fi
    write_state "$measured_hz"
    log "应用完成 profile=$profile target=$target_hz verified=$verified method=$method touch=$touch/$touch_applied sampling=$sampling"
}

restore_all() {
    clear_backdoor
    service call SurfaceFlinger 1034 i32 0 >/dev/null 2>&1
    restore_orig
    restore_touch
    save_conf_key profile off
    save_conf_key touch 0
    now > "$REV" 2>/dev/null
    profile=off
    touch=0
    target_hz=0
    verified=1
    method="已恢复系统默认"
    write_state
    log "已恢复系统默认状态"
}

touch_json() {
    first=1
    while IFS='|' read -r name p on off; do
        [ -n "$name" ] || continue
        exists=0
        [ -e "$p" ] && exists=1
        ok=0
        [ -f "$TOUCHSTATE" ] && ok=$(awk -F'|' -v n="$name" '$1 == n {print ($3 == 1 ? 1 : 0); exit}' "$TOUCHSTATE" 2>/dev/null)
        [ -n "$ok" ] || ok=0
        [ "$first" = 1 ] || printf ','
        first=0
        printf '{"name":"%s","path":"%s","exists":%s,"ok":%s}' "$(jesc "$name")" "$(jesc "$p")" "$exists" "$ok"
    done <<EOF
$TOUCH_SPEC
EOF
    if [ -f "$TOUCHSTATE" ] && grep -q '^renice|' "$TOUCHSTATE" 2>/dev/null; then
        [ "$first" = 1 ] || printf ','
        printf '{"name":"renice","path":"touch HAL","exists":1,"ok":1}'
    fi
}

json_status() {
    load_conf
    cur=$(current_hz)
    st_target=$(sed -n 's/^target=//p' "$STATE" 2>/dev/null | head -n 1)
    st_cur=$(sed -n 's/^current=//p' "$STATE" 2>/dev/null | head -n 1)
    st_ver=$(sed -n 's/^verified=//p' "$STATE" 2>/dev/null | head -n 1)
    st_method=$(sed -n 's/^method=//p' "$STATE" 2>/dev/null | head -n 1)
    st_ts=$(sed -n 's/^ts=//p' "$STATE" 2>/dev/null | head -n 1)
    st_touch=$(sed -n 's/^touch_applied=//p' "$STATE" 2>/dev/null | head -n 1)
    st_sampling=$(sed -n 's/^sampling_applied=//p' "$STATE" 2>/dev/null | head -n 1)
    is_num "$st_target" || st_target=0
    is_num "$st_ver" || st_ver=0
    is_num "$st_ts" || st_ts=0
    is_num "$st_touch" || st_touch=0
    is_num "$st_sampling" || st_sampling=0
    if ! is_num "$st_cur"; then st_cur=$st_target; fi
    if [ -n "$cur" ]; then st_cur=$cur; fi

    mx=$(max_hz); [ -n "$mx" ] || mx=0
    sdk=$(prop ro.build.version.sdk); is_num "$sdk" || sdk=0

    printf '{"ok":1,"ts":%s,"version":"%s",' "$(now)" "$(jesc "$VER")"
    printf '"device":{"brand":"%s","model":"%s","market":"%s","rom":"%s","android":"%s","sdk":%s,"soc":"%s","platform":"%s"},' \
        "$(jesc "$(prop ro.product.brand)")" \
        "$(jesc "$(prop ro.product.model)")" \
        "$(jesc "$(device_market)")" \
        "$(jesc "$(rom_name)")" \
        "$(jesc "$(prop ro.build.version.release)")" \
        "$sdk" \
        "$(jesc "$(prop ro.soc.model)")" \
        "$(jesc "$(platform_name)")"

    printf '"panel":{"max":%s,"modes":[' "$mx"
    first=1
    if [ -s "$MODES" ]; then
        while read -r line; do
            set -- $line
            [ -n "$1" ] || continue
            [ "$first" = 1 ] || printf ','
            first=0
            printf '{"id":%s,"w":%s,"h":%s,"hz":%s}' "$1" "${2:-0}" "${3:-0}" "${4:-0}"
        done < "$MODES"
    fi
    printf ']},'

    printf '"config":{"profile":"%s","fixed_hz":%s,"dyn_min":%s,"dyn_max":%s,"touch":%s,"touch_level":"%s","sampling":%s,"deep_lock":%s,"overlay":%s,"daemon":%s,"auto_boot":%s,"oplus_props":%s},' \
        "$profile" "$fixed_hz" "$dyn_min" "$dyn_max" "$touch" "$touch_level" "$sampling" "$deep_lock" "$overlay" "$daemon" "$auto_boot" "$oplus_props"

    printf '"live":{"current":%s,"target":%s,"verified":%s,"method":"%s","updated":%s},' \
        "$st_cur" "$st_target" "$st_ver" "$(jesc "$st_method")" "$st_ts"

    sampling_node_path=$(sampling_node)
    sampling_exists=0
    [ -n "$sampling_node_path" ] && sampling_exists=1
    printf '"sampling":{"value":%s,"exists":%s,"applied":%s,"path":"%s"},' "$sampling" "$sampling_exists" "$st_sampling" "$(jesc "$sampling_node_path")"

    printf '"touch":{"enabled":%s,"level":"%s","applied":%s,"nodes":[' "$touch" "$touch_level" "$st_touch"
    touch_json
    printf ']}}\n'
}

apply_json() {
    if [ -n "$measured_hz" ]; then
        cur=$measured_hz
    else
        cur=$(current_hz)
    fi
    [ -n "$cur" ] || cur=0
    printf '{"ok":1,"profile":"%s","target":%s,"current":%s,"verified":%s,"method":"%s","touch_applied":%s,"sampling":%s,"sampling_applied":%s}\n' \
        "$profile" "${target_hz:-0}" "$cur" "${verified:-0}" "$(jesc "$method")" "${touch_applied:-0}" "$sampling" "$sampling_applied"
}

cmd_brief() {
    load_conf
    cur=$(current_hz)
    st_target=$(sed -n 's/^target=//p' "$STATE" 2>/dev/null | head -n 1)
    st_ver=$(sed -n 's/^verified=//p' "$STATE" 2>/dev/null | head -n 1)
    st_method=$(sed -n 's/^method=//p' "$STATE" 2>/dev/null | head -n 1)
    is_num "$st_target" || st_target=0
    is_num "$st_ver" || st_ver=0
    [ -n "$cur" ] || cur=$st_target

    case "$profile" in
        fixed) pdesc="全局锁定 ${st_target}Hz" ;;
        dynamic)
            dyn_hi=$dyn_max
            if ! [ "$dyn_hi" -gt 0 ] 2>/dev/null; then dyn_hi=$(max_hz); fi
            [ -n "$dyn_hi" ] || dyn_hi=120
            pdesc="动态 ${dyn_min}-${dyn_hi}Hz"
            ;;
        off) pdesc="系统默认（未接管）" ;;
        *) pdesc=$profile ;;
    esac

    echo "真·全局高刷 $VER · 作者 颖哥"
    echo "机型：$(device_market) ($(prop ro.product.model))"
    echo "系统：$(rom_name) / Android $(prop ro.build.version.release)"
    echo "配置：$pdesc · 触控 $([ "$touch" = 1 ] && echo "开启($touch_level)" || echo 关闭)"
    echo "当前：${cur:-未知}Hz · $([ "$st_ver" = 1 ] && echo "已核验" || echo "待核验")"
    echo "方式：${st_method:-未应用}"
}

# ------------------------------------------------------------
#  守护进程
# ------------------------------------------------------------
run_daemon() {
    load_conf
    n=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$n" -lt 150 ]; do
        sleep 1
        n=$((n + 1))
    done
    sleep 2

    if [ "$auto_boot" = 1 ]; then
        apply_all
    fi
    if [ "$daemon" != 1 ]; then
        log "守护已关闭，退出"
        return 0
    fi

    log "守护进程启动 profile=$profile daemon=$daemon"
    last_rev=$(cat "$REV" 2>/dev/null)
    prev_screen=off
    tick=0
    while :; do
        sleep 5
        tick=$((tick + 1))

        rev=$(cat "$REV" 2>/dev/null)
        if [ "$rev" != "$last_rev" ]; then
            last_rev=$rev
            load_conf
            apply_all
            tick=0
            if [ "$daemon" != 1 ]; then
                log "守护已关闭，退出"
                return 0
            fi
        fi

        if screen_on; then
            if [ "$prev_screen" != "on" ]; then
                apply_all
                tick=0
            elif [ "$profile" = "fixed" ] && [ "$((tick % 6))" -eq 0 ]; then
                c=$(current_hz)
                t=$target_hz
                if [ -n "$c" ] && is_num "$t" && [ "$t" -gt 0 ]; then
                    d=$((c - t)); [ "$d" -lt 0 ] && d=$((-d))
                    if [ "$d" -gt 2 ]; then
                        log "检测到刷新率漂移 current=$c target=$t，重新锁定"
                        apply_all
                        tick=0
                    fi
                fi
            fi
            prev_screen=on
        else
            prev_screen=off
            tick=0
        fi
    done
}

# ------------------------------------------------------------
#  入口
# ------------------------------------------------------------
cmd=${1:-status}
load_conf

case "$cmd" in
    status|info)
        ensure_modes
        json_status
        ;;
    scan)
        if scan_modes; then
            printf '{"ok":1,"count":%s,"max":%s}\n' "$(wc -l < "$MODES")" "$(max_hz)"
        else
            printf '{"ok":0,"count":0,"max":0}\n'
        fi
        ;;
    apply)
        apply_all
        apply_json
        ;;
    switch)
        case "$2" in
            fixed)
                is_num "$3" || { printf '{"ok":0}\n'; exit 2; }
                set_conf profile fixed
                set_conf fixed_hz "$3"
                ;;
            dynamic)
                is_num "$3" && is_num "$4" || { printf '{"ok":0}\n'; exit 2; }
                set_conf profile dynamic
                set_conf dyn_min "$3"
                set_conf dyn_max "$4"
                ;;
            off) set_conf profile off ;;
            sampling)
                case "$3" in 0|120|240|360|480) ;; *) printf '{"ok":0}\n'; exit 2 ;; esac
                set_conf sampling "$3"
                ;;
            touch)
                case "$3" in 0|1) ;; *) printf '{"ok":0}\n'; exit 2 ;; esac
                set_conf touch "$3"
                [ -n "$4" ] && set_conf touch_level "$4"
                ;;
            *) printf '{"ok":0}\n'; exit 2 ;;
        esac
        load_conf
        apply_all
        apply_json
        ;;
    set)
        if set_conf "$2" "$3"; then
            load_conf
            printf '{"ok":1,"key":"%s","value":"%s"}\n' "$(jesc "$2")" "$(jesc "$3")"
        else
            printf '{"ok":0,"error":"invalid"}\n'
            exit 2
        fi
        ;;
    preset)
        case "$2" in
            max) set_conf profile fixed; set_conf fixed_hz 0 ;;
            dynamic) set_conf profile dynamic; [ -n "$3" ] && set_conf dyn_min "$3"; [ -n "$4" ] && set_conf dyn_max "$4" ;;
            off) set_conf profile off ;;
            *) printf '{"ok":0}\n'; exit 2 ;;
        esac
        load_conf
        apply_all
        apply_json
        ;;
    touch)
        case "$2" in
            on) set_conf touch 1 ;;
            off) set_conf touch 0 ;;
            level) [ -n "$3" ] && set_conf touch_level "$3" ;;
            *) printf '{"ok":0}\n'; exit 2 ;;
        esac
        load_conf
        apply_all
        apply_json
        ;;
    restore|reset)
        restore_all
        printf '{"ok":1}\n'
        ;;
    toggle)
        if [ "$profile" = off ]; then
            set_conf profile fixed; set_conf fixed_hz 0
        else
            set_conf profile off
        fi
        load_conf
        apply_all
        apply_json
        ;;
    log)
        n=${2:-80}
        is_num "$n" || n=80
        tail -n "$n" "$LOG" 2>/dev/null
        ;;
    brief)
        cmd_brief
        ;;
    modes)
        cat "$MODES" 2>/dev/null
        ;;
    daemon|run)
        run_daemon
        ;;
    *)
        echo "usage: hfr.sh status|scan|apply|set <k> <v>|preset max|dynamic|off|touch on|off|level|restore|toggle|log|modes|daemon" >&2
        exit 2
        ;;
esac
