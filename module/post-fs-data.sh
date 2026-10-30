#!/system/bin/sh
# 全局高刷 · post-fs-data
MODDIR=${0%/*}
DATA=${HFR_DATA:-/data/adb/global_hfr}

mkdir -p "$DATA" 2>/dev/null

if [ ! -f "$DATA/config.conf" ] && [ -f "$MODDIR/config/default.conf" ]; then
    cp -f "$MODDIR/config/default.conf" "$DATA/config.conf" 2>/dev/null
fi

# 欧加系 LTPO 兼容属性（可选，默认关闭）
if grep -q '^oplus_props=1' "$DATA/config.conf" 2>/dev/null; then
    brand=$(getprop ro.product.brand)
    case "$brand" in
        OPPO|OnePlus|realme|oplus|OPPO*)
            if command -v resetprop >/dev/null 2>&1; then
                resetprop -n debug.oplus.display.dynamic_fps_switch 0
                resetprop -n vendor.display.enable_optimize_refresh 0
                resetprop -n ro.surface_flinger.use_content_detection_for_refresh_rate false
            fi
            ;;
    esac
fi
