#!/bin/bash
#
# Repack fip.bin for Milk-V Duo 256M (SG2002) so that:
#   - big core  (C906B) -> Linux   (boot.sd / rootfs from this SDK, untouched)
#   - little core (C906L) -> RT-Thread (kernel image given by -r)
#
# fip.bin contains fsbl + opensbi + u-boot + the little core image (BLCP_2ND),
# so only fip.bin has to be replaced on the boot partition of the SD card.
#
# Usage:
#   ./pack_fip_rtthread.sh [-r <rtthread.bin>] [-b <board>] [-o <boot-mount>]
#
#   -r  little core image (default: RT-Thread c906_little/rtthread.bin)
#   -b  Milk-V board name (default: milkv-duo256m-musl-riscv64-sd)
#   -o  optional mount point of the boot (FAT32) partition to copy fip.bin to
#
set -e

SDK_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BOARD=milkv-duo256m-musl-riscv64-sd
RTT_BIN=/home/cybersyn/rt-thread/rt-thread/bsp/cvitek/c906_little/rtthread.bin
BOOT_MNT=

usage()
{
	echo "Usage: $0 [-r <rtthread.bin>] [-b <board>] [-o <boot-mount>]"
	echo "  -r  little core (C906L) image, default: ${RTT_BIN}"
	echo "  -b  board name, default: ${BOARD}"
	echo "  -o  copy the generated fip.bin to this boot partition mount point"
}

while getopts ":r:b:o:h" opt
do
	case "$opt" in
	r) RTT_BIN="$OPTARG" ;;
	b) BOARD="$OPTARG" ;;
	o) BOOT_MNT="$OPTARG" ;;
	h) usage; exit 0 ;;
	*) usage; exit 1 ;;
	esac
done

[ -f "$RTT_BIN" ] || { echo "ERROR: little core image '$RTT_BIN' not found"; exit 1; }

cd "$SDK_DIR"
# shellcheck disable=SC1091
source build/envsetup_milkv.sh "$BOARD" >/dev/null || exit 1

echo "==> board        : $PROJECT_FULLNAME"
echo "==> C906L image   : $RTT_BIN"
echo "==> building fip.bin with RT-Thread as BLCP_2ND"
export C906L_IMAGE="$RTT_BIN"
build_fsbl || exit 1

FIP="$OUTPUT_DIR/fip.bin"
[ -f "$FIP" ] || { echo "ERROR: $FIP was not generated"; exit 1; }

echo "==> verifying little core image inside fip.bin"
python3 - "$FIP" "$RTT_BIN" "$SDK_DIR/fsbl/plat/${CHIP_ARCH,,}/fiptool.py" <<'EOF'
import os
import sys
fip_path, image_path, fiptool_py = sys.argv[1:4]
sys.path.insert(0, os.path.dirname(fiptool_py))
import fiptool

fip = fiptool.FIP()
fip.read_fip(fip_path)
size = fip.param2['BLCP_2ND_SIZE'].toint()
load = fip.param2['BLCP_2ND_LOADADDR'].toint()
run = fip.param2['BLCP_2ND_RUNADDR'].toint()

data = open(fip_path, 'rb').read()[load:load + size]
image = open(image_path, 'rb').read()
match = data[:len(image)] == image and not any(data[len(image):])

print("    BLCP_2ND: load=%#x run=%#x size=%#x %s" %
      (load, run, size, "MATCH" if match else "MISMATCH"))
if not match:
    print("ERROR: fip.bin does not contain %s" % image_path)
    sys.exit(1)
EOF

echo "==> done: $FIP ($(stat -c %s "$FIP") bytes)"

if [ -n "$BOOT_MNT" ]; then
	[ -d "$BOOT_MNT" ] || { echo "ERROR: $BOOT_MNT is not a directory"; exit 1; }
	cp "$FIP" "$BOOT_MNT"/fip.bin
	sync
	echo "==> copied to $BOOT_MNT/fip.bin"
else
	echo "Copy it to the boot (FAT32) partition of the SD card:"
	echo "  cp $FIP /media/\$USER/boot/fip.bin && sync"
	echo "If the Linux device tree changed, also update boot.sd (see README.md):"
	echo "  cp ${OUTPUT_DIR}/rawimages/boot.sd /media/\$USER/boot/boot.sd && sync"
fi
