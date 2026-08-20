#!/bin/sh
# AX5-32Bit - Stitch kernel + rootfs into .ubi image
#
# Use this when you have modified 'ax5-32bit-v13.9-rootfs.squashfs' (e.g. via unsquashfs/mksquashfs)
# and want to rebuild the final '.ubi' flash image.
#
# Dependencies: 'ubinize' from mtd-utils (sudo apt install mtd-utils)

set -e

CFG="ubinize.cfg"
OUT="ax5-32bit-v13.9-release-custom.ubi"

if [ ! -f "$CFG" ]; then
    echo "ERROR: $CFG not found"
    exit 1
fi

if [ ! -f "ax5-32bit-v13.9-kernel-fit.itb" ]; then
    echo "ERROR: Kernel FIT not found"
    exit 1
fi

if [ ! -f "ax5-32bit-v13.9-rootfs.squashfs" ]; then
    echo "ERROR: Rootfs SquashFS not found"
    exit 1
fi

echo "=== Packaging UBI image ==="
# -m 2048: Minimum I/O size (2KB for AX5 NAND)
# -p 128KiB: Physical Erase Block size (128KB for AX5 NAND)
# -s 2048: Sub-page size
ubinize -o "$OUT" -m 2048 -p 128KiB -s 2048 "$CFG"

echo "=== SUCCESS! ==="
echo "Stitched image: $OUT"
sha256sum "$OUT"