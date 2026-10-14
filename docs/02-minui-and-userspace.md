# 2. minui, recovery, and why everything is userspace

## Recovery is its own little Linux system

On the Nexus 5X (Android 8.1, non-A/B) the **recovery partition** holds `recovery.img`: its own
copy of the kernel plus a **recovery ramdisk**. The bootloader decides whether to boot `boot` or
`recovery`. `fastboot boot recovery.img` hands it the same kernel and ramdisk straight from the PC,
without writing any partition.

Once booted, everything comes from that ramdisk:

| Running in recovery | Not running |
|---|---|
| `init` with recovery's own `init.rc`, `ueventd`, `/sbin/recovery`, `healthd`, `minivold` (LineageOS), recovery-mode `adbd`, `charger` | zygote, ART, system_server, SurfaceFlinger, HALs, GPU drivers, apps. `/system` isn't even mounted |

Recovery and Android only talk through storage: Android writes a command to the **misc** partition
(bootloader control block) and/or `/cache/recovery/command` and reboots, recovery runs it and leaves
`/cache/recovery/last_log`. Road Fighter only auto-starts when there is **no** such command.

## minui

minui is Google's tiny graphics + input library for recovery
(`bootable/recovery/minui/`, in AOSP since the 2008 initial code drop). In LineageOS 15.1 it is about
2,500 lines:

| File | Lines | Role |
|---|---|---|
| `graphics.cpp` | 375 | `gr_init`, `gr_fill`, `gr_blit`, `gr_text`, `gr_flip`, fonts, choosing a backend |
| `graphics_fbdev.cpp` | 172 | fbdev backend: `/dev/graphics/fb0` (bullhead and QEMU use this) |
| `graphics_drm.cpp` | 395 | DRM/KMS backend (newer devices) |
| `graphics_adf.cpp` | 198 | ADF backend (Google's short-lived display framework) |
| `events.cpp` | 266 | `/dev/input/event*` + epoll, key/touch callbacks |
| `resources.cpp` | 527 | libpng loading of images, animations, localized text, fonts |

What it can draw: filled rectangles (with one color and alpha), opaque blits, single-color alpha
masks (text, icons) and bitmap text. No scaling (except a LineageOS addition), no transparency for
images, no shapes. Road Fighter needed nothing new from minui. It uses
`gr_fb_width/height`, `gr_blit`, `gr_fill`, `gr_color`, `gr_text`, `gr_measure`, `gr_menu_font`,
`gr_clear` and `gr_flip`, and does compositing, clipping, alpha, scaling and tinting itself.

## All of it is userspace

`/sbin/recovery` is an ordinary statically linked program. minui is compiled into it. Road Fighter
is compiled into it too. They reach the hardware only through **system calls on device files**,
like any Linux program:

```c
// minui/graphics_fbdev.cpp
fd = open("/dev/graphics/fb0", O_RDWR);
ioctl(fd, FBIOGET_FSCREENINFO, &fi);           // stride, memory size
ioctl(fd, FBIOGET_VSCREENINFO, &vi);           // resolution, pixel format
bits = mmap(0, fi.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);   // the screen's memory
ioctl(fd, FBIOPAN_DISPLAY, &vi);               // flip between the two buffers (double buffering)

// minui/events.cpp
open("/dev/input/eventN"); ioctl(fd, EVIOCGBIT(...));   // which keys / axes the device has
epoll_wait(...); read(fd, &input_event, ...);           // key and touch events
```

Headers like `<linux/fb.h>` and `<linux/input.h>` are the kernel's **UAPI** headers: just the
structs and ioctl numbers that userspace needs. After the `mmap`, drawing a pixel is a plain memory
write. The kernel driver makes that memory appear on the panel.

```
userspace   /sbin/recovery
            ├─ recovery.cpp / screen_ui.cpp (menus)        roadfighter.cpp (game)
            ├─ RecoveryUI input thread → event queue  ←──── PollInputEvent()
            └─ minui: gr_* (graphics)   ev_* (input)
                       │ open/ioctl/mmap        │ epoll/read
──────────────────────┼────────────────────────┼──────────────────────────────
kernel                 /dev/graphics/fb0        /dev/input/event*
                       framebuffer driver       input drivers
```

The drivers behind those two device files are described in [03-drivers.md](03-drivers.md).

## The game loop inside recovery

```
main()                                         (recovery.cpp)
 ├─ ScreenRecoveryUI::Init → gr_init() + ev_init() + input thread
 ├─ no command? ──► run_road_fighter(ui)       (auto-start, patch 0002)
 └─ prompt_and_wait() menu ── Advanced ▸ Play Road Fighter ──► run_road_fighter(ui)

run_road_fighter():
  Init(): load /etc/roadfighter/*.png (libpng) → scale to screen → pre-tint verges → draw buttons
  loop every ~33 ms:
     Update(dt)     road/blue car position, collisions, score, level
     Render()       compose frame → gr_blit → dashboard text → gr_flip
     PollInputEvent until the next frame → steer / restart / exit
```

While the game runs, recovery's own UI is idle. The menu only redraws while it waits for a key,
and it isn't waiting, so the two never draw at the same time.
