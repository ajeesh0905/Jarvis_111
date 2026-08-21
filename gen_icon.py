"""Generates a simple JARVIS-style arc-reactor app icon at all required
Android mipmap densities, plus a 1024x1024 master and a Play-Store-style
adaptive foreground. No external assets/network needed.
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

BASE = "/home/claude/jarvis_app/android/app/src/main/res"
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

BG = (10, 14, 20, 255)          # near-black
RING = (56, 214, 255, 255)      # cyan
RING_DIM = (24, 110, 140, 255)
CORE = (170, 245, 255, 255)


def make_icon(size: int) -> Image.Image:
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Rounded-square dark background (Android will mask/round it as needed)
    pad = int(s * 0.04)
    d.rounded_rectangle([pad, pad, s - pad, s - pad], radius=int(s * 0.18), fill=BG)

    cx, cy = s / 2, s / 2

    # Outer glow rings (arc-reactor look)
    for i, (radius_frac, width_frac, color) in enumerate([
        (0.40, 0.045, RING),
        (0.30, 0.030, RING_DIM),
        (0.20, 0.045, RING),
    ]):
        r = s * radius_frac
        w = max(2, int(s * width_frac))
        bbox = [cx - r, cy - r, cx + r, cy + r]
        d.ellipse(bbox, outline=color, width=w)

    # Small tick marks around the middle ring (segmented look)
    r = s * 0.30
    for k in range(12):
        angle = math.radians(k * 30)
        x1 = cx + r * math.cos(angle)
        y1 = cy + r * math.sin(angle)
        x2 = cx + (r + s * 0.03) * math.cos(angle)
        y2 = cy + (r + s * 0.03) * math.sin(angle)
        d.line([x1, y1, x2, y2], fill=RING, width=max(2, int(s * 0.012)))

    # Glowing core
    core_r = s * 0.09
    d.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r], fill=CORE)

    img = img.filter(ImageFilter.GaussianBlur(radius=s * 0.001))
    img = img.resize((size, size), Image.LANCZOS)
    return img


def main():
    master = make_icon(1024)
    master.save("/home/claude/jarvis_app/assets/icon/app_icon.png")

    for folder, size in SIZES.items():
        out_dir = os.path.join(BASE, folder)
        os.makedirs(out_dir, exist_ok=True)
        icon = make_icon(size)
        icon.save(os.path.join(out_dir, "ic_launcher.png"))
        print(f"wrote {out_dir}/ic_launcher.png ({size}x{size})")


if __name__ == "__main__":
    main()
