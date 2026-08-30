#!/bin/sh
# AX5-32Bit - One-click "inject my files into rootfs + rebuild UBI"
#
# Workflow:
#   1. Put any files you want into the rootfs under ./customize/
#      (directory layout = target path in rootfs, e.g.
#       customize/usr/bin/myapp  ->  /usr/bin/myapp on the router)
#   2. Run: ./customize.sh [VER]
#      VER defaults to v21.0; the script picks:
#        ubinize-${VER}.cfg
#        ax5-32bit-${VER}-hakuwrt-kernel-fit.itb
#      and writes ax5-32bit-${VER}-hakuwrt-release-custom.ubi
#   3. Flash the generated .ubi via ./build.sh on the router.
#
# Base rootfs source: ax5-32bit-${VER}-hakuwrt-rootfs.squashfs (in same dir).
#
# Dependencies (on your build PC):
#   - squashfs-tools (unsquashfs + mksquashfs)
#   - mtd-utils 2.1.1 ubinize (already installed under ax5-32bit/src/...)
#     ⚠️ NOT the system /usr/sbin/ubinize (2.3.0 in incompatible, brick risk)
#
# Safe to re-run: original rootfs.squashfs is backed up once as
# ax5-32bit-${VER}-hakuwrt-rootfs.squashfs.orig and always used as the base.

set -e
cd "$(dirname "$0")"

VER="${1:-v21.0}"
BASE="ax5-32bit-${VER}-hakuwrt-rootfs.squashfs"
BASE_ORIG="${BASE}.orig"
OVERLAY="customize"
WORKDIR="squashfs-root"

UBINIZE="/home/xmb505/immortalwrt/ax5-32bit/src/staging_dir/host/bin/ubinize"

for tool in unsquashfs mksquashfs; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "ERROR: '$tool' not found. Install squashfs-tools first."
        exit 1
    fi
done

if [ ! -x "$UBINIZE" ]; then
    echo "ERROR: mtd-utils 2.1.1 ubinize not found at $UBINIZE"
    exit 1
fi

if [ ! -d "$OVERLAY" ] || [ -z "$(find "$OVERLAY" -type f ! -name 'README.md' 2>/dev/null | head -1)" ]; then
    echo "ERROR: $OVERLAY/ is empty. Put your files there first (see CUSTOMIZE.md)."
    exit 1
fi

# 1. Keep a pristine base image (only back up once)
if [ ! -f "$BASE_ORIG" ]; then
    [ -f "$BASE" ] || { echo "ERROR: $BASE missing"; exit 1; }
    cp "$BASE" "$BASE_ORIG"
    echo "=== Backed up original rootfs to $BASE_ORIG ==="
fi

# 2. Unpack pristine base
rm -rf "$WORKDIR"
echo "=== Extracting rootfs from $BASE_ORIG ==="
unsquashfs -d "$WORKDIR" "$BASE_ORIG" >/dev/null

# 3. Overlay custom files
echo "=== Injecting files from $OVERLAY/ ==="
cp -a "$OVERLAY"/. "$WORKDIR"/
rm -f "$WORKDIR"/README.md

# 3b. Strip dead ddns-go remnants (binary+init.d gone since v22.0; base still
#     carries the dangling S99ddns-go boot link and luci-app-ddns-go pages)
rm -rf "$WORKDIR"/etc/ddns-go "$WORKDIR"/usr/share/ddns-go
rm -f "$WORKDIR"/etc/rc.d/*ddns-go* "$WORKDIR"/usr/lib/lua/luci/view/ddns-go.htm \
    "$WORKDIR"/usr/lib/lua/luci/view/ddns-go_status.htm \
    "$WORKDIR"/usr/share/rpcd/acl.d/luci-app-ddns-go.json \
    "$WORKDIR"/usr/lib/lua/luci/controller/ddns-go.lua

# 4. Repack (NWRT kernel only supports squashfs-XZ, do NOT change flags)
rm -f "$BASE"
echo "=== Repacking squashfs (xz, 128K block) ==="
mksquashfs "$WORKDIR" "$BASE" -comp xz -b 128K -noappend >/dev/null

# 5. Rebuild UBI
sh ./pack-ubi.sh "$VER"

# 6. Also produce a '-custom.ubi' alias for downstream flashing scripts
CUSTOM_OUT="ax5-32bit-${VER}-hakuwrt-release-custom.ubi"
cp -f "ax5-32bit-${VER}-hakuwrt-release.ubi" "$CUSTOM_OUT"

rm -rf "$WORKDIR"
echo ""
echo "=== DONE ==="
echo "Flash via:  scp the .ubi to the router, then run ./build.sh on the router."
echo "New checksums:"
sha256sum "$BASE" "ax5-32bit-${VER}-hakuwrt-release.ubi" "$CUSTOM_OUT"
