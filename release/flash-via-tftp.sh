#!/bin/sh
# AX5-32Bit v14.3 release - TFTP recovery / direct serial flash
#
# Use this when router is bricked (no SSH, no boot). Requires serial console
# (UART) + access to the U-Boot prompt.
#
# Steps:
# 1. Connect serial (115200 8N1) to AX5 UART pads (TX/RX/GND)
# 2. Hold reset / power on, wait for U-Boot autoboot countdown
# 3. At U-Boot prompt, set up TFTP server with the .ubi file
# 4. Run commands below (substitute your tftp server IP)
#
# v14.3 UBI size: 24.2 MB. Partition mtd19 size: 36 MB (0x2400000).
# Erase full partition first, then write the UBI image to rootfs_1.

set -e

SERVER_IP="192.168.31.100"   # Change to your TFTP server
UBI_NAME="ax5-32bit-v14.3-release.ubi"
WIDTH=0x2400000              # AX5 rootfs_1 partition size (36MB)

echo "=== At U-Boot prompt, run: ==="
cat <<EOF
setenv serverip ${SERVER_IP}
setenv ipaddr 192.168.31.1
tftpboot 0x44000000 ${UBI_NAME}
nand erase 0x1180000 ${WIDTH}
nand write 0x44000000 0x1180000 \${filesize}
reset
EOF