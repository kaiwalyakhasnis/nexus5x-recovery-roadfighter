# 3. Which drivers are involved

Road Fighter doesn't add or need any driver on the phone. It goes through the same device files as
the stock recovery screens. Only QEMU needed kernel changes, because QEMU can't emulate the
Qualcomm hardware.

## On the Nexus 5X (bullhead, MSM8992, kernel 3.10)

| What | Device file | Kernel driver | Config / device tree |
|---|---|---|---|
| Screen | `/dev/graphics/fb0` | Qualcomm **MDSS** framebuffer (`mdss_fb`) → DSI panel | `CONFIG_FB_MSM_MDSS=y` |
| Touch | `/dev/input/eventN` | **Synaptics RMI4** over I²C | `CONFIG_TOUCHSCREEN_SYNAPTICS_I2C_RMI4=y`, `msm8992-bullhead-touch.dtsi` (`synaptics,rmi4`) |
| Volume keys | `/dev/input/eventN` | **gpio-keys** | `CONFIG_KEYBOARD_GPIO=y`, `msm8992-bullhead-misc.dtsi` (`gpio-keys`) |
| Power key | `/dev/input/eventN` | PMIC **qpnp-power-on** | `CONFIG_QPNP_POWER_ON=y` |
| Input core | — | evdev | `CONFIG_INPUT_EVDEV=y` |

`ueventd` (from the recovery ramdisk) creates the device nodes. minui's fbdev backend maps
`fb0`. If the framebuffer has room for two screens (`yres_virtual >= 2 × yres`), `gr_flip()` is a
cheap `FBIOPAN_DISPLAY` between them; otherwise minui draws in RAM and copies each frame into `fb0`.
minui's `events.cpp` opens every input device that has keys, or touch axes when touch is allowed.

There is no GPU, OpenGL or SurfaceFlinger involved: every pixel is computed on the CPU inside
`/sbin/recovery`.

## In QEMU (`virt` board)

QEMU has no MSM8992 model, so the QEMU kernel is the same bullhead source with a few
QEMU-only patches ([patches/qemu-kernel](../patches/qemu-kernel)) and config options
([qemu/kernel-qemu.config](../qemu/kernel-qemu.config)):

| What | Device file | Driver | Patch / option |
|---|---|---|---|
| Screen | `/dev/graphics/fb0` | **simplefb**: a framebuffer in plain RAM, described in the device tree | `CONFIG_FB_SIMPLE`, patch **0002** adds the 32-bit `a8b8g8r8` format (minui 8.1 needs 32 bpp) |
| Showing that RAM in a window | — | **`qemu_ramfb_setup.c`**: tells QEMU's `-device ramfb` the framebuffer's address/format over fw_cfg | patch **0003** |
| Keyboard | `/dev/input/event0` | **virtio-input**, backported from Linux 4.1 | patch **0004**, `CONFIG_VIRTIO_INPUT` |
| Boot log | `ttyAMA0` (early only) | PL011 early console | `CONFIG_SERIAL_AMBA_PL011`, `CONFIG_EARLY_PRINTK` |
| Busybox shell | `hvc0` | virtio console | `CONFIG_VIRTIO_CONSOLE`, `CONFIG_HVC_DRIVER` |
| (keep MDSS from crashing) | — | `mdss_dsi_status.c` ignores framebuffers that aren't MDSS | patch **0001** |

Because only the kernel underneath changes, **the same recovery ramdisk** runs on the phone and
in QEMU. The game can't tell the difference.

The details of each QEMU workaround are in [04-qemu-setup.md](04-qemu-setup.md).
