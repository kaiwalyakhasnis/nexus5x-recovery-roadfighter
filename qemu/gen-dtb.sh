#!/bin/bash
# Build a QEMU virt device tree with a simple-framebuffer (1080x1920 32bpp RGBX, like bullhead's panel)
# placed at 0x80000000 in guest RAM; boot with mem=1024M so Linux leaves it alone.  Usage: SMP=6 MEM=2048 ./gen-dtb.sh  -> $WORK/dtb/virt-fb-<SMP>-<MEM>.dtb
set -e
. "$(cd "$(dirname "$0")" && pwd)/env.sh"
SMP=${SMP:-6}; MEM=${MEM:-2048}
DTC=${DTC:-$LINEAGE/prebuilts/misc/linux-x86/dtc/dtc}
mkdir -p "$WORK/dtb"
DTB_OUT=$WORK/dtb/virt-fb-$SMP-$MEM
qemu-system-aarch64 -M $QEMU_MACHINE,dumpdtb=$DTB_OUT.orig.dtb -cpu cortex-a57 \
  -smp $SMP -m $MEM -display none -device virtio-serial-device >/dev/null 2>&1
$DTC -q -I dtb -O dts -o $DTB_OUT.orig.dts $DTB_OUT.orig.dtb
python3 - "$DTB_OUT.orig.dts" "$DTB_OUT.dts" "$MEM" <<'PY'
import re, sys
src, dst, mem = sys.argv[1], sys.argv[2], int(sys.argv[3])
W, H = 1080, 1920
# arm64 3.10 treats a whole 1GB sparsemem section as RAM if any of it is RAM (and refuses to
# ioremap it), so Linux gets the first 1GB (mem=1024M on the cmdline; QEMU rewrites the DT
# memory node itself) and the framebuffer sits in the next section.
assert mem >= 1040, "MEM must be >= 1040"
linux_ram = 1 << 30
fb_base = 0x40000000 + linux_ram
s = open(src).read()
node = f'''
	framebuffer@{fb_base:x} {{
		compatible = "simple-framebuffer";
		reg = <{fb_base >> 32:#x} {fb_base & 0xffffffff:#x} 0x00 {W*H*4:#x}>;
		width = <{W}>;
		height = <{H}>;
		stride = <{W*4}>;
		format = "a8b8g8r8";
	}};
'''
i = s.rindex('};')
s = s[:i] + node + s[i:]
open(dst, 'w').write(s)
print(f"fb at {fb_base:#x}, {W}x{H} a8b8g8r8, boot with mem={linux_ram>>20}M")
PY
$DTC -q -I dts -O dtb -o $DTB_OUT.dtb $DTB_OUT.dts
echo "$DTB_OUT.dtb"
