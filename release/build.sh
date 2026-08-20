#!/bin/sh
# AX5-32Bit v13.9 release - flash to mtd19 (rootfs_1)
#
# Use this when sys1 is active (flag_boot_rootfs=0) and you want to flash
# the v13.9 release to sys2 (mtd19 / rootfs_1), then switch boot flag.
#
# Recovery: if boot fails after flash, switch back to sys1:
#   fw_setenv flag_boot_rootfs 0
#   fw_setenv flag_try_sys1_failed 0
#   fw_setenv flag_try_sys2_failed 1
#   reboot

set -e

UBI="ax5-32bit-v13.9-release.ubi"

if [ ! -f "$UBI" ]; then
    echo "ERROR: $UBI not found"
    exit 1
fi

echo "=== Sanity check current partition ==="
fw_printenv flag_boot_rootfs flag_try_sys1_failed flag_try_sys2_failed 2>/dev/null || true

echo "=== Format mtd19 (rootfs_1) ==="
ubiformat /dev/mtd19 -f "$UBI"

echo "=== Switch boot flag to rootfs_1 (sys2) ==="
fw_setenv flag_boot_rootfs 1
fw_setenv flag_try_sys1_failed 1
fw_setenv flag_try_sys2_failed 0

echo "=== Reboot ==="
reboot