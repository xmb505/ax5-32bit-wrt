#!/bin/sh
# AX5-32Bit - Flash release.ubi to the OPPOSITE sys partition and switch to it
#
# Usage: ./build.sh [VER]
#   VER defaults to v21.0 (latest verified release).
#   Reads  ax5-32bit-${VER}-hakuwrt-release.ubi
#
# What this does (double-partition safe):
#   1. Picks the sys partition OPPOSITE to the one currently running
#      (cmdline says ubi.mtd=rootfs  →  running sys1 (mtd18), flash sys2 (mtd19)
#       cmdline says ubi.mtd=rootfs_1 → running sys2 (mtd19), flash sys1 (mtd18))
#   2. ubiformat that partition
#   3. Set flag_boot_rootfs to the new side, mark the old side as failed
#      (so U-Boot fallbacks here if new side doesn't boot)
#   4. reboot
#
# CRITICAL: the OLD side is marked failed=1 so U-Boot will rollback after
# ~3 boot attempts if the new side doesn't come up. Keep this side as fallback.

set -e

VER="${1:-v21.0}"
UBI="ax5-32bit-${VER}-hakuwrt-release.ubi"

if [ ! -f "$UBI" ]; then
    echo "ERROR: $UBI not found in $(pwd)"
    exit 1
fi

# Detect current side
CMDLINE=$(cat /proc/cmdline)
case "$CMDLINE" in
    *ubi.mtd=rootfs*)     CURRENT=1; TARGET=2; TARGET_MTD=/dev/mtd19; TARGET_NAME=rootfs_1 ;;
    *ubi.mtd=rootfs_1*)   CURRENT=2; TARGET=1; TARGET_MTD=/dev/mtd18; TARGET_NAME=rootfs   ;;
    *)
        echo "ERROR: cannot detect current sys from cmdline: $CMDLINE"
        exit 1
        ;;
esac

echo "=== AX5-32Bit $VER flash (sys${CURRENT} → sys${TARGET}) ==="
echo "  current cmdline : $CMDLINE"
echo "  target          : sys${TARGET} = ${TARGET_MTD} (${TARGET_NAME})"
echo "  ubi image       : $UBI ($(stat -c%s "$UBI") bytes)"
echo

echo "=== Current boot flags ==="
fw_printenv flag_boot_rootfs flag_try_sys1_failed flag_try_sys2_failed 2>/dev/null || true
echo

echo "=== Format ${TARGET_MTD} with $UBI (this can take 1-2 min) ==="
ubiformat "$TARGET_MTD" -f "$UBI" -y

echo
echo "=== Set env: boot sys${TARGET}, mark sys${CURRENT} failed for rollback ==="
if [ "$TARGET" = "2" ]; then
    fw_setenv flag_boot_rootfs 1
    fw_setenv flag_try_sys1_failed 1
    fw_setenv flag_try_sys2_failed 0
else
    fw_setenv flag_boot_rootfs 0
    fw_setenv flag_try_sys1_failed 0
    fw_setenv flag_try_sys2_failed 1
fi

echo
echo "=== Reboot ==="
sync
sleep 3
reboot
