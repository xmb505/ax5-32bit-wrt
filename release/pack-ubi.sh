#!/bin/sh
# AX5-32Bit - Stitch kernel + rootfs + overlay into .ubi image
#
# Use this when you have modified 'ax5-32bit-vXX.X-rootfs.squashfs'
# (e.g. via unsquashfs/mksquashfs) and want to rebuild the final '.ubi'
# flash image.
#
# VER is the version string (e.g. v21.0). It looks for:
#   ubinize-${VER}.cfg
#   ax5-32bit-${VER}-hakuwrt-kernel-fit.itb
#   ax5-32bit-${VER}-hakuwrt-rootfs.squashfs
# Outputs:
#   ax5-32bit-${VER}-hakuwrt-release.ubi
#
# ⚠️  CRITICAL — NAND 参数 (2026-08-23 INCIDENT 修正)
#   AX5 NAND 真实硬件参数: page=4096, sub-page=2048, PEB=128KiB
#   必须用 mtd-utils 2.1.1 的 ubinize + `-m 2048 -p 128KiB -s 2048`
#   - 系统默认 mtd-utils (2.3.0) 的 ubinize 不行,EC header 兼容性差
#   - -m 4096 -s 4096 是错的 (INCIDENT_V15 文档错误,已修正)

set -e
cd "$(dirname "$0")"

VER="${1:-v21.0}"
CFG="ubinize-${VER#v}.cfg"
KERNEL="ax5-32bit-${VER}-hakuwrt-kernel-fit.itb"
ROOTFS="ax5-32bit-${VER}-hakuwrt-rootfs.squashfs"
OUT="ax5-32bit-${VER}-hakuwrt-release.ubi"

UBINIZE="/home/xmb505/immortalwrt/ax5-32bit/src/staging_dir/host/bin/ubinize"

for f in "$CFG" "$KERNEL" "$ROOTFS"; do
    if [ ! -f "$f" ]; then
        echo "ERROR: $f not found in $(pwd)"
        exit 1
    fi
done

if [ ! -x "$UBINIZE" ]; then
    echo "ERROR: mtd-utils 2.1.1 ubinize not found at $UBINIZE"
    echo "       (system /usr/sbin/ubinize 2.3.0 is incompatible, do NOT use it)"
    exit 1
fi

echo "=== Packaging UBI image ($VER) ==="
echo "  kernel:  $KERNEL ($(stat -c%s "$KERNEL") bytes)"
echo "  rootfs:  $ROOTFS ($(stat -c%s "$ROOTFS") bytes)"
echo "  cfg:     $CFG"
echo "  ubinize: $($UBINIZE -V)"
echo "  out:     $OUT"
echo ""

# ⚠️ -m 2048 -p 128KiB -s 2048 (NOT -m 4096 -s 4096!)
"$UBINIZE" -o "$OUT" -m 2048 -p 128KiB -s 2048 "$CFG"

echo ""
echo "=== SUCCESS! ==="
echo "Stitched image: $OUT ($(stat -c%s "$OUT") bytes)"
sha256sum "$OUT"
