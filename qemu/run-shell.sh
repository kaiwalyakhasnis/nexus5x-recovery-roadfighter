#!/bin/bash
# Boot the QEMU bullhead kernel into a busybox shell on hvc0 (virtio console).
# SMP=6 for six CPUs like the phone. Quit: Ctrl-A then X.
Q=$(cd "$(dirname "$0")" && pwd)
. "$Q/env.sh"
exec qemu-system-aarch64 -M $QEMU_MACHINE -cpu cortex-a57 -smp ${SMP:-1} -m ${MEM:-1024} \
  -display none -serial null -monitor none \
  -chardev stdio,id=con,mux=on,signal=off \
  -device virtio-serial-device -device virtconsole,chardev=con \
  -kernel "$WORK/kobj/arch/arm64/boot/Image" -initrd "$WORK/initramfs/shell.cpio.gz" \
  -append "console=hvc0 rdinit=/init"
