#!/usr/bin/env python3
"""Generate MacUnzip AppIcon PNGs from the minimal vector source.

No network, no external runtime dependency beyond Pillow (already available)
and the committed SVG geometry encoded below / written beside the iconset.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "App" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SVG_PATH = ICONSET / "icon-source.svg"
LOGO_SVG = ROOT / "Assets" / "Logo.svg"

# macOS icon pixel sizes: (filename, pixels)
SIZES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

# Quiet system-blue fill (not neon). Flat geometry, no text.
BG = (37, 99, 235, 255)  # #2563EB
FG = (255, 255, 255, 255)
FG_MUTED = (255, 255, 255, 230)


def squircle_mask(size: int) -> Image.Image:
    """Approximate Apple continuous-corner mask."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    # Continuous corner ≈ 22% of side for large icons; tighten slightly for tiny sizes.
    radius = max(3, int(size * (0.22 if size >= 64 else 0.28)))
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def render_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Background plate
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1),
        radius=max(3, int(size * (0.22 if size >= 64 else 0.28))),
        fill=BG,
    )

    # Container (rounded rect) — archive body
    inset = size * 0.22
    body = [inset, size * 0.20, size - inset, size * 0.82]
    body_radius = max(2, int(size * 0.08))
    draw.rounded_rectangle(body, radius=body_radius, outline=FG, width=max(1, size // 32))

    # Lid / top band
    lid_y = size * 0.32
    draw.line([(body[0], lid_y), (body[2], lid_y)], fill=FG_MUTED, width=max(1, size // 40))

    # Vertical zipper track
    cx = size / 2
    track_w = max(1, size // 28)
    draw.rounded_rectangle(
        [cx - track_w, size * 0.36, cx + track_w, size * 0.74],
        radius=track_w,
        fill=FG,
    )

    # Zipper teeth — alternating short bars (readable at 16px)
    tooth_count = 5 if size >= 64 else 3
    tooth_w = size * (0.09 if size >= 64 else 0.11)
    tooth_h = max(1, int(size * 0.035))
    gap = (size * 0.74 - size * 0.38) / (tooth_count + 1)
    for i in range(tooth_count):
        y = size * 0.38 + gap * (i + 1)
        if i % 2 == 0:
            x0, x1 = cx - tooth_w - track_w, cx - track_w * 0.2
        else:
            x0, x1 = cx + track_w * 0.2, cx + tooth_w + track_w
        draw.rounded_rectangle([x0, y - tooth_h / 2, x1, y + tooth_h / 2], radius=tooth_h / 2, fill=FG)

    # Pull tab (small capsule)
    pull_w = size * 0.12
    pull_h = size * 0.07
    pull = [cx - pull_w / 2, size * 0.28 - pull_h / 2, cx + pull_w / 2, size * 0.28 + pull_h / 2]
    draw.rounded_rectangle(pull, radius=max(1, int(pull_h / 2)), fill=FG)

    img.putalpha(squircle_mask(size))
    return img


SVG = """<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <!-- Minimal archive container. No text, no glow, flat geometry. -->
  <defs>
    <clipPath id="squircle">
      <rect x="0" y="0" width="1024" height="1024" rx="224" ry="224"/>
    </clipPath>
  </defs>
  <g clip-path="url(#squircle)">
    <rect width="1024" height="1024" fill="#2563EB"/>
    <rect x="225" y="205" width="574" height="635" rx="82" fill="none" stroke="#FFFFFF" stroke-width="36"/>
    <line x1="225" y1="328" x2="799" y2="328" stroke="#FFFFFF" stroke-width="28" stroke-linecap="round" opacity="0.92"/>
    <rect x="492" y="368" width="40" height="390" rx="20" fill="#FFFFFF"/>
    <rect x="360" y="420" width="120" height="36" rx="18" fill="#FFFFFF"/>
    <rect x="544" y="500" width="120" height="36" rx="18" fill="#FFFFFF"/>
    <rect x="360" y="580" width="120" height="36" rx="18" fill="#FFFFFF"/>
    <rect x="544" y="660" width="120" height="36" rx="18" fill="#FFFFFF"/>
    <rect x="360" y="740" width="120" height="36" rx="18" fill="#FFFFFF"/>
    <rect x="452" y="268" width="120" height="72" rx="36" fill="#FFFFFF"/>
  </g>
</svg>
"""


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    SVG_PATH.write_text(SVG, encoding="utf-8")
    LOGO_SVG.parent.mkdir(parents=True, exist_ok=True)
    LOGO_SVG.write_text(SVG, encoding="utf-8")

    for name, px in SIZES:
        render_icon(px).save(ICONSET / name, format="PNG")
        print(f"wrote {name} ({px}px)")

    # Marketing-sized master for README / site reuse
    master = render_icon(1024)
    master.save(ROOT / "Assets" / "logo-v2.png", format="PNG")
    print("wrote Assets/logo-v2.png")


if __name__ == "__main__":
    main()
