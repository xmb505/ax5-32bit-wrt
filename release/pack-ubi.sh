#!/bin/sh
# AX5-32Bit v14.3 - Stitch kernel + rootfs into .ubi image
#
# Use this when you have modified 'ax5-32bit-v14.3-rootfs.squashfs'
# (e.g. via unsquashfs/mksquashfs) and want to rebuild the final '.ubi'
# flash image.
#
# Dependencies: 'ubinize' from mtd-utils (sudo apt install mtd-utils)

set -e

CFG="ubinize-v143.cfg"
OUT="ax5-32bit-v14.3-release-custom.ubi"

if [ ! -f "$CFG" ]; then
    echo "ERROR: $CFG not found"
    exit 1
fi

if [ ! -f "ax5-32bit-v14.3-kernel-fit.itb" ]; then
    echo "ERROR: Kernel FIT not found"
    exit 1
fi

if [ ! -f "ax5-32bit-v14.3-rootfs.squashfs" ]; then
    echo "ERROR: Rootfs SquashFS not found"
    exit 1
fi

echo "=== Packaging UBI image ==="
# -m 4096: Minimum I/O size (4KB - matches NWRT kernel UBI header stride)
# -p 128KiB: Physical Erase Block size (128KB for AX5 NAND)
# -s 4096: Sub-page size (matches v13.9 ubinize-v14 baseline)
ubinize -o "$OUT" -m 4096 -p 128KiB -s 4096 "$CFG"

echo "=== SUCCESS! ==="
echo "Stitched image: $OUT"
sha256sum "$OUT"