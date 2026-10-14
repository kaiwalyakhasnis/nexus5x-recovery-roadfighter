#!/bin/busybox sh
/bin/busybox mkdir -p /sbin /usr/bin /usr/sbin
/bin/busybox --install -s
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null
mkdir -p /dev/pts && mount -t devpts devpts /dev/pts
hostname bullhead-qemu
# glibc in busybox tries rseq (syscall 293), absent on 3.10; disable it and quiet console logs (dmesg still has them)
export GLIBC_TUNABLES=glibc.pthread.rseq=0
dmesg -n 1
echo
echo "=== bullhead kernel $(uname -r) on QEMU: busybox shell ==="
echo "Try: cat /proc/sys/kernel/sched_upmigrate ; ls /proc/sys/kernel/ | grep sched ; cat /proc/self/sched"
echo "Quit QEMU: Ctrl-A then X"
echo
exec setsid cttyhack sh -l
