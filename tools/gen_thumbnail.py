#!/usr/bin/env python3
"""SHELF LIFE thumbnail — RULE-BADGE-FORWARD (binding launch condition).

Badges DOMINATE the first visual read: four oversized composable rule badges
fill ~70% of the frame; a mini shelf scene sits small at the bottom.
Deterministic (no randomness). Output: cover/thumbnail.png 1152x648 + a
square crop assets/branding/thumbnail-square.png.
"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1152, 648
BG = (23, 26, 33)          # #171a21
PANEL = (35, 40, 51)
GOOD = (61, 220, 132)
BAD = (255, 92, 116)
WARN = (255, 200, 87)
INK = (232, 236, 244)
DIM = (154, 163, 181)

CAT_COLORS = {"P": (111, 206, 98), "D": (242, 177, 52), "M": (224, 82, 99), "B": (183, 139, 240)}

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
if not os.path.exists(FONT_PATH):
    FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def font(size: int):
    return ImageFont.truetype(FONT_PATH, size)


def badge(draw: ImageDraw.ImageDraw, cx: int, cy: int, label: str, sub: str,
          color, w: int = 520, h: int = 92):
    x0, y0 = cx - w // 2, cy - h // 2
    draw.rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=h // 2,
                           fill=PANEL, outline=color, width=6)
    # dot
    r = 14
    dx = x0 + 44
    draw.ellipse([dx - r, cy - r, dx + r, cy + r], fill=color)
    f_main = font(32)
    f_sub = font(17)
    draw.text((x0 + 76, y0 + 12), label, font=f_main, fill=INK)
    draw.text((x0 + 78, y0 + h - 30), sub, font=f_sub, fill=DIM)


def shelf_scene(base: Image.Image, y0: int):
    """Small colorful shelf strip at the bottom — context, not the subject."""
    d = ImageDraw.Draw(base)
    bay_w, cell_h = 120, 44
    gap = 18
    total = 4 * bay_w + 3 * gap
    x = (W - total) // 2
    cats = ["M", "D", "B", "P"]
    for i, c in enumerate(cats):
        bx = x + i * (bay_w + gap)
        d.rounded_rectangle([bx, y0, bx + bay_w, y0 + cell_h * 2 + 12],
                            radius=10, fill=PANEL, outline=(57, 64, 79), width=3)
        col = CAT_COLORS[c]
        for row in range(2):
            ix = bx + 12
            iy = y0 + 8 + row * (cell_h + 2)
            d.rounded_rectangle([ix, iy, ix + bay_w - 24, iy + cell_h],
                                radius=8, fill=col)
            d.text((ix + (bay_w - 24) // 2 - 12, iy + 8), c, font=font(26),
                   fill=(20, 20, 20))
    return base


def main():
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # Title — present but subordinate to badges
    f_title = font(44)
    tw = d.textlength("SHELF LIFE", font=f_title)
    d.text(((W - tw) / 2, 28), "SHELF LIFE", font=f_title, fill=INK)

    # FOUR OVERSIZED RULE BADGES — the first visual read
    badges = [
        ("LABELS FACE OUT", "facing rule", WARN),
        ("HEAVY BELOW LIGHT", "weight rule", GOOD),
        ("CATEGORY TOGETHER", "adjacency rule", (111, 154, 240)),
        ("OLDEST AT FRONT", "FIFO expiry rule", BAD),
    ]
    y = 130
    for label, sub, color in badges:
        badge(d, W // 2, y, label, sub, color)
        y += 108

    # mini shelf strip
    shelf_scene(img, H - 116)

    out_main = os.path.join(ROOT, "cover", "thumbnail.png")
    os.makedirs(os.path.dirname(out_main), exist_ok=True)
    img.save(out_main)
    # square crop for portals needing 1:1
    sq = img.crop(((W - H) // 2, 0, (W - H) // 2 + H, H)).resize((512, 512))
    sq_out = os.path.join(ROOT, "assets", "branding", "thumbnail-square.png")
    os.makedirs(os.path.dirname(sq_out), exist_ok=True)
    sq.save(sq_out)
    print("saved", out_main, "and", sq_out)


if __name__ == "__main__":
    main()
