#!/bin/bash
# One-time setup of the QEMU side: a patched copy of the bullhead kernel, built for QEMU's "virt"
# board, a busybox initramfs and the device tree with the recovery framebuffer.
# The LineageOS tree is only read; everything is written to $WORK.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
. "$REPO/qemu/env.sh"

mkdir -p "$WORK"
echo "== kernel source: $KERNEL_SRC (git HEAD) -> $WORK/src"
if [ ! -d "$WORK/src" ]; then
  mkdir -p "$WORK/src"
  git -C "$KERNEL_SRC" archive HEAD | tar -x -C "$WORK/src"
  for p in "$REPO"/patches/qemu-kernel/*.patch; do
    echo "   applying $(basename "$p")"
    patch -p1 -s -d "$WORK/src" < "$p"
  done
fi

echo "== kernel config: lineageos_bullhead_defconfig + qemu/kernel-qemu.config"
mkdir -p "$WORK/kobj"
kmake() { make -C "$WORK/src" O="$WORK/kobj" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" "$@"; }
kmake lineageos_bullhead_defconfig > /dev/null
args=()
while read -r line; do
  case "$line" in
    CONFIG_*=y)              opt=${line%%=*}; args+=(-e "${opt#CONFIG_}") ;;
    "# CONFIG_"*" is not set") opt=${line#\# CONFIG_}; args+=(-d "${opt%% *}") ;;
  esac
done < "$REPO/qemu/kernel-qemu.config"
"$WORK/src/scripts/config" --file "$WORK/kobj/.config" "${args[@]}"
kmake olddefconfig > /dev/null

echo "== building kernel Image (takes a while the first time)"
kmake -j"$(nproc)" Image > "$WORK/kernel-build.log" 2>&1 || { tail -30 "$WORK/kernel-build.log"; exit 1; }

echo "== initramfs"
mkdir -p "$WORK/initramfs" "$WORK/downloads"
BB_DEB=busybox-static_1.36.1-6ubuntu3_arm64.deb
BB_SHA256=1a8c03948f99dfbb90efd93d9214418b416ac0737ed4c90938ebbcd645f10682
if [ ! -f "$WORK/downloads/$BB_DEB" ]; then
  curl -sSfo "$WORK/downloads/$BB_DEB" "https://ports.ubuntu.com/ubuntu-ports/pool/main/b/busybox/$BB_DEB"
fi
echo "$BB_SHA256  $WORK/downloads/$BB_DEB" | sha256sum -c --quiet
rm -rf "$WORK/downloads/bb" && mkdir -p "$WORK/downloads/bb"
dpkg-deb -x "$WORK/downloads/$BB_DEB" "$WORK/downloads/bb"
cp "$WORK/downloads/bb/usr/bin/busybox" "$WORK/initramfs/busybox"
cp "$REPO/qemu/initramfs/init-shell.sh" "$WORK/initramfs/init-shell.sh"
"${CROSS_COMPILE}gcc" -std=gnu99 -static -nostdlib -ffreestanding -fno-stack-protector -O2 \
  -o "$WORK/initramfs/init-sched-dump" "$REPO/qemu/initramfs/init-sched-dump.c"
cat > "$WORK/initramfs/shell.list" <<LIST
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /bin 0755 0 0
dir /tmp 1777 0 0
dir /root 0700 0 0
file /bin/busybox $WORK/initramfs/busybox 0755 0 0
file /init $WORK/initramfs/init-shell.sh 0755 0 0
LIST
cat > "$WORK/initramfs/sched-dump.list" <<LIST
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/kmsg 0644 0 0 c 1 11
dir /proc 0755 0 0
dir /sys 0755 0 0
file /init $WORK/initramfs/init-sched-dump 0755 0 0
LIST
"$WORK/kobj/usr/gen_init_cpio" "$WORK/initramfs/shell.list" | gzip > "$WORK/initramfs/shell.cpio.gz"
"$WORK/kobj/usr/gen_init_cpio" "$WORK/initramfs/sched-dump.list" | gzip > "$WORK/initramfs/sched-dump.cpio.gz"

echo "== device tree with framebuffer"
SMP=6 MEM=2048 "$REPO/qemu/gen-dtb.sh"

echo
echo "Done. Kernel: $WORK/kobj/arch/arm64/boot/Image"
echo "Try:  qemu/run-shell.sh      (busybox shell)"
echo "      qemu/run-recovery.sh   (LineageOS recovery from $OUT)"
