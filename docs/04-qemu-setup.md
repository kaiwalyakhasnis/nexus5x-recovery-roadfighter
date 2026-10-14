# 4. Running the bullhead kernel and recovery in QEMU

QEMU has no model of the Nexus 5X's Snapdragon 808 (MSM8992). The trick is to boot the **same
bullhead kernel source** on QEMU's generic `virt` board (Cortex-A57, GICv2) and work around every
place where the Qualcomm kernel assumes Qualcomm hardware. The recovery ramdisk from the LineageOS
build then runs unchanged.

`qemu/setup.sh` does everything below; this page explains why each piece is there.

## Requirements

* A LineageOS 15.1 tree with `lineage_bullhead-userdebug` built (for the toolchain, `dtc` and
  `out/target/product/bullhead/ramdisk-recovery.img`). Set `LINEAGE=` if it isn't
  `~/Desktop/android/lineage`.
* `qemu-system-aarch64` (Ubuntu: `sudo apt install qemu-system-arm`), tested with QEMU 8.2.
* `python3` with Pillow (only for `screenshot.py`), `curl`, `dpkg-deb`.

```
qemu/setup.sh                  # once: kernel copy + patches + build, busybox initramfs, device tree
qemu/run-recovery.sh           # LineageOS recovery in a window, keyboard works
qemu/run-shell.sh              # busybox shell on the QEMU kernel (SMP=6 for six CPUs)
qemu/run-sched-dump.sh         # boot log + scheduler info, no shell
```

Everything is written to `$WORK` (default `~/bullhead-qemu`). QEMU's control socket is
`$QMP_SOCK` (default `$WORK/qmp.sock`); set it to a shorter path if `$WORK` is very long, since
Unix socket paths are limited to about 107 characters. The LineageOS tree is only read:
`setup.sh` takes the kernel with `git archive HEAD` and patches the copy.

## The tricks, in the order they were hit

### 1. TrustZone calls crash the kernel → `virtualization=on`

Very early in `setup_arch()` the Qualcomm kernel calls into TrustZone with `smc`
(`init_random_pool → scm_call`). On a plain `virt` board there's no EL3 firmware, so `smc` is an
undefined instruction and the kernel oopses before printing much.

With `-M virt,virtualization=on` the kernel boots at EL2 and QEMU uses **SMC** as the PSCI conduit.
QEMU's built-in "firmware" then answers unknown SMC calls with `NOT_SUPPORTED` (-1), and the
Qualcomm code just logs `scm_call failed with error code -1` and carries on.

### 2. No `ttyAMA0` → early console + virtio console

`lineageos_bullhead_defconfig` only has Qualcomm UARTs. The PL011 driver can be enabled, but its
probe needs a clock from the clock framework, and Qualcomm's own clock code (not the common clock
framework) can't hand out the fixed clock QEMU puts in the device tree. So `ttyAMA0` is never
created, and you get **"Warning: unable to open an initial console"**.

* `earlyprintk=pl011,0x9000000 keep_bootcon` keeps the early console alive for the whole boot
  log (it writes to the PL011 registers directly, no clock needed).
* For an interactive shell, a **virtio console** (`hvc0`) needs no clock at all.

### 3. Recovery needs a screen → simplefb in RAM, outside Linux's memory

Recovery draws on `/dev/graphics/fb0`. Qualcomm's MDSS can't work in QEMU, so the device tree gets
a **`simple-framebuffer`** node: 1080×1920 (the phone's panel) at guest address `0x80000000`
(`qemu/gen-dtb.sh`).

* QEMU rewrites the memory node in any `-dtb` you pass, so Linux is limited with **`mem=1024M`**
  instead.
* arm64 3.10 treats a whole **1 GB sparsemem section** as RAM if any of it is RAM, and refuses to
  `ioremap` it (`arch/arm64/mm/ioremap.c:58`). So the framebuffer has to be in a different
  gigabyte than Linux's memory: Linux gets `0x40000000–0x7fffffff`, the framebuffer starts at
  `0x80000000`.

### 4. MDSS crashes on a non-MDSS framebuffer → patch 0001

As soon as simplefb registers `fb0`, `mdss_dsi_status.c`'s framebuffer notifier treats it as an
MDSS framebuffer (`evdata->info->par` → `msm_fb_data_type`) and dereferences garbage. The
console is already quiet at that point. The oops was found by reading `__log_buf` straight out
of guest RAM with QMP `pmemsave`. Patch 0001 makes the notifier ignore framebuffers whose id isn't
`mdssfb*`.

### 5. Wrong colors → patch 0002 (32 bpp)

3.10's simplefb only knows `r5g6b5`. Recovery's minui in Android 8.1 effectively assumes 4 bytes
per pixel, so on a 16-bit framebuffer the text came out smeared and recolored. Patch 0002 adds the
`a8b8g8r8` format, which newer kernels have upstream. Bytes R,G,B,X match minui's default draw
format exactly.

### 6. Seeing it live → patch 0003 + `-device ramfb`

QEMU only shows a window for display devices it emulates. This kernel has no driver for any of
them: virtio-gpu needs Linux 4.2+, and PCI VGA needs the generic PCI host bridge from 3.19+.
`ramfb` is the exception: the guest only has to write a 28-byte config ("my framebuffer is at
address X, format XB24, 1080×1920, stride 4320") to QEMU's fw_cfg file `etc/ramfb`, using fw_cfg's
DMA interface. `drivers/video/qemu_ramfb_setup.c` (patch 0003) does that at boot from the
`simple-framebuffer` node, and QEMU then shows that memory live.
`qemu/screenshot.py` still works too: it reads the same RAM over QMP.

### 7. Keyboard → patch 0004 (virtio-input backport)

virtio-input appeared in Linux 4.1. Patch 0004 is a compact backport onto 3.10's virtio API
(legacy virtio-mmio, raw config `get/set`, event queue only). With
`-device virtio-keyboard-device`, the keys typed in the QEMU window arrive as
`/dev/input/event0`, and recovery's minui picks it up like any other key device.

### 8. Host build fix → patch 0000

GCC 10+ defaults to `-fno-common`, so the kernel's shipped `dtc` fails to link with
`multiple definition of 'yylloc'`. Patch 0000 is the same one-line fix as upstream. A full
LineageOS build of the bullhead kernel with a modern host GCC needs it too.

### 9. Small things

* Busybox: Ubuntu's static arm64 busybox (`busybox-static_1.36.1-6ubuntu3`, SHA-256 checked).
  Its glibc tries the `rseq` syscall, which 3.10 doesn't have, so the init script sets
  `GLIBC_TUNABLES=glibc.pthread.rseq=0` and lowers the console log level.
* evdev reads on arm64 must be at least 24 bytes (`struct input_event`).
* `-M virt,gic-version=2`: the 3.10 kernel only has a GICv2 driver.

## What QEMU can't show

QEMU's CPUs are identical Cortex-A57s with no cpufreq, so the HMP scheduler's big.LITTLE task
migration and the `interactive` governor don't behave as on the phone. Qualcomm-specific
peripherals (modem, camera, sensors, TrustZone) are absent; their drivers log warnings and are
skipped. None of that matters for recovery or the game.
