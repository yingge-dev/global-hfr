#!/system/bin/sh
# Global HFR · uninstall
MODDIR=${0%/*}
DATA=${HFR_DATA:-/data/adb/global_hfr}

echo ""
echo "======================================"
echo "        真·全局高刷 · 正在卸载"
echo "======================================"

# stop daemon
for pid in $(ps -A -o PID,ARGS 2>/dev/null | grep '[h]fr.sh daemon' | awk '{print $1}'); do
    kill "$pid" 2>/dev/null
done

# restore display / touch / SurfaceFlinger
if [ -f "$MODDIR/hfr.sh" ]; then
    sh "$MODDIR/hfr.sh" restore >/dev/null 2>&1
    echo "[✓] 已恢复系统刷新率与触控设置"
else
    settings delete system peak_refresh_rate >/dev/null 2>&1
    settings delete system min_refresh_rate >/dev/null 2>&1
    settings delete system user_refresh_rate >/dev/null 2>&1
    service call SurfaceFlinger 1034 i32 0 >/dev/null 2>&1
    echo "[✓] 已尝试恢复系统刷新率"
fi

rm -f "$DATA/sf_override" 2>/dev/null
rm -rf "$DATA"
echo "[✓] 配置与日志已清理"

echo ""
echo "⚠️  请立刻重启手机，确保 SurfaceFlinger 状态完全释放"
echo "======================================"
echo ""
