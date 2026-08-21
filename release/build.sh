#!/bin/sh
# AX5-32Bit v14.3 release - flash to mtd19 (rootfs_1 / sys2)
#
# v14.3 changes (vs v13.9):
#   - dropbear v2026.94 + baked RSA host key (no first-boot SSH reset)
#   - LuCI git-26.232 (2026 mainline, modular + JS frontend)
#   - libustream-ssl + libmbedtls (TLS via uhttpd plugin, was missing)
#   - ECDSA P-256 server cert (CN=AX5-<MAC>, SAN: 192.168.1.1 + openwrt.lan, 825d)
#   - /etc/config/system: timezone Asia/Shanghai + 5 NTP servers (ntp.aliyun, tencent, pool)
#   - sysntpd enabled by default
#   - root password hash: SHA-512 of 'password ' (matches sys1 dev handoff)
#   - NO haku_wrt (per user request: 不用装上hakuwrt)
#   - kernel FIT byte-identical to v13.9 (NWRT 5.4.213, secure boot signed)
#
# Use when sys1 is active (flag_boot_rootfs=0) and you want to flash
# the v14.3 release to sys2 (mtd19 / rootfs_1).
#
# CRITICAL: keeps flag_try_sys1_failed=0 so sys1 (v13.9) remains a fallback.
# If v14.3 fails to boot, AX5 will auto-rollback to sys1 after ~3 reboots.

set -e

UBI="ax5-32bit-v14.3-release.ubi"

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