#!/usr/bin/env python3
"""Rebuilds the 'Classic' card faces in Sources/SpiderSolitaire/Resources/Cards.

Sources (checked on every run, the build aborts if a licence changes):
  * Dmitry Fomin, "English pattern" playing cards (Wikimedia Commons, CC0 1.0): all 52 faces.
  * Byron Knoll, vector-playing-cards ace of spades (Wikimedia Commons, public domain): only the
    ornate centre spade, composited onto Fomin's ace of spades.

Output: 240 x 324 px PNGs (2x the largest on-screen card, 120 x 162 pt), the art fitted to the
card height and centred on a transparent background (the app draws the white card and border),
plus CREDITS.md with the source URL, author, licence and SHA-1 of every file.

Needs: python3 with Pillow, rsvg-convert (librsvg), pngquant and optipng (optional).
Usage: python3 scripts/cards/build_classic_cards.py [--cache DIR]
"""
import argparse, hashlib, io, json, os, re, shutil, subprocess, sys, time, urllib.parse, urllib.request
from PIL import Image

API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "SpiderSolitaire-asset-build/1.0 (https://github.com/dansailer; card art licence check)"}
RANKS = ["ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "jack", "queen", "king"]
SUITS = ["spades", "hearts", "diamonds", "clubs"]
OUT_W, OUT_H = 240, 360  # the source's own 2:3 aspect (360 x 540 SVG); CardView fits it into 71:96
SOURCE_W, SOURCE_H = 360, 540
# Fomin draws every suit pip into a 2:3 box (60 x 90 centre pips, 30 x 45 index pips), so hearts,
# spades and clubs come out ~1.5x taller than usual. Each pip is rescaled about its centre to the
# usual playing-card proportions (width / height): heart ~0.96, spade ~0.86, club ~0.91, diamond ~0.78.
PIP_SCALE = {"hearts": (1.15, 0.80), "spades": (1.10, 0.85), "clubs": (1.12, 0.82), "diamonds": (1.0, 0.86)}
PIP_BOXES = [(60.0, 90.0), (30.0, 45.0)]
SUIT_FILL = {"hearts": "#ff5555", "diamonds": "#ff5555", "spades": "#000000", "clubs": "#000000"}
ORNATE_ACE = "File:Ace of spades.svg"  # Byron Knoll, PD-author
ALLOWED = [r"\{\{\s*self\s*\|\s*cc-zero\s*\}\}", r"\{\{\s*cc-zero\s*\}\}", r"\{\{\s*PD-author\s*\|[^}]*\}\}"]
FORBIDDEN = r"(?i)gpl|by-sa|cc-by|attribution|nc-|non-?commercial|fair use"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_DIR = os.path.join(ROOT, "Sources", "SpiderSolitaire", "Resources", "Cards")


def asset_name(rank, suit):
    # Must match ClassicCardArt.assetName(rank:suit:) in Sources/SpiderBoard/ClassicCardArt.swift.
    return f"{suit}_{rank}"


def api(params):
    params = dict(params, format="json", formatversion="2")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers=UA)
    return json.load(urllib.request.urlopen(req))


def file_info(titles):
    info = {}
    for i in range(0, len(titles), 25):
        d = api({"action": "query", "titles": "|".join(titles[i:i + 25]),
                 "prop": "imageinfo|revisions", "rvprop": "content", "rvslots": "main",
                 "iiprop": "url|sha1|user|size|extmetadata"})
        for p in d["query"]["pages"]:
            if "imageinfo" not in p:
                sys.exit(f"missing on Commons: {p['title']}")
            ii = p["imageinfo"][0]
            text = p["revisions"][0]["slots"]["main"]["content"]
            sec = re.search(r"==\s*\{\{int:license-header\}\}\s*==(.*?)(?:\n==|\Z)", text, re.S)
            lic_wikitext = sec.group(1) if sec else ""
            meta = ii["extmetadata"]
            info[p["title"]] = {
                "title": p["title"], "url": ii["url"].split("?")[0], "page": ii["descriptionurl"],
                "sha1": ii["sha1"], "uploader": ii["user"],
                "licence": meta.get("LicenseShortName", {}).get("value", ""),
                "artist": re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip(),
                "lic_wikitext": lic_wikitext.strip(),
            }
        time.sleep(0.3)
    return info


def check_licence(f):
    lic = f["lic_wikitext"]
    template_lines = [l for l in lic.splitlines() if l.strip().startswith("{{")]
    ok = template_lines and all(any(re.fullmatch(a, l.strip(), re.I) for a in ALLOWED) for l in template_lines)
    if not ok or re.search(FORBIDDEN, lic) or f["licence"] not in ("CC0", "Public domain"):
        sys.exit(f"licence not clean for {f['title']}: {f['licence']!r} / {lic!r}")


def download(f, cache):
    path = os.path.join(cache, f["url"].rsplit("/", 1)[1])
    if not os.path.exists(path) or hashlib.sha1(open(path, "rb").read()).hexdigest() != f["sha1"]:
        data = urllib.request.urlopen(urllib.request.Request(f["url"], headers=UA)).read()
        open(path, "wb").write(data)
        time.sleep(0.2)
    if hashlib.sha1(open(path, "rb").read()).hexdigest() != f["sha1"]:
        sys.exit(f"sha1 mismatch for {path}")
    return path


def render(svg_bytes, height):
    png = subprocess.run(["rsvg-convert", "-h", str(height), "-f", "png"], input=svg_bytes,
                         capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def strip_outline(svg):
    """Fomin's cards start with a white, black-stroked rounded rect (one file uses a path): the card
    itself. Make it invisible so the app's own card shape and border show through."""
    m = re.search(rb"<(?:rect|path)\b[^>]*?>", svg, re.S)
    style = re.search(rb'style="([^"]*)"', m.group(0)) if m else None
    if not style or b"fill:#ffffff" not in style.group(1) or b"stroke:#000000" not in style.group(1):
        sys.exit("unexpected SVG layout: first shape is not the white card outline")
    element = m.group(0).replace(style.group(0), b'style="fill:none;stroke:none"')
    return svg[:m.start()] + element + svg[m.end():]


def reshape_pips(svg, suit):
    """Wraps every suit pip (a transform-free <path> filled with the suit colour whose bounding box
    is one of Fomin's 2:3 pip boxes) in a group that rescales it about its centre. Returns the new
    SVG and how many pips were changed."""
    from svgelements import Path  # pip install svgelements
    sx, sy = PIP_SCALE[suit]
    fill = SUIT_FILL[suit].encode()
    count = 0
    def wrap(m):
        nonlocal count
        el = m.group(0)
        if b"transform=" in el or (b"fill:" + fill) not in el.lower():
            return el
        d = re.search(rb'\sd="([^"]*)"', el)
        x0, y0, x1, y1 = Path(d.group(1).decode()).bbox()
        w, h = x1 - x0, y1 - y0
        if not any(abs(w - bw) < 0.6 and abs(h - bh) < 0.6 for bw, bh in PIP_BOXES):
            return el
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        count += 1
        m_ = f'matrix({sx},0,0,{sy},{cx - sx * cx:.4f},{cy - sy * cy:.4f})'.encode()
        return b'<g transform="' + m_ + b'">' + el + b"</g>"
    out = re.sub(rb"<path\b[^>]*?/>", wrap, svg, flags=re.S)
    return out, count


def prepared_svg(path, suit):
    svg, pips = reshape_pips(strip_outline(open(path, "rb").read()), suit)
    if pips < 3:
        sys.exit(f"{path}: found only {pips} suit pips to reshape")
    return svg, pips


def fit(art):
    """Uniform downscale to the output size (the art is already 2:3, so nothing is distorted)."""
    if abs(art.width / art.height - OUT_W / OUT_H) > 0.002:
        sys.exit(f"art is {art.width} x {art.height}, not 2:3")
    return art.resize((OUT_W, OUT_H), Image.LANCZOS)
    return canvas


def largest_dark_component(img):
    """Bounding box of the dark blobs around the centre (the big spade is several blobs split by its
    white filigree); blobs centred near the left/right edge are corner pips and are ignored."""
    small = img.convert("L").resize((img.width // 4, img.height // 4))
    w, h = small.size
    px = small.load()
    seen = [[False] * w for _ in range(h)]
    boxes = []
    for sy in range(h):
        for sx in range(w):
            if seen[sy][sx] or px[sx, sy] >= 128:
                continue
            stack, count, box = [(sx, sy)], 0, [sx, sy, sx, sy]
            seen[sy][sx] = True
            while stack:
                x, y = stack.pop()
                count += 1
                box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and px[nx, ny] < 128:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            centre_x = (box[0] + box[2]) / 2
            if count >= 4 and 0.25 * w <= centre_x <= 0.75 * w:
                boxes.append(box)
    x0, y0 = min(b[0] for b in boxes), min(b[1] for b in boxes)
    x1, y1 = max(b[2] for b in boxes), max(b[3] for b in boxes)
    return (max(0, x0 * 4 - 4), max(0, y0 * 4 - 4), min(img.width, x1 * 4 + 8), min(img.height, y1 * 4 + 8))


def ornate_spade(svg_path):
    """Crops the big filigree spade out of Byron Knoll's ace of spades (white inside, black outside)."""
    img = render(open(svg_path, "rb").read(), 1600)
    w, h = img.size
    box = (int(w * 0.17), int(h * 0.17), int(w * 0.83), int(h * 0.83))
    region = img.crop(box)
    bbox = largest_dark_component(region)
    spade = region.crop(bbox)
    # Keep the filigree's white but make the surrounding card white transparent: flood-fill
    # from the crop's edges through near-white pixels.
    px = spade.load()
    sw, sh = spade.size
    seen = set()
    stack = [(x, y) for x in range(sw) for y in (0, sh - 1)] + [(x, y) for y in range(sh) for x in (0, sw - 1)]
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < sw and 0 <= y < sh):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if min(r, g, b) < 200:
            continue
        px[x, y] = (255, 255, 255, 0)
        stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return spade


def ornate_ace(fomin_svg, knoll_svg):
    big = 1620
    art = render(prepared_svg(fomin_svg, "spades")[0], big)
    w, h = art.size
    # Clear Fomin's plain centre pip (corner indices stay untouched).
    clear = Image.new("RGBA", (int(w * 0.5), int(h * 0.4)), (0, 0, 0, 0))
    art.paste(clear, (int(w * 0.25), int(h * 0.3)))
    spade = ornate_spade(knoll_svg)
    target_w = int(w * 0.66)
    spade = spade.resize((target_w, round(spade.height * target_w / spade.width)), Image.LANCZOS)
    art.alpha_composite(spade, ((w - spade.width) // 2, (h - spade.height) // 2))
    return art


def optimise(path):
    if shutil.which("pngquant"):
        subprocess.run(["pngquant", "--force", "--skip-if-larger", "--quality", "80-98", "--speed", "1",
                        "--output", path, path], check=False)
    if shutil.which("optipng"):
        subprocess.run(["optipng", "-quiet", "-o5", "-strip", "all", path], check=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.join(ROOT, ".build", "card-sources"))
    args = ap.parse_args()
    os.makedirs(args.cache, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)

    titles = {(r, s): f"File:English pattern {r} of {s}.svg" for s in SUITS for r in RANKS}
    info = file_info(list(titles.values()) + [ORNATE_ACE])
    for f in info.values():
        check_licence(f)
        f["path"] = download(f, args.cache)

    rows = []
    pip_counts = {"spades_ace": prepared_svg(info[titles[("ace", "spades")]]["path"], "spades")[1]}
    for (rank, suit), title in titles.items():
        f = info[title]
        name = asset_name(rank, suit) + ".png"
        if (rank, suit) == ("ace", "spades"):
            art = ornate_ace(f["path"], info[ORNATE_ACE]["path"])
        else:
            art = render(prepared_svg(f["path"], suit)[0], OUT_H * 5)
        pip_counts[asset_name(rank, suit)] = prepared_svg(f["path"], suit)[1]
        out = os.path.join(OUT_DIR, name)
        fit(art).save(out)
        optimise(out)
        sources = [f] + ([info[ORNATE_ACE]] if (rank, suit) == ("ace", "spades") else [])
        rows.append((name, sources))
        print(name, os.path.getsize(out))

    manifest = {
        "comment": "Written by scripts/cards/build_classic_cards.py; checked by ClassicCardArtTests.",
        "sourceWidth": SOURCE_W, "sourceHeight": SOURCE_H, "imageWidth": OUT_W, "imageHeight": OUT_H,
        "pipScale": {k: {"x": v[0], "y": v[1]} for k, v in PIP_SCALE.items()},
        "reshapedPips": dict(sorted(pip_counts.items())),
    }
    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as out:
        json.dump(manifest, out, indent=2)
        out.write("\n")

    with open(os.path.join(OUT_DIR, "CREDITS.md"), "w") as out:
        out.write("# Classic card faces: sources and licences\n\n")
        out.write("Every image in this folder is generated by `scripts/cards/build_classic_cards.py` from the\n"
                  "Wikimedia Commons files below. The script reads each file page's licence section and\n"
                  "refuses to build if it is not CC0 or public domain. Changes made: the SVG card outline is\n"
                  "made transparent (the app draws its own card and border); every suit pip, which the\n"
                  "source draws into a tall 2:3 box, is rescaled about its centre to the usual proportions\n"
                  "(see `PIP_SCALE` in the script and `manifest.json`); the art is rendered with librsvg at\n"
                  f"its own 2:3 aspect, {OUT_W} x {OUT_H} px, and colours are quantised with pngquant.\n\n"
                  "* **Dmitry Fomin, \"English pattern\" playing cards** (2017), CC0 1.0 Universal Public\n"
                  "  Domain Dedication (`{{self|cc-zero}}`): <https://creativecommons.org/publicdomain/zero/1.0/>.\n"
                  "  Category: <https://commons.wikimedia.org/wiki/Category:SVG_English_pattern_playing_cards>\n"
                  "* **Byron Knoll, vector-playing-cards ace of spades**, released into the public domain by\n"
                  "  its author (`{{PD-author|Byron Knoll}}`). Only its ornate centre spade is used, on\n"
                  "  `spades_ace.png`.\n\n"
                  "Neither licence requires attribution; it is listed here so the provenance is clear.\n"
                  "Rejected: the Cburnett set (CC BY-SA 3.0) and \"English pattern playing cards deck PLUS\" (LGPL 2.1).\n\n"
                  "| Image | Source file page | Author | Licence | SHA-1 of source SVG |\n"
                  "|---|---|---|---|---|\n")
        for name, sources in sorted(rows):
            for s in sources:
                lic = "CC0 1.0" if s["licence"] == "CC0" else "Public domain"
                out.write(f"| `{name}` | [{s['title'][5:]}]({s['page']}) | {s['artist']} | {lic} | `{s['sha1']}` |\n")
    print("wrote", len(rows), "images to", OUT_DIR)


if __name__ == "__main__":
    main()
