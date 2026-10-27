#!/usr/bin/env python3
"""Preview of the Achievements window (Linux): badges from `SpiderIcon --badges`, laid out like
AchievementsView, plus the unlock banner. Usage: preview_achievements.py <badge-svg-dir> <out.png>"""
import subprocess, sys, textwrap, io
from PIL import Image, ImageDraw, ImageFont

badges, out = sys.argv[1], sys.argv[2]
S = 2  # retina scale
ACH = [  # id, title, hint (mirrors Achievement.all)
    ("firstWin", "First Win", "Win a game."),
    ("twoSuitWin", "Two Suits", "Win a game with two suits."),
    ("fourSuitWin", "Four Suits", "Win a game with four suits."),
    ("purist", "Purist", "Win a game without using Undo."),
    ("noPeeking", "No Peeking", "Win a game without asking for a hint."),
    ("grandmaster", "Grandmaster", "Win with four suits without using Undo."),
    ("speedster", "Speedster", "Win within 5 minutes (one suit), 12 (two suits) or 25 (four suits)."),
    ("efficient", "Efficient", "Win in at most 150 moves (one suit), 200 (two suits) or 300 (four suits)."),
    ("cleanSweep", "Clean Sweep", "Complete a suit before the first deal."),
    ("emptyHanded", "Empty Handed", "Empty a column before the first deal."),
    ("hatTrick", "Hat Trick", "Win 3 games in a row at one difficulty."),
    ("onARoll", "On a Roll", "Win 10 games in a row at one difficulty."),
    ("seasoned", "Seasoned", "Win 25 games."),
    ("century", "Century", "Play 100 games."),
]
UNLOCKED = {"firstWin": "12 Oct 2026", "twoSuitWin": "19 Oct 2026", "purist": "14 Oct 2026",
            "cleanSweep": "21 Oct 2026", "emptyHanded": "12 Oct 2026", "hatTrick": "25 Oct 2026"}

def font(bold, size):
    return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""), size * S)

def badge(name, unlocked, px):
    svg = "%s/%s-%s.svg" % (badges, name, "unlocked" if unlocked else "locked")
    png = subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg], check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")

cols, tile_w, tile_h, pad = 5, 150, 200, 20
W = pad * 2 + cols * tile_w + (cols - 1) * 14
rows = (len(ACH) + cols - 1) // cols
H = 28 + 40 + rows * tile_h + pad
img = Image.new("RGBA", (W * S, H * S), (236, 236, 236, 255))
d = ImageDraw.Draw(img)
# Title bar
d.rectangle([0, 0, W * S, 28 * S], fill=(222, 222, 222))
for i, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
    x = (14 + i * 20) * S
    d.ellipse([x - 6 * S, 8 * S, x + 6 * S, 20 * S], fill=c)
d.text((W * S // 2, 14 * S), "Achievements", font=font(True, 13), fill=(60, 60, 60), anchor="mm")
d.text((pad * S, 42 * S), "%d of %d unlocked" % (len(UNLOCKED), len(ACH)), font=font(True, 14), fill=(20, 20, 20), anchor="lm")
for i, (aid, title, hint) in enumerate(ACH):
    unlocked = aid in UNLOCKED
    x0 = pad + (i % cols) * (tile_w + 14)
    y0 = 62 + (i // cols) * tile_h
    cx = (x0 + tile_w // 2) * S
    b = badge(aid, unlocked, 84 * S)
    img.alpha_composite(b, (cx - b.width // 2, (y0 + 4) * S))
    y = (y0 + 96) * S
    d.text((cx, y), title, font=font(True, 13), fill=(20, 20, 20) if unlocked else (130, 130, 130), anchor="ma")
    y += 20 * S
    for line in textwrap.wrap(hint, 26):
        d.text((cx, y), line, font=font(False, 10), fill=(120, 120, 120), anchor="ma")
        y += 14 * S
    if unlocked:
        d.text((cx, y + 2 * S), "Unlocked " + UNLOCKED[aid], font=font(True, 10), fill=(140, 97, 13), anchor="ma")

# The banner, as it appears over the felt.
bw, bh = 400, 110
banner = Image.new("RGBA", (bw * S, bh * S), (0, 127, 14, 255))
bd = ImageDraw.Draw(banner)
r = [20 * S, 20 * S, (bw - 20) * S, 84 * S]
bd.rounded_rectangle([r[0] + 2 * S, r[1] + 4 * S, r[2] + 2 * S, r[3] + 4 * S], radius=10 * S, fill=(0, 70, 8))
bd.rounded_rectangle(r, radius=10 * S, fill=(255, 250, 235), outline=(204, 153, 46), width=int(1.5 * S))
bb = badge("hatTrick", True, 40 * S)
banner.alpha_composite(bb, (30 * S, 32 * S))
bd.text((80 * S, 28 * S), "Achievement unlocked", font=font(False, 10), fill=(115, 77, 13))
bd.text((80 * S, 42 * S), "Hat Trick", font=font(True, 14), fill=(0, 0, 0))
bd.text((80 * S, 62 * S), "Win 3 games in a row at one difficulty.", font=font(False, 10), fill=(77, 77, 77))

sheet = Image.new("RGBA", (W * S, (H + bh + 10) * S), (255, 255, 255, 255))
sheet.alpha_composite(img, (0, 0))
sheet.alpha_composite(banner, ((W - bw) * S // 2, (H + 5) * S))
sheet.convert("RGB").save(out, optimize=True)
print(out)
