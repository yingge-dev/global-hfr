#!/system/bin/sh
# Global HFR · action button
MODDIR=${0%/*}
HFR="$MODDIR/hfr.sh"

[ -f "$HFR" ] || exit 0

echo ""
echo "======================================"
echo "        真·全局高刷 · 快捷切换"
echo "======================================"
echo ""

sh "$HFR" toggle >/dev/null 2>&1
sh "$HFR" brief 2>/dev/null

echo ""
echo "--------------------------------------"
echo " 再次点击可切回另一状态"
echo " 更多设置请打开 WebUI（KsuWebUI）"
echo "======================================"
echo ""
