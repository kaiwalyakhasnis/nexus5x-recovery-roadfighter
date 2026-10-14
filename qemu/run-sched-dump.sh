#!/bin/bash
# Non-interactive boot: full boot log + scheduler info (/proc/sys/kernel/sched_*, /proc/self/sched),
# then idles. Quit: Ctrl-A then X.
Q=$(cd "$(dirname "$0")" && pwd)
. "$Q/env.sh"
exec qemu-system-aarch64 -M $QEMU_MACHINE -cpu cortex-a57 -smp ${SMP:-1} -m ${MEM:-1024} -nographic \
  -kernel "$WORK/kobj/arch/arm64/boot/Image" -initrd "$WORK/initramfs/sched-dump.cpio.gz" \
  -append "console=ttyAMA0 earlyprintk=pl011,0x9000000 keep_bootcon rdinit=/init"
