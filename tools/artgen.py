#!/usr/bin/env python3
"""SHELF LIFE art pass — seeded procedural texture/prop/moodboard generator.

Mirrors the custodian-accepted SHADOW FORM pipeline (shadow-form branch
assets/art-pass, tools/artgen.py): machine has no diffusion install; seeded
PIL rendering gives style-lock by construction + deterministic regen (same
seed -> same bytes). Tileability is achieved BY CONSTRUCTION (patterns whose
period divides SIZE, wrapped draws near borders) — no post-hoc wrap blending.

Outputs land under assets/art_pass/<room>/ as:
  - tileable surface textures (albedo RGB 1024x1024)
  - prop plates (RGBA cutout sheets)
  - room mood-board composite plate (the "THE ROOM" one-look pitch)

Rooms (direction pack D1):
  corner_shop_am  — CORNER SHOP AM: morning corner shop, warm daylight,
                    wooden counter, pastel tins, dust motes in sun.
  night_market_pm — NIGHT MARKET PM: lantern-lit stall after dark, teal
                    dusk, paper lanterns, wet-street neon reflections.

Usage: python3 tools/artgen.py [OUT_DIR] [SEED]
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/art_pass"
SEED = int(sys.argv[2]) if len(sys.argv) > 2 else 20260822
SIZE = 1024

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


# ---------- shared helpers (mirrored from shadow-form artgen.py) ----------
def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", path)


def wrap_blur(img, radius):
    """Tile-aware Gaussian blur: blur a 3x3 padded canvas, crop center.

    Plain ImageFilter.GaussianBlur under-weights border pixels (outside =
    black), producing a brightness halo that shows as seams when tiled.
    """
    w, h = img.size
    big = Image.new(img.mode, (w * 3, h * 3))
    for ox in (-w, 0, w):
        for oy in (-h, 0, h):
            big.paste(img, (w + ox, h + oy))
    return big.filter(ImageFilter.GaussianBlur(radius)).crop((w, h, w + w, h + h))


def grain_overlay(img, amount=14):
    g = Image.effect_noise(img.size, 24).convert("L")
    return Image.blend(img, Image.merge("RGB", (g, g, g)), amount / 255)


def wrap_ellipse(d, cx, cy, rx, ry, fill, outline=None, width=0):
    """Draw an ellipse 9x so it wraps across tile edges."""
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            d.ellipse([cx + ox - rx, cy + oy - ry, cx + ox + rx, cy + oy + ry],
                      fill=fill, outline=outline, width=width)


def wrap_line(d, pts, fill, width=2):
    """Draw a polyline 9x so it wraps across tile edges."""
    for ox in (-SIZE, 0, SIZE):
        for oy in (-SIZE, 0, SIZE):
            d.line([(x + ox, y + oy) for x, y in pts], fill=fill, width=width)


def vstrip_mask(rnd, count, wmin, wmax, amin, amax):
    """Full-height vertical streak mask (columns tile in both axes)."""
    wear = Image.new("L", (SIZE, SIZE), 0)
    wd = ImageDraw.Draw(wear)
    for _ in range(count):
        x = rnd.randint(0, SIZE - 1)
        wdt = rnd.randint(wmin, wmax)
        for ox in (-SIZE, 0, SIZE):
            wd.rectangle([x + ox, 0, x + ox + wdt, SIZE], fill=rnd.randint(amin, amax))
    return wrap_blur(wear, 10)


# ======================================================================
# ROOM A — CORNER SHOP AM
# ======================================================================
def am_wallpaper(rnd):
    """Warm cream wallpaper with faded awning stripe band and hairline cracks.

    Tiles by construction: stripe period 256 divides SIZE; cracks are
    full-height polylines whose x-jitter repeats at borders; base tone flat
    (all falloff belongs to the light rig, not the albedo).
    """
    base_c, dark_c = (214, 196, 160), (188, 168, 130)
    img = Image.new("RGB", (SIZE, SIZE), base_c)
    # subtle vertical two-tone stripes (painted wall, 256px period)
    pat = Image.new("L", (SIZE, SIZE), 0)
    pd = ImageDraw.Draw(pat)
    step = 256
    for gx in range(0, SIZE, step):
        for ox in (-SIZE, 0, SIZE):
            pd.rectangle([gx + ox, 0, gx + ox + step // 2, SIZE], fill=26)
    pat = wrap_blur(pat, 18)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), dark_c), img, pat)
    # hairline plaster cracks (wrapped full-height jittered columns)
    crack = Image.new("L", (SIZE, SIZE), 0)
    cd = ImageDraw.Draw(crack)
    for _ in range(7):
        x = rnd.randint(40, SIZE - 40)
        pts, y, xx = [], 0, x
        while y <= SIZE:
            pts.append((xx, y))
            y += rnd.randint(48, 90)
            xx += rnd.choice([-14, -7, 0, 7, 14])
        wrap_line(cd, pts, rnd.randint(30, 60), 2)
    crack = wrap_blur(crack, 2)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), (150, 132, 100)), img, crack)
    return grain_overlay(img, 9)


def am_counterwood(rnd):
    """Honey oak counter planks: sine grain with integer periods + seams.

    Tiles by construction: grain k=6 full cycles over SIZE; seam every 256;
    knots kept clear of the border ring so wrapped copies never clip them.
    """
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    light_c, dark_c = (166, 118, 66), (128, 88, 46)
    for y in range(SIZE):
        row_t = y / SIZE
        for x in range(0, SIZE):
            g = math.sin(2 * math.pi * 6 * x / SIZE + 3.0 * math.sin(
                2 * math.pi * 2 * y / SIZE)) * 0.5 + 0.5
            fine = math.sin(2 * math.pi * 24 * x / SIZE) * 0.5 + 0.5
            t = max(0.0, min(1.0, g * 0.75 + fine * 0.25 + row_t * 0.06))
            px[x, y] = lerp(dark_c, light_c, t)
    d = ImageDraw.Draw(img)
    for sx in range(0, SIZE, 256):
        for ox in (-SIZE, 0, SIZE):
            d.rectangle([sx + ox, 0, sx + ox + 4, SIZE], fill=(96, 64, 32))
    # knots (kept >=96px from any border)
    for _ in range(5):
        kx, ky = rnd.randint(96, SIZE - 96), rnd.randint(96, SIZE - 96)
        for rr, cc in ((16, (110, 74, 38)), (10, (92, 60, 30)), (5, (70, 45, 22))):
            d.ellipse([kx - rr, ky - rr, kx + rr, ky + rr], fill=cc)
    return grain_overlay(img, 8)


def am_props_plate(rnd):
    """CORNER SHOP AM prop plate — RGBA cutout sheet, transparent ground."""
    W, H = 2048, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f_reg = ImageFont.truetype(FONT_REG, 26)

    def label(txt, xy, col=(90, 70, 50)):
        d.text(xy, txt, font=f_reg, fill=col + (255,))

    # --- hanging produce scale (brass pan scale) ---
    sx, sy = 300, 300
    d.line([(sx, sy - 180), (sx, sy - 120)], fill=(122, 94, 52, 255), width=10)
    d.pieslice([sx - 60, sy - 200, sx + 60, sy - 80], 180, 360, fill=(176, 134, 76, 255))
    d.line([(sx - 54, sy - 120), (sx + 54, sy - 120)], fill=(122, 94, 52, 255), width=8)
    for hx in (-54, 54):
        d.line([(sx + hx, sy - 120), (sx + hx * 0.55, sy - 20)], fill=(122, 94, 52, 255), width=6)
    d.chord([sx - 130, sy - 30, sx + 130, sy + 90], 0, 180, fill=(196, 156, 92, 255),
            outline=(122, 94, 52, 255), width=8)
    label("brass pan scale", (sx - 90, sy + 120))

    # --- glass jars with pastel lids ---
    for j, jc in enumerate(((226, 178, 190), (186, 210, 170), (240, 208, 150))):
        jx = 700 + j * 190
        jy = 420
        d.rounded_rectangle([jx, jy, jx + 130, jy + 260], radius=26,
                            fill=(232, 238, 240, 120), outline=(150, 160, 165, 255), width=8)
        d.rounded_rectangle([jx - 8, jy - 34, jx + 138, jy + 12], radius=16, fill=jc + (255,))
        d.rectangle([jx + 30, jy + 90, jx + 100, jy + 170], fill=(250, 246, 236, 230))
        label("", (0, 0))
    label("glass jars, pastel lids", (700, 720))

    # --- stacked delivery crates ---
    for c in range(2):
        cx, cy = 1350 + c * 30, 560 + c * 130
        d.rectangle([cx, cy, cx + 330, cy + 120], fill=(172, 128, 78, 255))
        d.rectangle([cx, cy, cx + 330, cy + 120], outline=(120, 86, 48, 255), width=8)
        d.line([(cx, cy + 40), (cx + 330, cy + 40)], fill=(140, 102, 58, 255), width=6)
        d.line([(cx, cy + 82), (cx + 330, cy + 82)], fill=(140, 102, 58, 255), width=6)
    label("delivery crates", (1380, 850))

    # --- awning strip sample (red/cream) ---
    ax, ay = 1620, 220
    for i in range(8):
        col = (198, 84, 74, 255) if i % 2 == 0 else (238, 226, 202, 255)
        d.polygon([(ax + i * 50, ay), (ax + i * 50 + 50, ay),
                   (ax + i * 50 + 50, ay + 150), (ax + i * 50 + 25, ay + 185),
                   (ax + i * 50, ay + 150)], fill=col)
    label("awning valance", (1610, 430))
    return img


def am_moodboard(tex_wall, tex_wood, props):
    """One-look composite: room sketch + texture chips + palette bar."""
    W, H = 2048, 1400
    mb = Image.new("RGB", (W, H), (34, 28, 22))
    d = ImageDraw.Draw(mb)
    f_h = ImageFont.truetype(FONT_BOLD, 44)
    f_s = ImageFont.truetype(FONT_REG, 26)

    # left: painted room vignette (counter = payoff surface)
    room = Image.new("RGB", (1150, H - 120), (222, 206, 172))
    rd = ImageDraw.Draw(room, "RGBA")
    # back wall shading + window pool of morning light
    rd.rectangle([0, 0, 1150, 700], fill=(216, 198, 162))
    rd.polygon([(120, 0), (520, 0), (760, 1032), (240, 1032)], fill=(255, 244, 214, 120))
    # shelf rails on back wall
    tint_cycle = ((226, 178, 190), (186, 210, 170), (240, 208, 150), (170, 190, 214))
    ti = 0
    for ry in (300, 480, 660):
        rd.rectangle([140, ry, 1010, ry + 26], fill=(150, 108, 62))
        bx = 170
        while bx < 960:
            bw2 = 60 + (ti * 37 % 70)
            rd.rectangle([bx, ry - 84, bx + bw2, ry], fill=tint_cycle[ti % 4])
            rd.rectangle([bx, ry - 84, bx + bw2, ry], outline=(120, 90, 56), width=4)
            bx += bw2 + 26
            ti += 1
    # the counter: PAYOFF SURFACE band
    rd.rectangle([0, 760, 1150, 1032], fill=(166, 118, 66))
    rd.rectangle([0, 760, 1150, 800], fill=(196, 148, 92))
    for sx2 in range(0, 1150, 256):
        rd.rectangle([sx2, 800, sx2 + 4, 1032], fill=(96, 64, 32))
    rd.text((60, 880), "COUNTER = PAYOFF SURFACE", font=f_s, fill=(70, 48, 26))
    mb.paste(room, (40, 100))

    # right column: title, notes, texture chips, palette
    d.text((1240, 110), "CORNER SHOP AM", font=f_h, fill=(240, 228, 200))
    d.text((1240, 180), "warm daylight · honey oak · pastel tins · dust motes",
           font=f_s, fill=(200, 184, 152))
    d.text((1240, 250), "light: ONE key from upper-left window,", font=f_s,
           fill=(200, 184, 152))
    d.text((1240, 290), "hard falloff to shadowed right edge", font=f_s,
           fill=(200, 184, 152))
    chip_y = 380
    for name, tex in (("wallpaper", tex_wall), ("counter oak", tex_wood)):
        chip = tex.resize((340, 340))
        mb.paste(chip, (1240, chip_y))
        d.text((1240, chip_y + 350), name, font=f_s, fill=(210, 196, 164))
        chip_y += 400
    pal = [(214, 196, 160), (166, 118, 66), (226, 178, 190), (186, 210, 170),
           (240, 208, 150), (90, 70, 50)]
    d.text((1240, chip_y + 10), "palette", font=f_s, fill=(210, 196, 164))
    for i, c in enumerate(pal):
        d.rectangle([1240 + i * 120, chip_y + 60, 1240 + i * 120 + 104, chip_y + 164],
                    fill=c, outline=(20, 16, 12))
    return mb


# ======================================================================
# ROOM B — NIGHT MARKET PM
# ======================================================================
def pm_plaster(rnd):
    """Deep teal night-wall plaster with damp blooms and hairline cracks."""
    base_c, dark_c = (36, 66, 72), (24, 46, 52)
    img = Image.new("RGB", (SIZE, SIZE), base_c)
    bloom = Image.new("L", (SIZE, SIZE), 0)
    bd = ImageDraw.Draw(bloom)
    for _ in range(14):
        x, y = rnd.randint(0, SIZE - 1), rnd.randint(0, SIZE - 1)
        r = rnd.randint(60, 190)
        wrap_ellipse(bd, x, y, r, int(r * rnd.uniform(0.5, 0.9)),
                     rnd.randint(24, 56))
    bloom = wrap_blur(bloom, 24)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), dark_c), img, bloom)
    crack = Image.new("L", (SIZE, SIZE), 0)
    cd = ImageDraw.Draw(crack)
    for _ in range(6):
        x = rnd.randint(40, SIZE - 40)
        pts, y, xx = [], 0, x
        while y <= SIZE:
            pts.append((xx, y))
            y += rnd.randint(50, 96)
            xx += rnd.choice([-16, -8, 0, 8, 16])
        wrap_line(cd, pts, rnd.randint(26, 52), 2)
    crack = wrap_blur(crack, 2)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), (14, 28, 32)), img, crack)
    return grain_overlay(img, 11)


def pm_stallcloth(rnd):
    """Stall cloth: woven stripes + embroidered diamond border, slight sheen.

    Tiles by construction: warp stripes every 128px; weft overcast lines are
    horizontal full-width; diamonds sit on a 128 grid offset half a cell.
    """
    base_a, base_b = (158, 44, 52), (120, 30, 42)
    img = Image.new("RGB", (SIZE, SIZE))
    d = ImageDraw.Draw(img)
    for gx in range(0, SIZE, 128):
        d.rectangle([gx, 0, gx + 64, SIZE], fill=base_a)
        d.rectangle([gx + 64, 0, gx + 128, SIZE], fill=base_b)
    # weft thread highlights (full-width -> tiles horizontally)
    for gy in range(0, SIZE, 8):
        d.line([(0, gy), (SIZE, gy)], fill=(172, 56, 62) if gy % 16 == 0 else (140, 38, 48), width=2)
    # gold stitched diamonds on 128 grid
    dd = ImageDraw.Draw(img)
    for gy in range(0, SIZE + 128, 128):
        off = (gy // 128 % 2) * 64
        for gx in range(-128, SIZE + 128, 128):
            x = gx + off + 64
            dd.polygon([(x, gy - 26), (x + 26, gy), (x, gy + 26), (x - 26, gy)],
                       outline=(212, 168, 92), width=3)
    # sheen: soft diagonal luminance bands, wrapped
    sheen = Image.new("L", (SIZE, SIZE), 0)
    sd = ImageDraw.Draw(sheen)
    for k in range(0, SIZE * 2, 256):
        sd.line([(k, 0), (k - SIZE, SIZE)], fill=40, width=90)
    sheen = wrap_blur(sheen, 30)
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), (196, 74, 74)), img, sheen)
    return grain_overlay(img, 10)


def pm_props_plate(rnd):
    """NIGHT MARKET PM prop plate — RGBA cutout sheet."""
    W, H = 2048, 1024
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f_reg = ImageFont.truetype(FONT_REG, 26)

    def label(txt, xy):
        d.text(xy, txt, font=f_reg, fill=(210, 220, 225, 255))

    # --- hanging paper lanterns (three sizes) ---
    for i, (lx, ly, r) in enumerate(((260, 260, 110), (500, 210, 85), (680, 300, 65))):
        glow = (250, 196, 96)
        d.line([(lx, 0), (lx, ly - r - 26)], fill=(60, 50, 46, 255), width=6)
        d.ellipse([lx - r, ly - r, lx + r, ly + r],
                  fill=glow + (255,), outline=(190, 120, 60, 255), width=8)
        for k in range(-2, 3):
            d.arc([lx - r, ly - r, lx + r, ly + r], start=-70 - k * 8, end=70 - k * 8,
                  fill=(214, 140, 66, 255), width=5)
        d.rectangle([lx - int(r * 0.35), ly - r - 14, lx + int(r * 0.35), ly - r + 6],
                    fill=(70, 58, 50, 255))
        d.rectangle([lx - int(r * 0.35), ly + r - 6, lx + int(r * 0.35), ly + r + 14],
                    fill=(70, 58, 50, 255))
        d.ellipse([lx - int(r * .55), ly - int(r * .55), lx + int(r * .55), ly + int(r * .55)],
                  fill=(255, 232, 168, 255))
    label("paper lanterns (emissive)", (180, 620))

    # --- chalkboard menu sign ---
    mx, my = 900, 380
    d.rounded_rectangle([mx, my, mx + 420, my + 300], radius=18,
                        fill=(38, 46, 44, 255), outline=(126, 90, 56, 255), width=14)
    for li, lt in enumerate(("NOODLES  40", "TEA       15")):
        d.text((mx + 40, my + 60 + li * 80), lt,
               font=ImageFont.truetype(FONT_REG, 44), fill=(226, 230, 224, 255))
    label("chalkboard", (900, 730))

    # --- crate of oranges under string lights ---
    cx, cy = 1450, 520
    d.rectangle([cx, cy, cx + 380, cy + 200], fill=(146, 106, 62, 255))
    d.rectangle([cx, cy, cx + 380, cy + 200], outline=(100, 72, 42, 255), width=10)
    for oy in range(cy - 40, cy + 10, 52):
        for ox in range(cx + 20, cx + 380, 56):
            d.ellipse([ox, oy, ox + 48, oy + 48], fill=(226, 130, 44, 255),
                      outline=(160, 84, 24, 255), width=4)
    for sx in range(cx, cx + 380, 95):
        d.line([(sx, cy - 150), (sx + 40, cy - 40)], fill=(210, 190, 120, 255), width=4)
        d.ellipse([sx + 32, cy - 56, sx + 52, cy - 36], fill=(255, 226, 150, 255))
    label("crate + fairy lights", (1430, 780))
    return img


def _glow_ellipse(canvas_rgba, cx, cy, r, color, alpha):
    """Soft radial glow pasted onto an RGBA canvas — fades to zero INSIDE the
    sprite bounds so the paste never shows a square halo."""
    m = max(8, r // 3)
    size = r * 2 + m * 2
    spr = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spr)
    sd.ellipse([m, m, m + r * 2, m + r * 2], fill=color + (alpha,))
    spr = spr.filter(ImageFilter.GaussianBlur(m))
    canvas_rgba.alpha_composite(spr, (cx - size // 2, cy - size // 2))


def pm_moodboard(tex_wall, tex_cloth, props):
    W, H = 2048, 1400
    mb = Image.new("RGB", (W, H), (10, 14, 18))
    d = ImageDraw.Draw(mb)
    f_h = ImageFont.truetype(FONT_BOLD, 44)
    f_s = ImageFont.truetype(FONT_REG, 26)

    room = Image.new("RGBA", (1150, H - 120), (16, 30, 36, 255))
    rd = ImageDraw.Draw(room)
    rd.rectangle([0, 0, 1150, H - 120], fill=(22, 44, 50))
    # hanging lanterns casting warm pools
    for lx, ly, r in ((260, 220, 100), (560, 170, 80), (840, 260, 68)):
        _glow_ellipse(room, lx, ly, int(r * 1.7), (250, 190, 96), 110)
        rd.ellipse([lx - r, ly - r, lx + r, ly + r], fill=(250, 196, 96),
                   outline=(190, 120, 60))
    # stall cloth counter band = payoff surface
    rd.rectangle([0, 760, 1150, 1032], fill=(158, 44, 52))
    for sx2 in range(0, 1150, 128):
        rd.rectangle([sx2, 760, sx2 + 64, 1032], fill=(120, 30, 42))
        rd.polygon([(sx2 + 96, 860), (sx2 + 122, 886), (sx2 + 96, 912), (sx2 + 70, 886)],
                   outline=(212, 168, 92))
    rd.text((60, 950), "STALL COUNTER = PAYOFF SURFACE", font=f_s, fill=(240, 214, 170))
    # wet floor reflection strip
    rd.rectangle([0, 1032, 1150, H - 120], fill=(12, 24, 30))
    for rx in range(0, 1150, 90):
        rd.rectangle([rx, 1040, rx + 40, 1032 + 90], fill=(120, 70, 40))
    mb.paste(room.convert("RGB"), (40, 100))

    d.text((1240, 110), "NIGHT MARKET PM", font=f_h, fill=(235, 240, 242))
    d.text((1240, 180), "lantern ember on teal · red silk · neon reflections",
           font=f_s, fill=(170, 190, 196))
    d.text((1240, 250), "light: lantern pools from above, cool teal",
           font=f_s, fill=(170, 190, 196))
    d.text((1240, 290), "fill, edges fall to near-black", font=f_s,
           fill=(170, 190, 196))
    chip_y = 380
    for name, tex in (("teal plaster", tex_wall), ("stall cloth", tex_cloth)):
        chip = tex.resize((340, 340))
        mb.paste(chip, (1240, chip_y))
        d.text((1240, chip_y + 350), name, font=f_s, fill=(190, 205, 210))
        chip_y += 400
    pal = [(36, 66, 72), (158, 44, 52), (250, 196, 96), (212, 168, 92), (226, 130, 44)]
    d.text((1240, chip_y + 10), "palette", font=f_s, fill=(190, 205, 210))
    for i, c in enumerate(pal):
        d.rectangle([1240 + i * 120, chip_y + 60, 1240 + i * 120 + 104, chip_y + 164],
                    fill=c, outline=(0, 0, 0))
    return mb


def main():
    rnd_am = random.Random(SEED)
    rnd_pm = random.Random(SEED + 1)

    am_wall = am_wallpaper(random.Random(SEED + 10))
    am_wood = am_counterwood(random.Random(SEED + 11))
    pm_wall = pm_plaster(random.Random(SEED + 20))
    pm_cloth = pm_stallcloth(random.Random(SEED + 21))
    am_props = am_props_plate(random.Random(SEED + 12))
    pm_props = pm_props_plate(random.Random(SEED + 22))

    am_mb = am_moodboard(am_wall, am_wood, am_props)
    pm_mb = pm_moodboard(pm_wall, pm_cloth, pm_props)

    save(am_wall, f"{OUT}/corner_shop_am/tex_wallpaper.png")
    save(am_wood, f"{OUT}/corner_shop_am/tex_counterwood.png")
    save(am_props, f"{OUT}/corner_shop_am/props_plate.png")
    save(am_mb, f"{OUT}/corner_shop_am/mood_board.png")
    save(pm_wall, f"{OUT}/night_market_pm/tex_plaster.png")
    save(pm_cloth, f"{OUT}/night_market_pm/tex_stallcloth.png")
    save(pm_props, f"{OUT}/night_market_pm/props_plate.png")
    save(pm_mb, f"{OUT}/night_market_pm/mood_board.png")


if __name__ == "__main__":
    main()
