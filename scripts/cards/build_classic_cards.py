#!/usr/bin/env python3
"""Rebuilds the 'Classic' card faces in Sources/SpiderSolitaire/Resources/Cards.

Sources (checked on every run, the build aborts if a licence changes):
  * Dmitry Fomin, "English pattern" playing cards (Wikimedia Commons, CC0 1.0): all 52 faces.
  * Byron Knoll, vector-playing-cards ace of spades (Wikimedia Commons, public domain): only the
    ornate centre spade, composited onto Fomin's ace of spades.

Output: one single-page vector PDF per card (paths only, no embedded images), the source's own
360 x 540 pt page (2:3), on a transparent background (the app draws the white card and border).
The app renders each PDF once into a bitmap at the exact pixel size of the card on screen (see
ClassicCardImages.swift), so faces stay sharp at every card size and display scale.
Also writes manifest.json and CREDITS.md (source URL, author, licence and SHA-1 of every file).

Needs: python3 with svgelements (pip install svgelements) and rsvg-convert (librsvg, e.g.
`brew install librsvg`). Every PDF is checked to contain no raster image.
Usage: python3 scripts/cards/build_classic_cards.py [--cache DIR]
"""
import argparse, hashlib, json, os, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request, zlib

API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "SpiderSolitaire-asset-build/1.0 (https://github.com/dansailer; card art licence check)"}
RANKS = ["ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "jack", "queen", "king"]
SUITS = ["spades", "hearts", "diamonds", "clubs"]
SOURCE_W, SOURCE_H = 360, 540  # every Fomin SVG; the PDF page keeps this 2:3 size (in points)
ORNATE_WIDTH = 0.66  # Knoll's spade on the ace of spades, as a fraction of the card width
# Fomin draws every suit pip into a 2:3 box (60 x 90 centre pips, 30 x 45 index pips), so hearts,
# spades and clubs come out ~1.5x taller than usual. Each pip is rescaled about its centre to the
# usual playing-card proportions (width / height): heart ~0.96, spade ~0.86, club ~0.91, diamond ~0.78.
PIP_SCALE = {"hearts": (1.15, 0.80), "spades": (1.10, 0.85), "clubs": (1.12, 0.82), "diamonds": (1.0, 0.86)}
PIP_BOXES = [(60.0, 90.0), (30.0, 45.0)]
SUIT_FILL = {"hearts": "#ff5555", "diamonds": "#ff5555", "spades": "#000000", "clubs": "#000000"}
ORNATE_ACE = "File:Ace of spades.svg"  # Byron Knoll, PD-author
# Author names written to CREDITS.md. The Commons "Artist" field is free text that anyone can edit,
# so it is only checked to still name the author, never copied verbatim.
FOMIN = "Дмитрий Фомин (Dmitry Fomin)"
KNOLL = "Byron Knoll"
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


def author(f):
    expected = KNOLL if f["title"] == ORNATE_ACE else FOMIN
    if expected.split(" (")[0] not in f["artist"] and expected not in f["artist"]:
        sys.exit(f"unexpected author for {f['title']}: {f['artist']!r}")
    return expected


def check_licence(f):
    lic = f["lic_wikitext"]
    template_lines = [l for l in lic.splitlines() if l.strip().startswith("{{")]
    ok = template_lines and all(any(re.fullmatch(a, l.strip(), re.I) for a in ALLOWED) for l in template_lines)
    if not ok or re.search(FORBIDDEN, lic) or f["licence"] not in ("CC0", "Public domain"):
        sys.exit(f"licence not clean for {f['title']}: {f['licence']!r} / {lic!r}")


def download(f, cache):
    path = os.path.join(cache, f["url"].rsplit("/", 1)[1])
    if not os.path.exists(path) or hashlib.sha1(open(path, "rb").read()).hexdigest() != f["sha1"]:
        for attempt in range(6):
            try:
                data = urllib.request.urlopen(urllib.request.Request(f["url"], headers=UA)).read()
                break
            except urllib.error.HTTPError as e:  # Wikimedia rate-limits bursts (429): back off
                if e.code != 429 or attempt == 5:
                    raise
                time.sleep(5 * 2 ** attempt)
        open(path, "wb").write(data)
        time.sleep(1.0)
    if hashlib.sha1(open(path, "rb").read()).hexdigest() != f["sha1"]:
        sys.exit(f"sha1 mismatch for {path}")
    return path


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


def svg_root_size(svg):
    """User-space size of an SVG: its viewBox, else its width and height."""
    root = re.search(rb"<svg\b[^>]*>", svg, re.S).group(0)
    box = re.search(rb'\sviewBox="\s*[-0-9.]+[\s,]+[-0-9.]+[\s,]+([0-9.]+)[\s,]+([0-9.]+)\s*"', root)
    if not box:
        box = re.search(rb'\swidth="([0-9.]+)(?:px)?"[^>]*?\sheight="([0-9.]+)(?:px)?"', root, re.S)
    return float(box.group(1)), float(box.group(2))


def remove_centre_pip(svg):
    """Drops Fomin's plain centre spade (the one reshaped pip drawn in the 60 x 90 box) from the ace
    of spades, so Knoll's ornate spade can take its place. The corner indices stay untouched."""
    from svgelements import Path
    found = []
    for m in re.finditer(rb'<g transform="matrix\([^"]*\)"><path\b[^>]*?/></g>', svg, re.S):
        d = re.search(rb'\sd="([^"]*)"', m.group(0))
        x0, y0, x1, y1 = Path(d.group(1).decode()).bbox()
        if abs((x1 - x0) - 60.0) < 0.6 and abs((y1 - y0) - 90.0) < 0.6:
            found.append(m)
    if len(found) != 1:
        sys.exit(f"ace of spades: expected one 60 x 90 centre pip, found {len(found)}")
    return svg[:found[0].start()] + svg[found[0].end():]


def ornate_spade_element(knoll_svg, card_w, card_h):
    """Byron Knoll's big filigree spade (one black path whose holes are the filigree), as a
    <path> placed in Fomin's 360 x 540 card space: centred, 66 % of the card width, as before."""
    from svgelements import Path
    paths = re.findall(rb"<path\b[^>]*?/>", knoll_svg, re.S)
    best = None
    for el in paths:
        d = re.search(rb'\sd="([^"]*)"', el)
        x0, y0, x1, y1 = Path(d.group(1).decode()).bbox()
        if b"fill:#000000" in el and (best is None or (x1 - x0) * (y1 - y0) > best[1]):
            best = (d.group(1), (x1 - x0) * (y1 - y0), (x0, y0, x1, y1))
    d, _, (x0, y0, x1, y1) = best
    kw, kh = svg_root_size(knoll_svg)
    if not (0.25 * kw < (x0 + x1) / 2 < 0.75 * kw and (x1 - x0) > 0.5 * kw):
        sys.exit("unexpected layout in Knoll's ace of spades: the big centre spade was not found")
    scale = ORNATE_WIDTH * card_w / (x1 - x0)
    tx = card_w / 2 - scale * (x0 + x1) / 2
    ty = card_h / 2 - scale * (y0 + y1) / 2
    return (f'<path transform="matrix({scale:.6f},0,0,{scale:.6f},{tx:.4f},{ty:.4f})" '
            f'style="fill:#000000;stroke:none" d="').encode() + d + b'"/>'


def ornate_ace_svg(fomin_svg, knoll_svg):
    svg, pips = prepared_svg(fomin_svg, "spades")
    svg = remove_centre_pip(svg)
    w, h = svg_root_size(svg)
    spade = ornate_spade_element(open(knoll_svg, "rb").read(), w, h)
    close = svg.rindex(b"</svg>")
    return svg[:close] + spade + b"\n" + svg[close:], pips


def to_pdf(svg, out):
    """librsvg + cairo: paths stay paths. Page size = the SVG's 360 x 540 user units (at 72 dpi)."""
    # SOURCE_DATE_EPOCH pins cairo's CreationDate, so rebuilding unchanged sources gives identical files.
    env = dict(os.environ, SOURCE_DATE_EPOCH="1500000000")
    subprocess.run(["rsvg-convert", "-f", "pdf", "--dpi-x", "72", "--dpi-y", "72", "-o", out],
                   input=svg, check=True, env=env)
    check_vector_pdf(out)


def check_vector_pdf(path):
    """Fails if the PDF holds any raster: an image XObject, an inline image, or a smask image."""
    data = open(path, "rb").read()
    if not data.startswith(b"%PDF-"):
        sys.exit(f"{path}: not a PDF")
    chunks = [data]
    for m in re.finditer(rb"stream\r?\n", data):
        try:
            chunks.append(zlib.decompressobj().decompress(data[m.end():]))
        except zlib.error:
            pass
    for c in chunks:
        if re.search(rb"/Subtype\s*/Image|/ImageMask|\bBI\b[^\n]*\bID\b", c):
            sys.exit(f"{path}: contains a raster image, expected vector paths only")


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
    pip_counts = {}
    for name in os.listdir(OUT_DIR):  # stale outputs (the PNGs of earlier builds)
        if name.endswith((".png", ".pdf")):
            os.remove(os.path.join(OUT_DIR, name))
    for (rank, suit), title in titles.items():
        f = info[title]
        name = asset_name(rank, suit) + ".pdf"
        if (rank, suit) == ("ace", "spades"):
            svg, pips = ornate_ace_svg(f["path"], info[ORNATE_ACE]["path"])
        else:
            svg, pips = prepared_svg(f["path"], suit)
        pip_counts[asset_name(rank, suit)] = pips
        out = os.path.join(OUT_DIR, name)
        to_pdf(svg, out)
        sources = [f] + ([info[ORNATE_ACE]] if (rank, suit) == ("ace", "spades") else [])
        rows.append((name, sources))
        print(name, os.path.getsize(out))

    manifest = {
        "comment": "Written by scripts/cards/build_classic_cards.py; checked by ClassicCardArtTests.",
        "sourceWidth": SOURCE_W, "sourceHeight": SOURCE_H, "format": "pdf",
        "ornateSpadeWidth": ORNATE_WIDTH,
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
                  "(see `PIP_SCALE` in the script and `manifest.json`); on the ace of spades the plain centre\n"
                  "pip is replaced by Byron Knoll's ornate spade path, centred at 66 % of the card width; each\n"
                  "card is then converted with librsvg to a vector PDF (paths only, no raster images) at the\n"
                  f"source's own 2:3 page size, {SOURCE_W} x {SOURCE_H} pt. The app rasterises each PDF at the\n"
                  "exact pixel size of the card on screen.\n\n"
                  "* **Dmitry Fomin, \"English pattern\" playing cards** (2017), CC0 1.0 Universal Public\n"
                  "  Domain Dedication (`{{self|cc-zero}}`): <https://creativecommons.org/publicdomain/zero/1.0/>.\n"
                  "  Category: <https://commons.wikimedia.org/wiki/Category:SVG_English_pattern_playing_cards>\n"
                  "* **Byron Knoll, vector-playing-cards ace of spades**, released into the public domain by\n"
                  "  its author (`{{PD-author|Byron Knoll}}`). Only its ornate centre spade is used, on\n"
                  "  `spades_ace.pdf`.\n\n"
                  "Neither licence requires attribution; it is listed here so the provenance is clear.\n"
                  "Rejected: the Cburnett set (CC BY-SA 3.0) and \"English pattern playing cards deck PLUS\" (LGPL 2.1).\n\n"
                  "| Image | Source file page | Author | Licence | SHA-1 of source SVG |\n"
                  "|---|---|---|---|---|\n")
        for name, sources in sorted(rows):
            for s in sources:
                lic = "CC0 1.0" if s["licence"] == "CC0" else "Public domain"
                out.write(f"| `{name}` | [{s['title'][5:]}]({s['page']}) | {author(s)} | {lic} | `{s['sha1']}` |\n")
    print("wrote", len(rows), "PDFs to", OUT_DIR)


if __name__ == "__main__":
    main()
