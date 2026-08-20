#!/bin/sh
# AX5-32Bit - One-click "inject my files into rootfs + rebuild UBI"
#
# Workflow:
#   1. Put any files you want into the rootfs under ./customize/
#      (directory layout = target path in rootfs, e.g.
#       customize/usr/bin/myapp  ->  /usr/bin/myapp on the router)
#   2. Run: ./customize.sh
#   3. Flash the generated ax5-32bit-v13.9-release-custom.ubi
#
# Dependencies (on your build PC): squashfs-tools, mtd-utils
#   Debian/Ubuntu: sudo apt install squashfs-tools mtd-utils xz-utils
#
# Safe to re-run: original rootfs.squashfs is backed up once as
# ax5-32bit-v13.9-rootfs.squashfs.orig and always used as the base.

set -e
cd "$(dirname "$0")"

ROOTFS="ax5-32bit-v13.9-rootfs.squashfs"
OVERLAY="customize"
WORKDIR="squashfs-root"

for tool in unsquashfs mksquashfs ubinize; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: '$tool' not found. Install squashfs-tools + mtd-utils first."
        exit 1
    fi
done

if [ ! -d "$OVERLAY" ] || [ -z "$(find "$OVERLAY" -type f ! -name 'README.md' 2>/dev/null | head -1)" ]; then
    echo "ERROR: $OVERLAY/ is empty. Put your files there first (see CUSTOMIZE.md)."
    exit 1
fi

# 1. Keep a pristine base image
if [ ! -f "$ROOTFS.orig" ]; then
    [ -f "$ROOTFS" ] || { echo "ERROR: $ROOTFS missing"; exit 1; }
    cp "$ROOTFS" "$ROOTFS.orig"
    echo "=== Backed up original rootfs to $ROOTFS.orig ==="
fi

# 2. Unpack pristine base
rm -rf "$WORKDIR"
echo "=== Extracting rootfs ==="
unsquashfs -d "$WORKDIR" "$ROOTFS.orig" >/dev/null

# 3. Overlay custom files
echo "=== Injecting files from $OVERLAY/ ==="
cp -a "$OVERLAY"/. "$WORKDIR"/
rm -f "$WORKDIR"/README.md

# 4. Repack (NWRT kernel only supports squashfs-XZ, do NOT change flags)
rm -f "$ROOTFS"
echo "=== Repacking squashfs (xz, 128K block) ==="
mksquashfs "$WORKDIR" "$ROOTFS" -comp xz -b 128K -noappend >/dev/null

# 5. Rebuild UBI
sh ./pack-ubi.sh

rm -rf "$WORKDIR"
echo ""
echo "=== DONE ==="
echo "Flash it via SSH:  scp the .ubi to the router, then run ./build.sh on the router."
echo "New checksums:"
sha256sum "$ROOTFS" ax5-32bit-v13.9-release-custom.ubi
