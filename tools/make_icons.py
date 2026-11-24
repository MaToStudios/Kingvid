#!/usr/bin/env python3
"""Generates the KingVid app icon, launch crown and in-app crown logos (one per accent colour).

Run from the repository root:  python3 tools/make_icons.py

The in-app logo is a pre-rendered image (not SwiftUI shapes + blend modes) so it renders identically
on every device: no overlays, masks or blend modes that could produce stray bars.
"""
import json
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "KingVid", "Resources", "Assets.xcassets")
SS = 3  # supersampling factor

PALETTES = {
    "Gold": [(0.0, (252, 238, 168)), (0.30, (233, 197, 82)), (0.55, (200, 154, 40)), (0.80, (150, 108, 22)), (1.0, (104, 72, 12))],
    "Champagne": [(0.0, (255, 249, 232)), (0.30, (241, 222, 174)), (0.55, (222, 192, 134)), (0.80, (172, 142, 88)), (1.0, (122, 96, 52))],
    "Rose": [(0.0, (253, 229, 217)), (0.30, (234, 182, 159)), (0.55, (215, 152, 128)), (0.80, (162, 108, 88)), (1.0, (114, 72, 58))],
}


def crown_masks(size):
    """Body (polygon + jewels) and band masks, supersampled. The band is flush with the body base,
    so the crown reads as one solid object rather than a crown sitting on a separate bar."""
    big = size * SS
    body = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(body)

    def P(x, y):
        return (x * big, (0.10 + y * 0.80) * big)

    pts = [(0.12, 0.81), (0.07, 0.30), (0.29, 0.54), (0.50, 0.12), (0.71, 0.54), (0.93, 0.30), (0.88, 0.81)]
    d.polygon([P(*p) for p in pts], fill=255)
    for cx, cy, r in [(0.07, 0.25, 0.055), (0.50, 0.075, 0.060), (0.93, 0.25, 0.055)]:
        x, y = P(cx, cy)
        rr = r * big
        d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=255)

    band = Image.new("L", (big, big), 0)
    bd = ImageDraw.Draw(band)
    x0, y0 = P(0.12, 0.81)
    x1, y1 = P(0.88, 0.97)
    bd.rounded_rectangle([x0, y0, x1, y1], radius=(y1 - y0) * 0.35, fill=255)
    # square off the top corners so the band joins the body flush
    bd.rectangle([x0, y0, x1, y0 + (y1 - y0) * 0.45], fill=255)

    seam = Image.new("L", (big, big), 0)
    sd = ImageDraw.Draw(seam)
    sx0, sy0 = P(0.12, 0.805)
    sx1, sy1 = P(0.88, 0.822)
    sd.rectangle([sx0, sy0, sx1, sy1], fill=255)
    return body, band, seam


def vertical_gradient(size, stops):
    ys = np.linspace(0, 1, size)
    out = np.zeros((size, size, 3), dtype=np.float32)
    ts = [s[0] for s in stops]
    for c in range(3):
        out[:, :, c] = np.interp(ys, ts, [s[1][c] for s in stops])[:, None]
    return Image.fromarray(out.astype(np.uint8), "RGB")


def crown_image(size, palette="Gold"):
    """RGBA crown on a transparent background (no padding artefacts, nothing outside the silhouette)."""
    stops = PALETTES[palette]
    big = size * SS
    body, band, seam = crown_masks(size)
    gold = vertical_gradient(big, stops)
    band_stops = [(0.0, stops[1][1]), (0.5, stops[2][1]), (1.0, stops[4][1])]
    gold_band = vertical_gradient(big, band_stops)

    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.paste(gold, (0, 0), body)
    img.paste(gold_band, (0, 0), band)
    dark = Image.new("RGBA", (big, big), tuple(stops[4][1]) + (255,))
    img.paste(dark, (0, 0), ImageChops.multiply(seam, ImageChops.lighter(body, band)))

    # thin specular edge along the silhouette top
    union = ImageChops.lighter(body, band)
    blur = union.filter(ImageFilter.GaussianBlur(SS * 2))
    edge = np.clip(np.asarray(union, dtype=np.float32) / 255.0 - np.asarray(blur, dtype=np.float32) / 255.0, 0, 1) * 1.6
    glow = np.zeros((big, big, 4), dtype=np.uint8)
    glow[:, :, 0], glow[:, :, 1], glow[:, :, 2] = 255, 246, 205
    glow[:, :, 3] = np.clip(edge * 255, 0, 255).astype(np.uint8)
    img = Image.alpha_composite(img, Image.fromarray(glow, "RGBA"))

    # gems on the band
    d = ImageDraw.Draw(img)
    for gx in (0.29, 0.50, 0.71):
        cx = gx * big
        cy = (0.10 + 0.895 * 0.80) * big
        r = 0.026 * big
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(30, 20, 4, 255))
        r2 = r * 0.42
        d.ellipse([cx - r2 - r * 0.15, cy - r2 - r * 0.2, cx + r2 - r * 0.15, cy + r2 - r * 0.2], fill=(255, 236, 160, 210))
    return img.resize((size, size), Image.LANCZOS)


def crop_to_content(img, pad_ratio=0.0):
    """Crop transparent margins so the logo is optically centred when used with scaledToFit."""
    bbox = img.getbbox()
    if not bbox:
        return img
    cropped = img.crop(bbox)
    w, h = cropped.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - w) // 2, (side - h) // 2))
    return canvas


def make_app_icon(path, size=1024):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    r = np.clip(np.sqrt((xx - size / 2) ** 2 + (yy - size * 0.42) ** 2) / (size * 0.75), 0, 1)
    inner = np.array([34, 35, 38], dtype=np.float32)
    outer = np.array([4, 4, 5], dtype=np.float32)
    bg = inner[None, None, :] * (1 - r[:, :, None]) + outer[None, None, :] * r[:, :, None]
    base = Image.fromarray(bg.astype(np.uint8), "RGB").convert("RGBA")

    crown = crop_to_content(crown_image(1600, "Gold"))
    target = int(size * 0.62)
    crown = crown.resize((target, target), Image.LANCZOS)
    ox = (size - crown.width) // 2
    oy = (size - crown.height) // 2

    shadow = Image.new("RGBA", crown.size, (0, 0, 0, 0))
    shadow.putalpha(crown.split()[3].point(lambda v: int(v * 0.55)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.02))
    base.alpha_composite(shadow, (ox, oy + int(size * 0.018)))
    glow = Image.new("RGBA", crown.size, (0, 0, 0, 0))
    glow.paste(Image.new("RGBA", crown.size, (230, 180, 60, 255)), (0, 0), crown.split()[3].point(lambda v: int(v * 0.30)))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.035))
    base.alpha_composite(glow, (ox, oy))
    base.alpha_composite(crown, (ox, oy))
    base.convert("RGB").save(path, "PNG")


def write_imageset(name, palette, sizes):
    folder = os.path.join(ROOT, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    big = crop_to_content(crown_image(1200, palette))
    images = []
    for scale, px in sizes:
        fname = name + (".png" if scale == 1 else "@%dx.png" % scale)
        big.resize((px, px), Image.LANCZOS).save(os.path.join(folder, fname))
        images.append({"filename": fname, "idiom": "universal", "scale": "%dx" % scale})
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"author": "xcode", "version": 1}}, f, indent=2)


def main():
    icon_dir = os.path.join(ROOT, "AppIcon.appiconset")
    make_app_icon(os.path.join(icon_dir, "icon-1024.png"))
    with open(os.path.join(icon_dir, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)

    # Launch screen crown + the three in-app logos (square, content-cropped, transparent)
    write_imageset("LaunchCrown", "Gold", [(1, 150), (2, 300), (3, 450)])
    write_imageset("CrownGold", "Gold", [(1, 140), (2, 280), (3, 420)])
    write_imageset("CrownChampagne", "Champagne", [(1, 140), (2, 280), (3, 420)])
    write_imageset("CrownRose", "Rose", [(1, 140), (2, 280), (3, 420)])

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
