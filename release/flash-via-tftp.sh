#!/bin/sh
# AX5-32Bit v13.9 release - TFTP recovery / direct serial flash
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
# This is for emergency recovery ONLY - normal flow is build.sh

set -e

SERVER_IP="192.168.31.100"   # Change to your TFTP server
UBI_NAME="ax5-32bit-v13.9-release.ubi"
WIDTH=0x2400000              # AX5 rootfs partition size (36MB)

echo "=== At U-Boot prompt, run: ==="
cat <<EOF
setenv serverip ${SERVER_IP}
setenv ipaddr 192.168.31.1
tftpboot 0x44000000 ${UBI}
nand erase 0x1180000 ${WIDTH}
nand write 0x44000000 0x1180000 \${filesize}
reset
EOF