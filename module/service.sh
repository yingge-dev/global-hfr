#!/system/bin/sh
# Global HFR · late_start service
MODDIR=${0%/*}

[ -f "$MODDIR/hfr.sh" ] || exit 0

exec sh "$MODDIR/hfr.sh" daemon
