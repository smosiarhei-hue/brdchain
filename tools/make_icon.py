#!/usr/bin/env python3
"""Generate the app icon set.

iOS icons are square with no transparency allowed — the alpha channel has to be
flattened or the build pipeline rejects them. This writes opaque RGBA PNGs at
every size the asset catalog expects, so no image tooling is required beyond a
zlib writer.

Run:  python tools/make_icon.py
"""

from __future__ import annotations

import os
import struct
import zlib

OUT_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "MLBBServerPicker", "Sources", "Assets.xcassets", "AppIcon.appiconset")

# (points, scale, idiom). actool matches entries against an exact
# idiom+size+scale triple and rejects the set outright when a required slot is
# missing, so the full canonical matrix has to be present — including the
# 1024x1024 marketing icon.
ICON_SPECS = [
    (20, 2, "iphone"), (20, 3, "iphone"),
    (29, 2, "iphone"), (29, 3, "iphone"),
    (40, 2, "iphone"), (40, 3, "iphone"),
    (60, 2, "iphone"), (60, 3, "iphone"),
    (20, 1, "ipad"), (20, 2, "ipad"),
    (29, 1, "ipad"), (29, 2, "ipad"),
    (40, 1, "ipad"), (40, 2, "ipad"),
    (76, 1, "ipad"), (76, 2, "ipad"),
    (83.5, 2, "ipad"),
    (1024, 1, "ios-marketing"),
]

# Deep indigo to cyan, reading as a signal/wave motif.
BG_TOP = (22, 24, 58)
BG_BOTTOM = (10, 62, 96)
RING = (86, 214, 255)
CORE = (140, 240, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size: int) -> bytes:
    """Return raw RGBA rows for a size x size icon."""
    rows = []
    cx = cy = (size - 1) / 2.0
    # Geometry in fractions of the canvas so it scales to any pixel size.
    outer_r = size * 0.38
    inner_r = size * 0.22
    ring_w = max(1.5, size * 0.062)

    for y in range(size):
        row = bytearray()
        dy = y - cy
        for x in range(size):
            dx = x - cx
            d = (dx * dx + dy * dy) ** 0.5

            # Vertical background gradient.
            r, g, b = lerp(BG_TOP, BG_BOTTOM, y / max(1, size - 1))

            # Concentric ping waves radiating from the centre: two rings whose
            # thickness grows outward, reading as a signal/pulse.
            outer_ring = abs(d - outer_r) <= ring_w
            inner_ring = abs(d - inner_r) <= ring_w * 0.7

            if outer_ring or inner_ring:
                # Fade the ring slightly toward its outer edge for depth.
                target_r = outer_r if outer_ring else inner_r
                width = ring_w if outer_ring else ring_w * 0.7
                edge = min(1.0, abs(d - target_r) / width)
                intensity = 0.25 + 0.75 * (1.0 - edge)
                colour = lerp((r, g, b), RING, intensity)
                r, g, b = colour

            # Solid core at the origin.
            if d <= size * 0.055:
                r, g, b = CORE

            row += bytes((r, g, b, 255))
        # Each PNG scanline is prefixed with a filter-type byte. 0 = no filter.
        # Omitting it leaves the image one byte short per row, which makes it
        # undecodable even though the file looks like a valid PNG.
        rows.append(b"\x00" + bytes(row))
    return b"".join(rows)


def write_png(path: str, size: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">2I5B", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", header)
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as fh:
        fh.write(png)


def main() -> None:
    os.makedirs(OUT_ROOT, exist_ok=True)
    # Wipe first: a stale icon left behind by a rename becomes an unreferenced
    # child of the set, and actool rejects that even when the new file is valid.
    for stale in os.listdir(OUT_ROOT):
        if stale.endswith(".png"):
            os.remove(os.path.join(OUT_ROOT, stale))

    images = []

    for points, scale, idiom in ICON_SPECS:
        px = int(round(points * scale))
        suffix = "" if scale == 1 else f"@{scale}x"
        name = f"Icon-{idiom}-{points:g}{suffix}.png"

        target = os.path.join(OUT_ROOT, name)
        write_png(target, px, render(px))
        images.append(
            f'{{"size":"{points:g}x{points:g}","idiom":"{idiom}",'
            f'"filename":"{name}","scale":"{scale}x"}}'
        )
        print(f"  {name:34} {px}x{px}")

    contents = (
        "{\n  \"images\" : [\n    " + ",\n    ".join(images) + "\n  ],\n"
        "  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
    )
    with open(os.path.join(OUT_ROOT, "Contents.json"), "w", encoding="utf-8") as fh:
        fh.write(contents)

    print(f"\n{len(images)} images -> {os.path.normpath(OUT_ROOT)}")


if __name__ == "__main__":
    main()
