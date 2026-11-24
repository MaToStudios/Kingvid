#!/usr/bin/env python3
"""Generates the KingVid app icon and launch crown artwork.

Run from the repository root:  python3 tools/make_icons.py
The crown geometry here mirrors `CrownShape` in KingVid/Design/CrownShape.swift.
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "KingVid", "Resources", "Assets.xcassets")
SS = 3  # supersampling factor


def crown_mask(size, pad=0.0):
    """Returns an 'L' mask (size x size, supersampled) of the crown silhouette, and the band mask."""
    big = size * SS
    body = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(body)
    box = 1.0 - 2 * pad

    def P(x, y):
        return ((pad + x * box) * big, (pad + y * box * 0.80 + 0.10 * box) * big)

    pts = [(0.12, 0.80), (0.07, 0.30), (0.29, 0.54), (0.50, 0.12), (0.71, 0.54), (0.93, 0.30), (0.88, 0.80)]
    d.polygon([P(*p) for p in pts], fill=255)
    for cx, cy, r in [(0.07, 0.25, 0.055), (0.50, 0.075, 0.060), (0.93, 0.25, 0.055)]:
        x, y = P(cx, cy)
        rr = r * box * big
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)
    band = Image.new("L", (big, big), 0)
    bd = ImageDraw.Draw(band)
    x0, y0 = P(0.14, 0.82)
    x1, y1 = P(0.86, 0.97)
    bd.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) / 2.2, fill=255)
    return body, band


def vertical_gradient(size, stops):
    """stops: list of (t, (r,g,b))."""
    h = size
    ys = np.linspace(0, 1, h)
    out = np.zeros((h, size, 3), dtype=np.float32)
    ts = [s[0] for s in stops]
    for c in range(3):
        col = np.interp(ys, ts, [s[1][c] for s in stops])
        out[:, :, c] = col[:, None]
    return Image.fromarray(out.astype(np.uint8), "RGB")


GOLD = [(0.0, (252, 238, 168)), (0.30, (233, 197, 82)), (0.55, (200, 154, 40)), (0.80, (150, 108, 22)), (1.0, (104, 72, 12))]
GOLD_BAND = [(0.0, (245, 220, 120)), (0.5, (190, 144, 36)), (1.0, (118, 82, 14))]


def crown_image(size, pad=0.0, gems=True):
    """RGBA crown on transparent background."""
    big = size * SS
    body, band = crown_mask(size, pad)
    gold = vertical_gradient(big, GOLD)
    gold_band = vertical_gradient(big, GOLD_BAND)
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.paste(gold, (0, 0), body)
    # darker separation line between body and band
    sep = band.filter(ImageFilter.MaxFilter(SS * 4 + 1))
    sep_edge = Image.new("L", (big, big), 0)
    sep_edge.paste(sep, (0, 0))
    dark = Image.new("RGBA", (big, big), (40, 28, 4, 255))
    img.paste(dark, (0, 0), ImageChops_subtract(sep_edge, band))
    img.paste(gold_band, (0, 0), band)
    # specular highlight: thin light edge along the top of the body
    hi = body.filter(ImageFilter.GaussianBlur(SS * 2))
    hi_arr = np.asarray(hi, dtype=np.float32) / 255.0
    body_arr = np.asarray(body, dtype=np.float32) / 255.0
    edge = np.clip(body_arr - hi_arr, 0, 1) * 1.8
    glow = np.zeros((big, big, 4), dtype=np.uint8)
    glow[:, :, 0] = 255
    glow[:, :, 1] = 246
    glow[:, :, 2] = 200
    glow[:, :, 3] = np.clip(edge * 255, 0, 255).astype(np.uint8)
    img = Image.alpha_composite(img, Image.fromarray(glow, "RGBA"))
    if gems:
        d = ImageDraw.Draw(img)
        box = 1.0 - 2 * pad
        for gx in (0.29, 0.50, 0.71):
            cx = (pad + gx * box) * big
            cy = (pad + 0.895 * box * 0.80 + 0.10 * box) * big
            r = 0.028 * box * big
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(30, 20, 4, 255))
            r2 = r * 0.45
            d.ellipse([cx - r2 - r * 0.15, cy - r2 - r * 0.2, cx + r2 - r * 0.15, cy + r2 - r * 0.2], fill=(255, 236, 160, 200))
    return img.resize((size, size), Image.LANCZOS)


def ImageChops_subtract(a, b):
    from PIL import ImageChops
    return ImageChops.subtract(a, b)


def make_app_icon(path, size=1024):
    # dark graphite radial background
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = size / 2
    r = np.sqrt((xx - cx) ** 2 + (yy - cy * 0.85) ** 2) / (size * 0.75)
    r = np.clip(r, 0, 1)
    inner = np.array([34, 35, 38], dtype=np.float32)
    outer = np.array([4, 4, 5], dtype=np.float32)
    bg = inner[None, None, :] * (1 - r[:, :, None]) + outer[None, None, :] * r[:, :, None]
    base = Image.fromarray(bg.astype(np.uint8), "RGB").convert("RGBA")

    # gold ring
    ring = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    m = int(size * 0.045 * SS)
    rd.rounded_rectangle([m, m, size * SS - m, size * SS - m], radius=int(size * 0.2 * SS), outline=(212, 175, 55, 90), width=int(size * 0.004 * SS))
    base = Image.alpha_composite(base, ring.resize((size, size), Image.LANCZOS))

    crown = crown_image(int(size * 0.66), 0.0)
    # soft shadow
    shadow = Image.new("RGBA", crown.size, (0, 0, 0, 0))
    shadow.putalpha(crown.split()[3].point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.02))
    ox = (size - crown.width) // 2
    oy = int(size * 0.17)
    base.alpha_composite(shadow, (ox, oy + int(size * 0.018)))
    # glow
    glow = Image.new("RGBA", crown.size, (0, 0, 0, 0))
    g = Image.new("RGBA", crown.size, (230, 180, 60, 255))
    glow.paste(g, (0, 0), crown.split()[3].point(lambda v: int(v * 0.35)))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.035))
    base.alpha_composite(glow, (ox, oy))
    base.alpha_composite(crown, (ox, oy))
    base.convert("RGB").save(path, "PNG")


def main():
    icon_dir = os.path.join(ROOT, "AppIcon.appiconset")
    make_app_icon(os.path.join(icon_dir, "icon-1024.png"))
    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

    launch_dir = os.path.join(ROOT, "LaunchCrown.imageset")
    images = []
    for scale, px in ((1, 150), (2, 300), (3, 450)):
        name = "LaunchCrown.png" if scale == 1 else "LaunchCrown@%dx.png" % scale
        crown_image(px, 0.0).save(os.path.join(launch_dir, name))
        images.append({"filename": name, "idiom": "universal", "scale": "%dx" % scale})
    with open(os.path.join(launch_dir, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)

    def color_set(folder, rgb):
        r, g, b = rgb
        content = {"colors": [{"color": {"color-space": "srgb", "components": {"alpha": "1.000", "red": "%.3f" % (r / 255), "green": "%.3f" % (g / 255), "blue": "%.3f" % (b / 255)}}, "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}
        with open(os.path.join(ROOT, folder, "Contents.json"), "w") as f:
            json.dump(content, f, indent=2)

    color_set("AccentColor.colorset", (212, 175, 55))
    color_set("LaunchBackground.colorset", (7, 7, 8))
    with open(os.path.join(ROOT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("icons written")


if __name__ == "__main__":
    main()
