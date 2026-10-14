#!/usr/bin/env python3
"""Grab the recovery screen of a running qemu/run-recovery.sh as PNG (reads guest RAM over QMP).

Usage: qemu/screenshot.py                 -> $WORK/screenshots/recovery-<time>.png (+ screenshots/latest.png)
       qemu/screenshot.py --watch [secs]  -> keep refreshing $WORK/screenshots/latest.png
"""
import json, os, socket, sys, tempfile, time
from PIL import Image

Q = os.environ.get("WORK", os.path.expanduser("~/bullhead-qemu"))
SOCK = os.environ.get("QMP_SOCK", os.path.join(Q, "qmp.sock"))
FB_BASE, W, H = 0x80000000, 1080, 1920      # must match gen-dtb.sh
SHOTS = os.path.join(Q, "screenshots")


def qmp(cmd, **args):
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    f = s.makefile("rw")
    f.readline()                                   # greeting
    for c in ({"execute": "qmp_capabilities"}, {"execute": cmd, "arguments": args}):
        f.write(json.dumps(c) + "\n"); f.flush()
        while True:
            r = json.loads(f.readline())
            if "return" in r or "error" in r:
                break
        if "error" in r:
            raise RuntimeError(r["error"])
    s.close()


def grab(path):
    with tempfile.NamedTemporaryFile(dir=SHOTS, suffix=".raw") as raw:
        qmp("pmemsave", val=FB_BASE, size=W * H * 4, filename=raw.name)
        img = Image.frombytes("RGB", (W, H), raw.read(), "raw", "RGBX")
    tmp = path + ".tmp.png"
    img.save(tmp)
    os.replace(tmp, path)                          # atomic, so viewers never see a half-written file


os.makedirs(SHOTS, exist_ok=True)
latest = os.path.join(SHOTS, "latest.png")
if len(sys.argv) > 1 and sys.argv[1] == "--watch":
    period = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    print(f"refreshing {latest} every {period}s (Ctrl-C to stop)")
    while True:
        grab(latest)
        time.sleep(period)
else:
    out = os.path.join(SHOTS, time.strftime("recovery-%Y%m%d-%H%M%S.png"))
    grab(out)
    grab(latest)
    print(out)
