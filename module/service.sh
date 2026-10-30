#!/system/bin/sh
# 全局高刷 · late_start service
MODDIR=${0%/*}

[ -f "$MODDIR/hfr.sh" ] || exit 0

# 交给引擎：等待开机完成 -> 应用配置 -> 守护（息屏/亮屏/漂移自动重锁）
exec sh "$MODDIR/hfr.sh" daemon
