#!/system/bin/sh
# ============================================================
#  Global HFR · install script v2
# ============================================================

if ! command -v ui_print >/dev/null 2>&1; then
    ui_print() { echo "$*"; }
fi
if ! command -v abort >/dev/null 2>&1; then
    abort() { echo "! $*"; exit 1; }
fi
if ! command -v set_perm >/dev/null 2>&1; then
    set_perm() {
        chown "$2:$3" "$1" 2>/dev/null
        chmod "$4" "$1" 2>/dev/null
    }
fi
if ! command -v set_perm_recursive >/dev/null 2>&1; then
    set_perm_recursive() {
        chown -R "$2:$3" "$1" 2>/dev/null
        find "$1" -type d -exec chmod "$4" {} + 2>/dev/null
        find "$1" -type f -exec chmod "$5" {} + 2>/dev/null
    }
fi

[ -n "$MODPATH" ] || MODPATH=$(cd "${0%/*}" 2>/dev/null && pwd)
[ -f "$MODPATH/module.prop" ] || abort "安装包不完整：缺少 module.prop"

MODVER=$(sed -n 's/^version=//p' "$MODPATH/module.prop" | head -n 1)
DATA=${HFR_DATA:-/data/adb/global_hfr}

ui_print " "
ui_print "======================================"
ui_print "        真·全局高刷  ·  颖哥"
ui_print "  小米 / OPPO / 一加 / realme / 通用"
ui_print "  $MODVER  |  高刷 + 动态 + 触控 + WebUI"
ui_print "======================================"
ui_print " "

brand=$(getprop ro.product.brand)
[ -n "$brand" ] || brand=$(getprop ro.product.system.brand)
model=$(getprop ro.product.model)
[ -n "$model" ] || model=$(getprop ro.product.odm.model)
market=$(getprop ro.product.market.name)
[ -n "$market" ] || market=$(getprop ro.vendor.oplus.market.name)
[ -n "$market" ] || market="$model"

rom=$(getprop ro.mi.os.version.name)
if [ -n "$rom" ]; then
    rom="HyperOS $rom"
else
    rom=$(getprop ro.miui.ui.version.name)
    if [ -n "$rom" ]; then
        rom="MIUI $rom"
    else
        rom=$(getprop ro.build.version.oplusrom)
        if [ -n "$rom" ]; then
            rom="ColorOS $rom"
        else
            rom=$(getprop ro.build.version.opporom)
            [ -n "$rom" ] && rom="ColorOS $rom" || rom=$(getprop ro.build.display.id)
        fi
    fi
fi

sdk=$(getprop ro.build.version.sdk)
case "$sdk" in ''|*[!0-9]*) sdk=${API:-0} ;; esac

ui_print "- 机型：$market ($model)"
ui_print "- 品牌：$brand"
ui_print "- 系统：$rom / Android $(getprop ro.build.version.release)"
ui_print "- 芯片：$(getprop ro.soc.model) $(getprop ro.board.platform)"
ui_print " "

if [ "$sdk" -lt 30 ] 2>/dev/null; then
    abort "需要 Android 11 及以上系统（当前 SDK $sdk）"
fi

case "$brand" in
    Xiaomi|Redmi|POCO|OPPO|OnePlus|realme|oplus|OPPO*)
        ui_print "- 已识别厂商，启用对应动态刷新率策略"
        ;;
    *)
        ui_print "- 未识别厂商，使用通用 DisplayManager / Settings 接口"
        ui_print "- 仍会继续安装，若异常请恢复默认并重启"
        ;;
esac
ui_print " "

# ---------- 权限与目录 ----------
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in hfr.sh service.sh post-fs-data.sh uninstall.sh action.sh customize.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done

mkdir -p "$DATA"
set_perm "$DATA" 0 0 0755

if [ ! -f "$DATA/config.conf" ]; then
    cp -f "$MODPATH/config/default.conf" "$DATA/config.conf" 2>/dev/null
    [ -f "$DATA/config.conf" ] || abort "无法写入默认配置"
fi
set_perm "$DATA/config.conf" 0 0 0644

# 清理上一版遗留的临时状态
rm -f "$DATA/sf_override" "$DATA/state.conf" "$DATA/live.conf" "$DATA/device.conf" 2>/dev/null

# ---------- 安装时预扫描 ----------
ui_print "- 正在扫描显示档位…"
MODDIR="$MODPATH" sh "$MODPATH/hfr.sh" scan >/dev/null 2>&1
maxhz=""
if [ -s "$DATA/modes.tsv" ]; then
    maxhz=$(awk -F'\t' 'BEGIN{m=0} {if ($4+0>m) m=$4+0} END{if (m>0) printf "%.0f", m}' "$DATA/modes.tsv" 2>/dev/null)
fi

if [ -n "$maxhz" ]; then
    ui_print "- 已检测到面板最高 ${maxhz}Hz"
else
    ui_print "- 安装环境无法读取档位，开机后会自动重试"
fi

# ---------- 更新模块描述 ----------
desc="真·全局高刷 · 已适配 ${market}（${model}）｜${rom}｜面板最高 ${maxhz:-待检测}Hz｜动态下限30/60/90按面板识别｜能力自检+多级回退｜WebUI"
desc=$(printf '%s' "$desc" | tr -d '|&')
prop_tmp="$MODPATH/module.prop.tmp"
grep -v '^description=' "$MODPATH/module.prop" > "$prop_tmp" 2>/dev/null
echo "description=$desc" >> "$prop_tmp"
mv -f "$prop_tmp" "$MODPATH/module.prop" 2>/dev/null

ui_print " "
ui_print "✅ 安装完成"
ui_print "──────────────────────────────────────"
ui_print " 默认使用 60Hz 到面板最高的原生动态刷新率"
ui_print " 首次开机自动应用，可在 WebUI 切换固定/动态"
ui_print " WebUI：KernelSU / APatch 模块页直接打开"
ui_print "        Magisk 请安装 KsuWebUI 并授予 Root"
ui_print " 恢复：设置页「恢复系统默认」或卸载模块"
ui_print "──────────────────────────────────────"
ui_print " 作者：颖哥"
ui_print " "
