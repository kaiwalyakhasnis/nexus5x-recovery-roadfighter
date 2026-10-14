#!/bin/bash
# Boot LineageOS recovery (ramdisk-recovery.img from the lineage out/ dir, read-only) on the QEMU
# bullhead kernel. The screen is shown live in a QEMU window (simplefb + ramfb) and the QEMU
# keyboard reaches recovery (virtio-input). Boot log on this terminal.
# Quit: close the window, or Ctrl-A then X here.  Headless: DISPLAY_OPT=none qemu/run-recovery.sh
set -e
Q=$(cd "$(dirname "$0")" && pwd)
. "$Q/env.sh"
RAMDISK=${RAMDISK:-$OUT/ramdisk-recovery.img}
SMP=${SMP:-6}; MEM=2048
DTB=$WORK/dtb/virt-fb-$SMP-$MEM.dtb
[ -f "$DTB" ] || SMP=$SMP MEM=$MEM "$Q/gen-dtb.sh" > /dev/null
rm -f "$QMP_SOCK"
exec qemu-system-aarch64 -M $QEMU_MACHINE -cpu cortex-a57 -smp $SMP -m $MEM \
  -device ramfb -device virtio-keyboard-device -display ${DISPLAY_OPT:-gtk,zoom-to-fit=on} -serial mon:stdio \
  -dtb "$DTB" -qmp unix:"$QMP_SOCK",server=on,wait=off \
  -kernel "$WORK/kobj/arch/arm64/boot/Image" -initrd "$RAMDISK" \
  -append "console=ttyAMA0 earlyprintk=pl011,0x9000000 keep_bootcon androidboot.hardware=bullhead androidboot.selinux=permissive mem=1024M"
