#!/bin/sh
# AX5-32Bit v15.0 release - flash to mtd19 (rootfs_1 / sys2)
#
# v15.0 changes (vs v14.3):
#   - uhttpd listen_http :81 → :80 (抢回 port 80, 不上 haku_wrt)
#   - 时区明确: zonename 'Asia/Shanghai' (注释里标 "北京时间 (UTC+8, CST-8)")
#   - dropbear RSA host key 重新生成 (v15 专用, 与 v14.3 不同)
#   - uhttpd cert config 'key_type ec' (default 用 ECDSA P-256)
#   - 其它与 v14.3 一致: dropbear 2026.94 / LuCI 26.232 / TLS via libustream-ssl + libmbedtls / NTP 5 server / sysntpd enabled
#
# kernel FIT byte-identical to v13.9 (NWRT 5.4.213, Secure Boot signed).
#
# CRITICAL: keeps flag_try_sys1_failed=0 so sys1 (v13.9) remains a fallback.
# If v15.0 fails to boot, AX5 will auto-rollback to sys1 after ~3 reboots.

set -e

UBI="ax5-32bit-v15.0-release.ubi"

if [ ! -f "$UBI" ]; then
    echo "ERROR: $UBI not found in $(pwd)"
    exit 1
fi

echo "=== Sanity check: current boot flags ==="
fw_printenv flag_boot_rootfs flag_try_sys1_failed flag_try_sys2_failed 2>/dev/null || true

echo
echo "=== Format mtd19 (rootfs_1 / sys2) with $UBI ==="
ubiformat /dev/mtd19 -f "$UBI" -y

echo
echo "=== Set env: boot from sys2, sys1 stays as fallback ==="
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_try_sys2_failed 1

echo
echo "=== Reboot ==="
sync
sleep 3
reboot