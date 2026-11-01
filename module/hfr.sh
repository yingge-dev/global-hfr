#!/system/bin/sh
# ============================================================
#  Global HFR Engine v2  (author: yingge)
#  device detect / mode scan / fixed lock / native+adaptive dynamic
#  touch boost / cached status / boot daemon / config persist
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
DEV=$DATA/device.conf
PANEL=$DATA/panel.conf
TOUCHJSON=$DATA/touch.json
LOG=$DATA/run.log
ORIG=$DATA/orig.conf
TOUCHBAK=$DATA/touch.backup
TOUCHSTATE=$DATA/touch.state
TOUCHSIG=$DATA/touch.sig
REV=$DATA/rev
SFLAG=$DATA/sf_override
KEYSBAK=$DATA/keys.backup

PATH=/system/bin:/system/xbin:/vendor/bin:/sbin:$PATH
export PATH
umask 022

TAB=$(printf '\t')
is_num() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}
VER=""; VC=""
if [ -f "$MODDIR/module.prop" ]; then
    while IFS='=' read -r k v; do
        case "$k" in
            version) VER=$v ;;
            versionCode) VC=$v ;;
        esac
    done < "$MODDIR/module.prop"
fi
[ -n "$VER" ] || VER=v2.1.0
is_num "$VC" || VC=20100

[ -d "$DATA" ] || mkdir -p "$DATA" 2>/dev/null

# ------------------------------------------------------------
#  helpers
# ------------------------------------------------------------
log() {
    [ -d "$DATA" ] || return 0
    if [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null)" -gt 131072 ] 2>/dev/null; then
        tail -n 300 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG" 2>/dev/null
    fi
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null
}

now() { date +%s; }

jesc() {
    v=$1
    v=${v//\"/}
    v=${v//\\/}
    v=${v//$'\r'/}
    v=${v//$'\n'/}
    v=${v//$'\t'/}
    printf '%s' "$v"
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
        sleep 0.5
    done
    log "settings put $ns/$key=$val failed"
    return 1
}

del_setting() {
    settings delete "$1" "$2" >/dev/null 2>&1
}

# ------------------------------------------------------------
#  config
# ------------------------------------------------------------
profile=fixed
fixed_hz=0
dyn_min=60
dyn_max=0
dyn_engine=auto
dyn_idle_ms=3000
touch=1
touch_level=standard
deep_lock=1
overlay=0
daemon=1
auto_boot=1
oplus_props=0
sampling=0

target_hz=0
verified=0
method=""
engine=""
touch_applied=0
sampling_applied=0
sampling_method=""
restart_required=0

FAMILY_CACHE=""
CAN_SF=0
CAN_CMD=0
VENDOR_KEYS=""
ADAPT_KIND=""

load_conf() {
    profile=fixed; fixed_hz=0; dyn_min=60; dyn_max=0
    dyn_engine=auto; dyn_idle_ms=3000
    touch=1; touch_level=standard; deep_lock=1; overlay=0
    daemon=1; auto_boot=1; oplus_props=0; sampling=0
    [ -f "$CONF" ] || return 0
    while IFS='=' read -r k v; do
        v=${v// /}
        v=${v//$'\t'/}
        v=${v//$'\r'/}
        case "$k" in
            profile) case "$v" in fixed|dynamic|off) profile=$v ;; esac ;;
            fixed_hz) is_num "$v" && fixed_hz=$v ;;
            dyn_min) is_num "$v" && dyn_min=$v ;;
            dyn_max) is_num "$v" && dyn_max=$v ;;
            dyn_engine) case "$v" in auto|native|adaptive) dyn_engine=$v ;; esac ;;
            dyn_idle_ms) is_num "$v" && [ "$v" -ge 1000 ] 2>/dev/null && dyn_idle_ms=$v ;;
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

set_conf() {
    k=$1; v=$2
    case "$k" in
        profile) case "$v" in fixed|dynamic|off) ;; *) return 2 ;; esac ;;
        fixed_hz|dyn_min|dyn_max) is_num "$v" || return 2 ;;
        dyn_engine) case "$v" in auto|native|adaptive) ;; *) return 2 ;; esac ;;
        dyn_idle_ms) is_num "$v" && [ "$v" -ge 1000 ] 2>/dev/null || return 2 ;;
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
#  device info
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

device_family() {
    b=$(prop ro.product.brand)
    case "$b" in
        Xiaomi|Redmi|POCO|xiaomi|redmi|poco) echo "xiaomi"; return ;;
        OPPO|OnePlus|realme|oplus|OPPO*) echo "oplus"; return ;;
    esac
    if [ -n "$(prop ro.mi.os.version.name)" ] || [ -n "$(prop ro.miui.ui.version.name)" ]; then
        echo "xiaomi"; return
    fi
    echo "aosp"
}

cache_device() {
    fam=$(device_family)
    {
        echo "brand=$(prop ro.product.brand)"
        echo "model=$(prop ro.product.model)"
        echo "market=$(device_market)"
        echo "rom=$(rom_name)"
        echo "android=$(prop ro.build.version.release)"
        echo "sdk=$(prop ro.build.version.sdk)"
        echo "soc=$(prop ro.soc.model)"
        echo "platform=$(platform_name)"
        echo "family=$fam"
        detect_caps "$fam"
    } > "$DEV.tmp" 2>/dev/null && mv -f "$DEV.tmp" "$DEV" 2>/dev/null
}

dev_get() {
    if [ -f "$DEV" ]; then
        v=$(sed -n "s/^$1=//p" "$DEV" 2>/dev/null | head -n 1)
        [ -n "$v" ] && { printf '%s' "$v"; return; }
    fi
    case "$1" in
        brand) prop ro.product.brand ;;
        model) prop ro.product.model ;;
        market) device_market ;;
        rom) rom_name ;;
        android) prop ro.build.version.release ;;
        sdk) prop ro.build.version.sdk ;;
        soc) prop ro.soc.model ;;
        platform) platform_name ;;
        family) device_family ;;
    esac
}

detect_caps() {
    fam=${1:-$(device_family)}
    can_sf=0
    can_cmd=0
    keys=""
    case "$fam" in
        xiaomi) can_sf=1 ;;
    esac
    if command -v cmd >/dev/null 2>&1 && cmd display help 2>/dev/null | grep -q 'set-user-preferred-display-mode'; then
        can_cmd=1
    fi
    for spec in secure:miui_refresh_rate system:oplus_screen_refresh_rate \
                system:oneplus_screen_refresh_rate secure:oplus_refresh_rate \
                system:realme_screen_refresh_rate system:smart_refresh_rate; do
        ns=${spec%%:*}; key=${spec#*:}
        v=$(settings get "$ns" "$key" 2>/dev/null | tr -d '\r\n')
        if [ -n "$v" ] && [ "$v" != "null" ]; then
            keys="$keys $spec"
        fi
    done
    printf 'can_sf=%s\ncan_cmd=%s\nkeys=%s\n' "$can_sf" "$can_cmd" "$keys"
}

ensure_caps() {
    [ -f "$DEV" ] || return 0
    has=0
    while IFS='=' read -r k v; do
        [ "$k" = "can_sf" ] && has=1
    done < "$DEV"
    if [ "$has" = "0" ]; then
        detect_caps >> "$DEV" 2>/dev/null
    fi
}

caps_load() {
    FAMILY_CACHE=""
    CAN_SF=0
    CAN_CMD=0
    VENDOR_KEYS=""
    if [ -f "$DEV" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                family) FAMILY_CACHE=$v ;;
                can_sf) CAN_SF=$v ;;
                can_cmd) CAN_CMD=$v ;;
                keys) VENDOR_KEYS=$v ;;
            esac
        done < "$DEV"
    fi
    [ -n "$FAMILY_CACHE" ] || FAMILY_CACHE=$(dev_get family)
    if [ -n "$HFR_FORCE_FAMILY" ]; then
        FAMILY_CACHE=$HFR_FORCE_FAMILY
        [ "$FAMILY_CACHE" = "xiaomi" ] || CAN_SF=0
    fi
    [ -n "$HFR_FORCE_NO_SF" ] && CAN_SF=0
    case "$CAN_SF" in 0|1) ;; *) CAN_SF=0 ;; esac
    case "$CAN_CMD" in 0|1) ;; *) CAN_CMD=0 ;; esac
}

set_vendor_keys() {
    val=$1
    for spec in $VENDOR_KEYS; do
        ns=${spec%%:*}; key=${spec#*:}
        settings put "$ns" "$key" "$val" >/dev/null 2>&1 &
    done
}

backup_vendor_keys() {
    [ -f "$KEYSBAK" ] && return 0
    [ -n "$VENDOR_KEYS" ] || return 0
    : > "$KEYSBAK" 2>/dev/null
    for spec in $VENDOR_KEYS; do
        ns=${spec%%:*}; key=${spec#*:}
        v=$(settings get "$ns" "$key" 2>/dev/null | tr -d '\r\n')
        printf '%s=%s\n' "$spec" "$v" >> "$KEYSBAK" 2>/dev/null
    done
}

restore_vendor_keys() {
    [ -f "$KEYSBAK" ] || return 0
    while IFS='=' read -r spec v; do
        [ -n "$spec" ] || continue
        ns=${spec%%:*}; key=${spec#*:}
        case "$v" in
            ''|null) del_setting "$ns" "$key" ;;
            *) put_setting "$ns" "$key" "$v" ;;
        esac
    done < "$KEYSBAK"
    rm -f "$KEYSBAK"
}

# ------------------------------------------------------------
#  modes
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
        mx=$(awk -F'\t' 'BEGIN{m=0} {if ($4+0 > m) m=$4+0} END{if (m>0) printf "%.0f", m}' "$MODES" 2>/dev/null)
        nm=$(dumpsys display 2>/dev/null | sed -n 's/.*mLockedMaxRefreshRate: \([0-9.]*\).*/\1/p' | head -n 1)
        nm=${nm%%.*}
        is_num "$nm" || nm=0
        [ "$nm" -le 60 ] 2>/dev/null && nm=$mx
        [ "$nm" -gt "$mx" ] 2>/dev/null && nm=$mx
        printf 'max=%s\nnative=%s\n' "${mx:-0}" "${nm:-$mx}" > "$PANEL" 2>/dev/null
        log "scan modes: $(wc -l < "$MODES") native=${nm:-$mx}"
        return 0
    fi
    rm -f "$MODES.tmp"
    return 1
}

ensure_panel() {
    if [ -f "$PANEL" ]; then
        has_native=0
        while IFS='=' read -r k v; do
            [ "$k" = "native" ] && has_native=1
        done < "$PANEL"
        if [ "$has_native" = "0" ] && [ -s "$MODES" ]; then
            nm=$(dumpsys display 2>/dev/null | sed -n 's/.*mLockedMaxRefreshRate: \([0-9.]*\).*/\1/p' | head -n 1)
            nm=${nm%%.*}
            is_num "$nm" || nm=0
            mx=$(awk -F'\t' 'BEGIN{m=0} {if ($4+0 > m) m=$4+0} END{if (m>0) printf "%.0f", m}' "$MODES" 2>/dev/null)
            [ "$nm" -le 60 ] 2>/dev/null && nm=$mx
            [ "$nm" -gt "$mx" ] 2>/dev/null && nm=$mx
            echo "native=${nm:-$mx}" >> "$PANEL" 2>/dev/null
        fi
        return 0
    fi
    [ -s "$MODES" ] || return 1
    mx=$(awk -F'\t' 'BEGIN{m=0} {if ($4+0 > m) m=$4+0} END{if (m>0) printf "%.0f", m}' "$MODES" 2>/dev/null)
    printf 'max=%s\nnative=%s\n' "${mx:-0}" "${mx:-0}" > "$PANEL" 2>/dev/null
}

ensure_modes() {
    if [ -s "$MODES" ]; then
        ensure_panel
        return 0
    fi
    scan_modes
}

max_hz() {
    if [ -f "$PANEL" ]; then
        while IFS='=' read -r k v; do
            if [ "$k" = "max" ]; then
                is_num "$v" && [ "$v" -gt 0 ] 2>/dev/null && { printf '%s\n' "$v"; return 0; }
            fi
        done < "$PANEL"
    fi
    [ -s "$MODES" ] || return 1
    awk -F'\t' 'BEGIN{m=0} {if ($4+0 > m) m = $4+0} END{if (m > 0) printf "%.0f\n", m}' "$MODES" 2>/dev/null
}

native_max() {
    if [ -f "$PANEL" ]; then
        while IFS='=' read -r k v; do
            if [ "$k" = "native" ]; then
                is_num "$v" && [ "$v" -gt 60 ] 2>/dev/null && { printf '%s\n' "$v"; return 0; }
            fi
        done < "$PANEL"
    fi
    max_hz
}

refresh_native_cap() {
    [ -s "$MODES" ] || return 1
    mx=$(max_hz); [ -n "$mx" ] || return 1
    nm=$(dumpsys display 2>/dev/null | sed -n 's/.*mLockedMaxRefreshRate: \([0-9.]*\).*/\1/p' | head -n 1)
    nm=${nm%%.*}
    is_num "$nm" || nm=0
    [ "$nm" -le 60 ] 2>/dev/null && nm=$mx
    [ "$nm" -gt "$mx" ] 2>/dev/null && nm=$mx
    printf 'max=%s\nnative=%s\n' "$mx" "${nm:-$mx}" > "$PANEL" 2>/dev/null
}

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

mode_wh() {
    [ -s "$MODES" ] || return 1
    awk -F'\t' -v i="$1" '$1 == i {printf "%s %s\n", $2, $3; exit}' "$MODES" 2>/dev/null
}

# ------------------------------------------------------------
#  display control
# ------------------------------------------------------------
sf_set() {
    out=$(service call SurfaceFlinger 1035 i32 "$1" 2>&1)
    case "$out" in
        *Exception*|*Error*|*error*|*Failed*|*"Invalid argument"*) return 1 ;;
    esac
    return 0
}

backup_orig() {
    if [ ! -f "$ORIG" ]; then
        {
            echo "peak=$(settings get system peak_refresh_rate 2>/dev/null | tr -d '\r\n')"
            echo "min=$(settings get system min_refresh_rate 2>/dev/null | tr -d '\r\n')"
            echo "user=$(settings get system user_refresh_rate 2>/dev/null | tr -d '\r\n')"
            echo "miui=$(settings get secure miui_refresh_rate 2>/dev/null | tr -d '\r\n')"
        } > "$ORIG" 2>/dev/null
    elif ! grep -q '^miui=' "$ORIG" 2>/dev/null; then
        echo "miui=$(settings get secure miui_refresh_rate 2>/dev/null | tr -d '\r\n')" >> "$ORIG" 2>/dev/null
    fi
    backup_vendor_keys
}

restore_orig() {
    if [ ! -f "$ORIG" ]; then
        del_setting system peak_refresh_rate
        del_setting system min_refresh_rate
        del_setting system user_refresh_rate
        return 0
    fi
    peak=$(sed -n 's/^peak=//p' "$ORIG" | head -n 1)
    min=$(sed -n 's/^min=//p' "$ORIG" | head -n 1)
    user=$(sed -n 's/^user=//p' "$ORIG" | head -n 1)
    miui=$(sed -n 's/^miui=//p' "$ORIG" | head -n 1)
    case "$peak" in
        ''|null) del_setting system peak_refresh_rate ;;
        *) put_setting system peak_refresh_rate "$peak" ;;
    esac
    case "$min" in
        ''|null) del_setting system min_refresh_rate ;;
        *) put_setting system min_refresh_rate "$min" ;;
    esac
    case "$user" in
        ''|null) del_setting system user_refresh_rate ;;
        *) put_setting system user_refresh_rate "$user" ;;
    esac
    if [ -n "$miui" ]; then
        case "$miui" in
            null) del_setting secure miui_refresh_rate ;;
            *) put_setting secure miui_refresh_rate "$miui" ;;
        esac
    fi
    restore_vendor_keys
    rm -f "$ORIG"
    log "restore orig peak=$peak min=$min"
}

apply_native_range() {
    lo=$1; hi=$2
    backup_orig
    settings put system min_refresh_rate "$lo" >/dev/null 2>&1 &
    settings put system peak_refresh_rate "$hi" >/dev/null 2>&1 &
    settings delete system user_refresh_rate >/dev/null 2>&1 &
    set_vendor_keys "$hi"
    wait
    log "native range $lo-$hi"
}

read_active_hz() {
    v=$(dumpsys SurfaceFlinger 2>/dev/null | sed -n 's/.*activeMode=.*vsyncRate=\([0-9.]*\) Hz.*/\1/p' | head -n 1)
    if [ -z "$v" ]; then
        v=$(dumpsys display 2>/dev/null | sed -n 's/.*mActiveSfDisplayMode=.*vsyncRate=\([0-9.]*\).*/\1/p' | head -n 1)
    fi
    case "$v" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    awk -v x="$v" 'BEGIN{printf "%.0f\n", x}' 2>/dev/null
}

apply_fixed_mode() {
    t=$1
    is_num "$t" || t=0
    if [ "$t" -eq 0 ]; then t=$(max_hz); fi
    [ -n "$t" ] || t=120
    set -- $(pick_mode "$t")
    mid=$1; mhz=$2
    if [ -z "$mid" ]; then
        method="未检测到 ${t}Hz 档位"
        log "$method"
        return 1
    fi
    backup_orig
    settings put system min_refresh_rate "$mhz" >/dev/null 2>&1 &
    settings put system peak_refresh_rate "$mhz" >/dev/null 2>&1 &
    settings put system user_refresh_rate "$mhz" >/dev/null 2>&1 &
    set_vendor_keys "$mhz"
    wait
    target_hz=$mhz
    method="Settings ${mhz}Hz"
    verified=0

    # Xiaomi / HyperOS: the vendor backdoor is the only reliable hard lock.
    if [ "$deep_lock" = "1" ] && [ "$CAN_SF" = "1" ]; then
        if sf_set "$mid"; then
            method="SurfaceFlinger mode $mid"
            : > "$SFLAG" 2>/dev/null
            verified=1
            return 0
        fi
    fi

    # Generic path: DisplayManager user preferred mode first.
    wh=$(mode_wh "$mid")
    if [ "$CAN_CMD" = "1" ] && [ -n "$wh" ]; then
        cmd display set-user-preferred-display-mode $wh "$mhz" 0 0 >/dev/null 2>&1
        sleep 0.45
        c=$(read_active_hz)
        if [ -n "$c" ] && [ $((c - mhz)) -le 2 ] 2>/dev/null && [ $((mhz - c)) -le 2 ] 2>/dev/null; then
            method="DisplayManager ${mhz}Hz"
            verified=1
            return 0
        fi
    fi

    # Last vendor fallback, only when capability is known.
    if [ "$deep_lock" = "1" ] && [ "$CAN_SF" = "1" ]; then
        if sf_set "$mid"; then
            method="SurfaceFlinger mode $mid"
            : > "$SFLAG" 2>/dev/null
            verified=1
            return 0
        fi
    fi

    # Verify the plain settings range; some AOSP ROMs honor min=peak.
    sleep 0.35
    c=$(read_active_hz)
    if [ -n "$c" ] && [ $((c - mhz)) -le 2 ] 2>/dev/null && [ $((mhz - c)) -le 2 ] 2>/dev/null; then
        method="Settings ${mhz}Hz"
        verified=1
    else
        method="兼容模式 ${mhz}Hz（系统未确认）"
        verified=0
    fi
    return 0
}

apply_dynamic_mode() {
    lo=$dyn_min; hi=$dyn_max
    is_num "$lo" || lo=60
    pmax=$(max_hz); [ -n "$pmax" ] || pmax=120
    nmax=$(native_max); [ -n "$nmax" ] || nmax=$pmax
    if ! is_num "$hi" || [ "$hi" -eq 0 ]; then hi=$pmax; fi
    [ "$hi" -gt "$pmax" ] && hi=$pmax
    [ "$hi" -le "$lo" ] && hi=$((lo + 30))
    set -- $(pick_mode "$lo"); lo_id=$1; lo_hz=$2
    set -- $(pick_mode "$hi"); hi_id=$1; hi_hz=$2
    [ -n "$lo_id" ] || lo_id=$hi_id
    [ -n "$lo_hz" ] || lo_hz=$lo
    if [ -z "$hi_id" ]; then
        method="未检测到 ${hi}Hz 档位"
        return 1
    fi
    [ -n "$hi_hz" ] || hi_hz=$hi

    eng=$dyn_engine
    if [ "$eng" = "auto" ]; then
        if [ -f "$SFLAG" ]; then
            eng="adaptive"
        elif [ "$FAMILY_CACHE" = "xiaomi" ] && [ "$nmax" -lt "$pmax" ] && [ "$hi_hz" -gt "$nmax" ]; then
            eng="adaptive"
        else
            eng="native"
        fi
    fi

    capnote=""
    if [ "$eng" = "native" ]; then
        if [ "$lo_hz" -ge "$nmax" ] && [ "$nmax" -lt "$pmax" ]; then
            eng="adaptive"
        elif [ "$hi_hz" -gt "$nmax" ]; then
            hi_hz=$nmax
            set -- $(pick_mode "$hi_hz"); hi_id=$1; hi_hz=$2
            [ -n "$hi_id" ] || hi_id=$lo_id
            capnote="（系统上限 ${nmax}Hz）"
        fi
    fi

    apply_native_range "$lo_hz" "$hi_hz"
    target_hz=$hi_hz
    verified=1

    if [ "$eng" = "adaptive" ] && [ -n "$lo_id" ] && [ -n "$hi_id" ] && [ "$lo_id" != "$hi_id" ]; then
        engine="adaptive"
        if [ "$CAN_SF" = "1" ] && [ "$FAMILY_CACHE" = "xiaomi" ]; then
            ADAPT_KIND="sf"
            method="自适应 ${lo_hz}-${hi_hz}Hz"
            if sf_set "$hi_id" >/dev/null 2>&1; then
                : > "$SFLAG" 2>/dev/null
            else
                ADAPT_KIND="settings"
                method="自适应 ${lo_hz}-${hi_hz}Hz（设置）"
                settings put system min_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                wait
            fi
        else
            ADAPT_KIND="settings"
            method="自适应 ${lo_hz}-${hi_hz}Hz（设置）"
            settings put system min_refresh_rate "$hi_hz" >/dev/null 2>&1 &
            settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
            wait
        fi
    else
        engine="native"
        if [ -f "$SFLAG" ]; then
            method="原生动态 ${lo_hz}-${hi_hz}Hz · 重启后生效"
            verified=0
            restart_required=1
        else
            method="原生动态 ${lo_hz}-${hi_hz}Hz${capnote}"
        fi
    fi
    return 0
}

apply_display() {
    method=""; verified=0; target_hz=0; engine=""
    case "$profile" in
        off)
            [ "${FAMILY_CACHE:-$(dev_get family)}" = "xiaomi" ] && sf_set 0 >/dev/null 2>&1
            restore_orig
            method="系统默认"
            verified=1
            ;;
        dynamic)
            apply_dynamic_mode
            ;;
        *)
            apply_fixed_mode "$fixed_hz"
            ;;
    esac
    return 0
}

# ------------------------------------------------------------
#  touch
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
    if printf '%s' "8 3007 $sampling 1" > "$node" 2>/dev/null; then
        sampling_applied=1
        sampling_method="thp $sampling"
        log "sampling ${sampling}Hz -> $node"
        return 0
    fi
    log "sampling write failed -> $node"
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
    rm -f "$TOUCHSTATE" "$TOUCHSIG"
    printf '[]' > "$TOUCHJSON" 2>/dev/null
    touch_applied=0
}

apply_touch() {
    touch_applied=0
    restore_touch
    : > "$TOUCHSTATE" 2>/dev/null
    : > "$TOUCHJSON.tmp" 2>/dev/null
    jfirst=1

    if [ "$touch" = "1" ]; then
        while IFS='|' read -r name p on off; do
            [ -n "$name" ] || continue
            exists=0
            [ -e "$p" ] && exists=1
            ok=0
            skip=0
            case "$name" in
                x_*) [ "$touch_level" = "esports" ] || skip=1 ;;
            esac
            if [ "$exists" = "1" ] && [ "$skip" = "0" ]; then
                backup_touch_node "$p"
                if write_node "$p" "$on"; then
                    printf '%s|%s|1|%s\n' "$name" "$p" "$on" >> "$TOUCHSTATE"
                    touch_applied=$((touch_applied + 1))
                    ok=1
                else
                    printf '%s|%s|0|%s\n' "$name" "$p" "$on" >> "$TOUCHSTATE"
                fi
            fi
            [ "$jfirst" = "1" ] || printf ',' >> "$TOUCHJSON.tmp"
            jfirst=0
            printf '{"name":"%s","path":"%s","exists":%s,"ok":%s}' "$(jesc "$name")" "$(jesc "$p")" "$exists" "$ok" >> "$TOUCHJSON.tmp"
        done <<EOF
$TOUCH_SPEC
EOF

        if [ "$touch_level" = "esports" ]; then prio=-15; else prio=-8; fi
        n=$(renice_touch "$prio")
        if [ "$n" -gt 0 ] 2>/dev/null; then
            printf 'renice|touch HAL|1|%s\n' "$prio" >> "$TOUCHSTATE"
            touch_applied=$((touch_applied + 1))
            [ "$jfirst" = "1" ] || printf ',' >> "$TOUCHJSON.tmp"
            jfirst=0
            printf '{"name":"renice","path":"touch HAL","exists":1,"ok":1}' >> "$TOUCHJSON.tmp"
        fi
        apply_sampling
        [ "$sampling_applied" = "1" ] && touch_applied=$((touch_applied + 1))
        log "touch level=$touch_level applied=$touch_applied renice=$n sampling=$sampling"
    fi
    mv -f "$TOUCHJSON.tmp" "$TOUCHJSON" 2>/dev/null
}

# ------------------------------------------------------------
#  state
# ------------------------------------------------------------
write_state() {
    cur=$1
    [ -n "$cur" ] || cur=${target_hz:-0}
    {
        echo "ts=$(now)"
        echo "profile=$profile"
        echo "engine=$engine"
        echo "target=$target_hz"
        echo "current=$cur"
        echo "verified=$verified"
        echo "method=$method"
        echo "touch_applied=$touch_applied"
        echo "sampling_applied=$sampling_applied"
        echo "sampling_method=$sampling_method"
        echo "restart_required=$restart_required"
    } > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
}

read_state() {
    st_ts=0; st_profile=""; st_engine=""; st_target=0; st_cur=0
    st_ver=0; st_method=""; st_touch=0; st_sampling=0; st_restart=0
    [ -f "$STATE" ] || return 0
    while IFS='=' read -r k v; do
        case "$k" in
            ts) is_num "$v" && st_ts=$v ;;
            profile) st_profile=$v ;;
            engine) st_engine=$v ;;
            target) is_num "$v" && st_target=$v ;;
            current) is_num "$v" && st_cur=$v ;;
            verified) is_num "$v" && st_ver=$v ;;
            method) st_method=$v ;;
            touch_applied) is_num "$v" && st_touch=$v ;;
            sampling_applied) is_num "$v" && st_sampling=$v ;;
            restart_required) is_num "$v" && st_restart=$v ;;
        esac
    done < "$STATE"
}

apply_all() {
    ensure_modes
    restart_required=0
    apply_display
    t_sig="$touch|$touch_level|$sampling"
    if [ -s "$TOUCHSTATE" ] && [ -s "$TOUCHJSON" ] && [ "$(cat "$TOUCHSIG" 2>/dev/null)" = "$t_sig" ]; then
        touch_applied=0
        while IFS='|' read -r _tn _tp _tok _tv; do
            [ "$_tok" = "1" ] && touch_applied=$((touch_applied + 1))
        done < "$TOUCHSTATE"
    else
        apply_touch
        printf '%s' "$t_sig" > "$TOUCHSIG" 2>/dev/null
    fi
    if [ "$overlay" = "1" ]; then
        service call SurfaceFlinger 1034 i32 1 >/dev/null 2>&1
    else
        service call SurfaceFlinger 1034 i32 0 >/dev/null 2>&1
    fi
    write_state "$target_hz"
    log "apply profile=$profile engine=$engine target=$target_hz method=$method"
}

restore_all() {
    restart_required=0
    if [ "${FAMILY_CACHE:-$(dev_get family)}" = "xiaomi" ] && [ "$CAN_SF" = "1" ]; then
        sf_set 0 >/dev/null 2>&1
        restart_required=1
    fi
    rm -f "$SFLAG"
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
    engine=""
    method="已恢复系统默认（重启后完全生效）"
    write_state 0
    log "restore all"
}

json_status() {
    load_conf
    read_state
    cur=$st_cur
    if ! is_num "$cur" || [ "$cur" -le 0 ] 2>/dev/null; then cur=$st_target; fi
    [ "$profile" = "off" ] && cur=0
    mx=0
    if [ -f "$PANEL" ]; then
        while IFS='=' read -r k v; do
            [ "$k" = "max" ] && mx=$v
        done < "$PANEL"
    fi
    is_num "$mx" || mx=0

    d_brand=""; d_model=""; d_market=""; d_rom=""; d_android=""; d_sdk=""; d_soc=""; d_platform=""; d_family=""
    if [ -f "$DEV" ]; then
        while IFS='=' read -r k v; do
            case "$k" in
                brand) d_brand=$v ;;
                model) d_model=$v ;;
                market) d_market=$v ;;
                rom) d_rom=$v ;;
                android) d_android=$v ;;
                sdk) d_sdk=$v ;;
                soc) d_soc=$v ;;
                platform) d_platform=$v ;;
                family) d_family=$v ;;
            esac
        done < "$DEV"
    fi
    d_brand=${d_brand//\"/}; d_brand=${d_brand//\\/}
    d_model=${d_model//\"/}; d_model=${d_model//\\/}
    d_market=${d_market//\"/}; d_market=${d_market//\\/}
    d_rom=${d_rom//\"/}; d_rom=${d_rom//\\/}
    d_android=${d_android//\"/}; d_android=${d_android//\\/}
    d_sdk=${d_sdk//\"/}; d_sdk=${d_sdk//\\/}
    d_soc=${d_soc//\"/}; d_soc=${d_soc//\\/}
    d_platform=${d_platform//\"/}; d_platform=${d_platform//\\/}
    d_family=${d_family//\"/}; d_family=${d_family//\\/}
    st_method=${st_method//\"/}; st_method=${st_method//\\/}
    st_engine=${st_engine//\"/}; st_engine=${st_engine//\\/}

    printf '{"ok":1,"ts":%s,"version":"%s","versionCode":%s,' "$(now)" "$VER" "$VC"
    printf '"device":{"brand":"%s","model":"%s","market":"%s","rom":"%s","android":"%s","sdk":%s,"soc":"%s","platform":"%s","family":"%s"},' \
        "$d_brand" "$d_model" "$d_market" "$d_rom" "$d_android" "$d_sdk" "$d_soc" "$d_platform" "$d_family"

    nmax=$(native_max); [ -n "$nmax" ] || nmax=$mx
    printf '"panel":{"max":%s,"nativeMax":%s,"modes":[' "$mx" "$nmax"
    first=1
    if [ -s "$MODES" ]; then
        while read -r line; do
            set -- $line
            [ -n "$1" ] || continue
            [ "$first" = "1" ] || printf ','
            first=0
            printf '{"id":%s,"w":%s,"h":%s,"hz":%s}' "$1" "${2:-0}" "${3:-0}" "${4:-0}"
        done < "$MODES"
    fi
    printf ']},'

    adapt_kind="settings"
    [ "$CAN_SF" = "1" ] && [ "$d_family" = "xiaomi" ] && adapt_kind="sf"
    printf '"caps":{"can_sf":%s,"can_cmd":%s,"adapt":"%s","keys":"%s"},' "$CAN_SF" "$CAN_CMD" "$adapt_kind" "$VENDOR_KEYS"

    printf '"config":{"profile":"%s","fixed_hz":%s,"dyn_min":%s,"dyn_max":%s,"dyn_engine":"%s","dyn_idle_ms":%s,"touch":%s,"touch_level":"%s","sampling":%s,"deep_lock":%s,"overlay":%s,"daemon":%s,"auto_boot":%s,"oplus_props":%s},' \
        "$profile" "$fixed_hz" "$dyn_min" "$dyn_max" "$dyn_engine" "$dyn_idle_ms" "$touch" "$touch_level" "$sampling" "$deep_lock" "$overlay" "$daemon" "$auto_boot" "$oplus_props"

    printf '"live":{"current":%s,"target":%s,"verified":%s,"method":"%s","engine":"%s","updated":%s,"restart_required":%s},' \
        "$cur" "$st_target" "$st_ver" "$st_method" "$st_engine" "$st_ts" "$st_restart"

    sampling_node_path=""
    for p in $SAMPLING_NODES; do
        [ -e "$p" ] && { sampling_node_path=$p; break; }
    done
    sampling_exists=0
    [ -n "$sampling_node_path" ] && sampling_exists=1
    printf '"sampling":{"value":%s,"exists":%s,"applied":%s,"path":"%s"},' "$sampling" "$sampling_exists" "$st_sampling" "$sampling_node_path"

    printf '"touch":{"enabled":%s,"level":"%s","applied":%s,"nodes":[' "$touch" "$touch_level" "$st_touch"
    cat "$TOUCHJSON" 2>/dev/null
    printf ']}}\n'
}

apply_json() {
    m=${method//\"/}; m=${m//\\/}
    printf '{"ok":1,"profile":"%s","engine":"%s","target":%s,"current":%s,"verified":%s,"method":"%s","touch_applied":%s,"sampling":%s,"sampling_applied":%s,"restart_required":%s}\n' \
        "$profile" "$engine" "${target_hz:-0}" "${target_hz:-0}" "${verified:-0}" "$m" "${touch_applied:-0}" "$sampling" "$sampling_applied" "${restart_required:-0}"
}

cmd_brief() {
    load_conf
    read_state
    cur=$st_cur
    [ -n "$cur" ] || cur=$st_target
    case "$profile" in
        fixed) pdesc="全局锁定 ${st_target}Hz" ;;
        dynamic)
            dyn_hi=$dyn_max
            if ! [ "$dyn_hi" -gt 0 ] 2>/dev/null; then dyn_hi=$(max_hz); fi
            [ -n "$dyn_hi" ] || dyn_hi=120
            if [ "$st_engine" = "adaptive" ]; then pdesc="自适应动态 ${dyn_min}-${dyn_hi}Hz"; else pdesc="原生动态 ${dyn_min}-${dyn_hi}Hz"; fi
            ;;
        off) pdesc="系统默认（未接管）" ;;
        *) pdesc=$profile ;;
    esac
    echo "真·全局高刷 $VER · 作者 颖哥"
    echo "机型：$(dev_get market) ($(dev_get model))"
    echo "系统：$(dev_get rom) / Android $(dev_get android)"
    echo "配置：$pdesc · 触控 $([ "$touch" = "1" ] && echo "开启($touch_level)" || echo 关闭)"
    echo "当前：${cur:-未知}Hz · $([ "$st_ver" = "1" ] && echo "已核验" || echo "待核验")"
    echo "方式：${st_method:-未应用}"
}

# ------------------------------------------------------------
#  adaptive dynamic (activity based)
# ------------------------------------------------------------
read_power() {
    out=$(dumpsys power 2>/dev/null)
    wake=$(printf '%s\n' "$out" | sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' | head -n 1)
    act=$(printf '%s\n' "$out" | sed -n 's/.*mLastUserActivityTime(excludingAttention)=\([0-9]*\).*/\1/p' | head -n 1)
    [ -n "$act" ] || act=$(printf '%s\n' "$out" | sed -n 's/.*mLastUserActivityTime=\([0-9]*\).*/\1/p' | head -n 1)
    [ -n "$wake" ] || wake=Unknown
}

adaptive_loop() {
    load_conf
    [ "$profile" = "dynamic" ] || return 0
    case "$dyn_engine" in
        adaptive) ;;
        auto) [ "$engine" = "adaptive" ] || return 0 ;;
        *) return 0 ;;
    esac
    lo=$dyn_min; hi=$dyn_max
    if ! is_num "$hi" || [ "$hi" -eq 0 ]; then hi=$(max_hz); fi
    [ -n "$hi" ] || hi=120
    [ "$hi" -le "$lo" ] && hi=$((lo + 30))
    set -- $(pick_mode "$lo"); lo_id=$1; lo_hz=$2
    set -- $(pick_mode "$hi"); hi_id=$1; hi_hz=$2
    if [ -z "$lo_id" ] || [ -z "$hi_id" ] || [ "$lo_id" = "$hi_id" ]; then
        log "adaptive: no modes ${lo}-${hi}"
        dyn_engine=native
        save_conf_key dyn_engine native
        return 1
    fi
    idle_s=$((dyn_idle_ms / 1000))
    [ "$idle_s" -ge 1 ] 2>/dev/null || idle_s=3
    if [ "$ADAPT_KIND" = "settings" ]; then
        adapt_kind="settings"
    elif [ "$CAN_SF" = "1" ] && [ "$FAMILY_CACHE" = "xiaomi" ]; then
        adapt_kind="sf"
    else
        adapt_kind="settings"
    fi
    ADAPT_KIND=$adapt_kind
    cur_id=$hi_id
    if [ "$adapt_kind" = "settings" ]; then
        settings put system min_refresh_rate "$hi_hz" >/dev/null 2>&1 &
        settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
        wait
        method="自适应 ${lo_hz}-${hi_hz}Hz（设置）"
    else
        sf_set "$hi_id" >/dev/null 2>&1
        method="自适应 ${lo_hz}-${hi_hz}Hz"
    fi
    target_hz=$hi_hz
    engine="adaptive"
    verified=1
    last_act=""
    last_active=$(now)
    last_rev=$(cat "$REV" 2>/dev/null)
    log "adaptive start ${lo_hz}-${hi_hz} kind=$adapt_kind idle=${idle_s}s"
    tick=0

    while :; do
        tick=$((tick + 1))
        if [ $((tick % 5)) -eq 0 ]; then
            rev=$(cat "$REV" 2>/dev/null)
            if [ "$rev" != "$last_rev" ]; then
                log "adaptive: config changed"
                return 2
            fi
        fi
        read_power
        t=$(now)
        if [ "$wake" = "Awake" ]; then
            if [ -z "$last_act" ]; then
                last_act=$act
                last_active=$t
            elif [ "$act" != "$last_act" ]; then
                last_act=$act
                last_active=$t
                if [ "$cur_id" != "$hi_id" ]; then
                    if [ "$adapt_kind" = "settings" ]; then
                        settings put system min_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                        settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                        wait
                    else
                        sf_set "$hi_id" >/dev/null 2>&1
                    fi
                    cur_id=$hi_id
                    write_state "$hi_hz"
                fi
            elif [ $((t - last_active)) -ge "$idle_s" ]; then
                if [ "$cur_id" != "$lo_id" ]; then
                    if [ "$adapt_kind" = "settings" ]; then
                        settings put system min_refresh_rate "$lo_hz" >/dev/null 2>&1 &
                        settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                        wait
                    else
                        sf_set "$lo_id" >/dev/null 2>&1
                    fi
                    cur_id=$lo_id
                    write_state "$lo_hz"
                fi
            fi
        else
            if [ "$cur_id" != "$lo_id" ]; then
                if [ "$adapt_kind" = "settings" ]; then
                    settings put system min_refresh_rate "$lo_hz" >/dev/null 2>&1 &
                    settings put system peak_refresh_rate "$hi_hz" >/dev/null 2>&1 &
                    wait
                else
                    sf_set "$lo_id" >/dev/null 2>&1
                fi
                cur_id=$lo_id
                write_state "$lo_hz"
            fi
            sleep 2
            continue
        fi
        sleep 1
    done
}

# ------------------------------------------------------------
#  daemon
# ------------------------------------------------------------
screen_on() {
    w=$(dumpsys power 2>/dev/null | sed -n 's/.*mWakefulness=\([A-Za-z]*\).*/\1/p' | head -n 1)
    case "$w" in
        Asleep|Dozing|Dreaming) return 1 ;;
    esac
    return 0
}

run_daemon() {
    load_conf
    n=0
    while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$n" -lt 150 ]; do
        sleep 1
        n=$((n + 1))
    done
    sleep 2
    refresh_native_cap

    if [ "$auto_boot" = "1" ]; then
        apply_all
    fi
    if [ "$daemon" != "1" ]; then
        log "daemon disabled"
        return 0
    fi

    log "daemon start profile=$profile engine=$dyn_engine"
    last_rev=$(cat "$REV" 2>/dev/null)
    prev_screen="off"
    tick=0
    while :; do
        rev=$(cat "$REV" 2>/dev/null)
        if [ "$rev" != "$last_rev" ]; then
            last_rev=$rev
            load_conf
            apply_all
            tick=0
            if [ "$daemon" != "1" ]; then
                log "daemon disabled"
                return 0
            fi
        fi

        if [ "$profile" = "dynamic" ] && [ "$engine" = "adaptive" ]; then
            adaptive_loop
            load_conf
            apply_all
            last_rev=$(cat "$REV" 2>/dev/null)
            continue
        fi

        sleep 5
        tick=$((tick + 1))
        if screen_on; then
            if [ "$prev_screen" != "on" ]; then
                apply_all
                tick=0
            elif [ "$profile" = "fixed" ] && [ "$((tick % 6))" -eq 0 ]; then
                set -- $(pick_mode "$target_hz")
                [ -n "$1" ] && sf_set "$1" >/dev/null 2>&1
            elif [ "$profile" = "dynamic" ] && [ "$engine" = "native" ] && [ "$((tick % 3))" -eq 0 ]; then
                lo=$dyn_min; hi=$dyn_max
                if ! is_num "$hi" || [ "$hi" -eq 0 ]; then hi=$(max_hz); fi
                [ -n "$hi" ] || hi=120
                [ "$hi" -le "$lo" ] && hi=$((lo + 30))
                apply_native_range "$lo" "$hi"
            fi
            prev_screen=on
        else
            prev_screen=off
            tick=0
        fi
    done
}

# ------------------------------------------------------------
#  entry
# ------------------------------------------------------------
cmd=${1:-status}
load_conf
[ -f "$DEV" ] || cache_device
ensure_caps
caps_load

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
    probe)
        ensure_modes
        mx=$(max_hz); [ -n "$mx" ] || mx=0
        nmax=$(native_max); [ -n "$nmax" ] || nmax=$mx
        act=$(read_active_hz); [ -n "$act" ] || act=0
        adapt_kind="settings"
        [ "$CAN_SF" = "1" ] && [ "${FAMILY_CACHE:-$(dev_get family)}" = "xiaomi" ] && adapt_kind="sf"
        rec="native"
        [ "$nmax" -lt "$mx" ] 2>/dev/null && rec="adaptive"
        printf '{"ok":1,"family":"%s","can_sf":%s,"can_cmd":%s,"keys":"%s","panelMax":%s,"nativeMax":%s,"adapt":"%s","recommend":"%s","active":%s}\n' \
            "$(jesc "$(dev_get family)")" "$CAN_SF" "$CAN_CMD" "$VENDOR_KEYS" "$mx" "$nmax" "$adapt_kind" "$rec" "$act"
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
                if [ -n "$5" ]; then
                    case "$5" in auto|native|adaptive) set_conf dyn_engine "$5" ;; esac
                fi
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
            dynamic)
                set_conf profile dynamic
                [ -n "$3" ] && set_conf dyn_min "$3"
                [ -n "$4" ] && set_conf dyn_max "$4"
                [ -n "$5" ] && set_conf dyn_engine "$5"
                ;;
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
    reboot)
        sync
        svc power reboot 2>/dev/null || reboot
        ;;
    toggle)
        if [ "$profile" = "off" ]; then
            set_conf profile fixed
            set_conf fixed_hz 0
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
        echo "usage: hfr.sh status|probe|scan|apply|switch fixed <hz>|dynamic <lo> <hi> [engine]|off|set <k> <v>|preset|touch|restore|reboot|toggle|log|modes|daemon" >&2
        exit 2
        ;;
esac
