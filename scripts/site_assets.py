#!/usr/bin/env python3
"""Builds docs/assets and docs/fonts for the website (run on the box or any machine with Pillow,
rsvg-convert and pngquant). Everything the page loads is a file in docs/: no CDN.

    python3 scripts/site_assets.py <snapshots-dir> <icon.svg> <card-back.svg> <fonts-dir> <phosphor-dir>

<snapshots-dir>   PNGs from `SpiderSolitaire --snapshot <dir>` on a Mac (real app windows)
<icon.svg>        `SpiderIcon icon.svg`;  <card-back.svg>: `SpiderIcon --card-back back.svg`
<fonts-dir>       unpacked npm packages @fontsource/cormorant-garamond and @fontsource-variable/manrope
<phosphor-dir>    unpacked npm package @phosphor-icons/core (MIT)
"""
import os, re, shutil, subprocess, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DOCS = os.path.join(ROOT, "docs")
ASSETS = os.path.join(DOCS, "assets")
CARDS = os.path.join(ROOT, "Sources", "SpiderSolitaire", "Resources", "Cards")
snap, icon_svg, back_svg, fonts, phosphor = sys.argv[1:6]
os.makedirs(ASSETS, exist_ok=True)

def webp(src, dst, width=None, crop=None, quality=86):
    rgba = Image.open(src).convert("RGBA")
    im = Image.new("RGB", rgba.size, (255, 255, 255))
    im.paste(rgba, mask=rgba.split()[3])  # vibrancy areas come out transparent
    if crop: im = im.crop(crop)
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(os.path.join(ASSETS, dst), "WEBP", quality=quality, method=6)
    return im.size

sizes = {}
sizes["board"] = webp(os.path.join(snap, "board.png"), "board.webp", 1600)
sizes["appearance"] = webp(os.path.join(snap, "settings-appearance.png"), "settings-appearance.webp", 1040, crop=(0, 0, 1040, 830))
# The help sidebar is vibrancy, which cacheDisplay can't draw: keep the text column only.
sizes["help"] = webp(os.path.join(snap, "help.png"), "help.webp", 800, crop=(356, 0, 1120, 1344))
sizes["achievements"] = webp(os.path.join(snap, "achievements.png"), "achievements.webp", 1440)
sizes["general"] = webp(os.path.join(snap, "settings-general.png"), "settings-general.webp", 1040)

# Social card 1200 x 630: the board on the felt colour.
og = Image.new("RGB", (1200, 630), (19, 18, 9))
b = Image.open(os.path.join(snap, "board.png")).convert("RGB").resize((1040, 780), Image.LANCZOS)
og.paste(b.crop((0, 0, 1040, 550)), (80, 40))
og.save(os.path.join(ASSETS, "og-image.png"), optimize=True)

def svg_png(svg, dst, w, h=None):
    args = ["rsvg-convert", "-w", str(w)] + (["-h", str(h)] if h else []) + [svg, "-o", os.path.join(ASSETS, dst)]
    subprocess.run(args, check=True)
    subprocess.run(["pngquant", "--force", "--skip-if-larger", "--ext", ".png", "--quality", "70-95",
                    os.path.join(ASSETS, dst)], check=False)

svg_png(icon_svg, "icon-512.png", 512, 512)
svg_png(icon_svg, "icon-180.png", 180, 180)
svg_png(icon_svg, "favicon-32.png", 32, 32)
svg_png(back_svg, "card-back.png", 240)
shutil.copy(icon_svg, os.path.join(ASSETS, "favicon.svg"))

for name in ["spades_king", "hearts_queen", "spades_jack", "spades_ace", "hearts_king", "hearts_ace"]:
    shutil.copy(os.path.join(CARDS, name + ".png"), os.path.join(ASSETS, name.replace("_", "-") + ".png"))

# Fonts (SIL OFL 1.1), Latin subsets as published by Fontsource, each with its licence.
for folder, files, lic in [
    ("cormorant-garamond", ["cormorant-garamond-latin-500-normal.woff2", "cormorant-garamond-latin-600-normal.woff2"],
     "cormorant-garamond/package/LICENSE"),
    ("manrope", ["manrope-latin-wght-normal.woff2"], "manrope/package/LICENSE"),
]:
    dst = os.path.join(DOCS, "fonts", folder)
    os.makedirs(dst, exist_ok=True)
    src = os.path.join(fonts, lic.split("/")[0], "package", "files")
    for f in files: shutil.copy(os.path.join(src, f), os.path.join(dst, f))
    shutil.copy(os.path.join(fonts, lic), os.path.join(dst, "OFL.txt"))

# Phosphor icons (MIT) as one sprite of <symbol>s.
ICONS = ["download-simple", "github-logo", "apple-logo", "cards", "check-circle", "arrow-counter-clockwise",
         "trophy", "palette", "sparkle", "shield-check", "wifi-slash", "list", "x", "seal-check", "keyboard",
         "lightbulb", "heart", "arrow-up-right", "lock-key", "arrow-left"]
symbols = []
for name in ICONS:
    svg = open(os.path.join(phosphor, "package", "assets", "regular", name + ".svg")).read()
    inner = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S).group(1)
    symbols.append(f'<symbol id="i-{name}" viewBox="0 0 256 256">{inner}</symbol>')
with open(os.path.join(ASSETS, "icons.svg"), "w") as f:
    f.write('<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor">'
            '<!-- Phosphor Icons, MIT, (c) 2023 Phosphor Icons -->' + "".join(symbols) + "</svg>\n")
shutil.copy(os.path.join(phosphor, "package", "LICENSE"), os.path.join(ASSETS, "PHOSPHOR-LICENSE.txt"))
for k, v in sizes.items(): print(k, v)
