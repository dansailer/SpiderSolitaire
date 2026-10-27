#!/usr/bin/env python3
"""Preview of the help window (Linux): renders `SpiderTools help` Markdown as two window mockups
(Rules and Keyboard Shortcuts) laid out like HelpView. Usage: preview_help.py <help.md> <out.png>"""
import sys
from PIL import Image, ImageDraw, ImageFont

md, out = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
S = 2
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf"
def font(size, bold=False): return ImageFont.truetype(FONT % ("-Bold" if bold else ""), size * S)

sections = {}
for chunk in md.split("\n# ")[0:]:
    chunk = chunk.lstrip("# ")
    title, _, body = chunk.partition("\n")
    sections[title.strip()] = body
SIDEBAR = ["Rules", "Scoring", "Tips", "Achievements", "Keyboard Shortcuts"]
ICONS = {"Rules": "▤", "Scoring": "#", "Tips": "✦", "Achievements": "✪", "Keyboard Shortcuts": "⌘"}

MEASURE = ImageDraw.Draw(Image.new("RGB", (1, 1)))
def wrap(text, width_pt, size=12):
    """Greedy word wrap by rendered width, like Text in the real window."""
    out, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if line and MEASURE.textlength(trial, font=font(size)) > width_pt * S:
            out.append(line); line = word
        else:
            line = trial
    return out + ([line] if line else [])

def window(selected, W=560):
    body = sections[selected]
    H = 4000
    img = Image.new("RGB", (W * S, H * S), (255, 255, 255))
    d = ImageDraw.Draw(img)
    side = 170
    d.rectangle([0, 0, side * S, H * S], fill=(236, 236, 238))
    y = 44
    for name in SIDEBAR:
        if name == selected:
            d.rounded_rectangle([8 * S, (y - 4) * S, (side - 8) * S, (y + 20) * S], radius=6 * S, fill=(10, 100, 220))
        col = (255, 255, 255) if name == selected else (30, 30, 30)
        d.text((18 * S, y * S), ICONS[name], font=font(12), fill=(255, 255, 255) if name == selected else (10, 100, 220))
        d.text((38 * S, y * S), name, font=font(12), fill=col)
        y += 28
    x0, x1 = side + 22, W - 22
    y = 44
    d.text((x0 * S, y * S), selected, font=font(20, True), fill=(20, 20, 20)); y += 36
    lines = body.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("## "):
            y += 6; d.text((x0 * S, y * S), line[3:], font=font(13, True), fill=(20, 20, 20)); y += 22
        elif line.startswith("- "):
            for j, w in enumerate(wrap(line[2:], x1 - x0 - 12)):
                if j == 0: d.text((x0 * S, y * S), "•", font=font(12), fill=(40, 40, 40))
                d.text(((x0 + 12) * S, y * S), w, font=font(12), fill=(40, 40, 40)); y += 17
            y += 3
        elif line.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip("|").split("|")]
                if not set(lines[i]) <= set("|-"): rows.append(cells)
                i += 1
            i -= 1
            top = y; y += 10
            colw = 120 if selected != "Scoring" else 150
            for r, cells in enumerate(rows):
                wrapped = wrap(cells[1], x1 - x0 - colw - 24) or [""]
                f = font(10, True) if r == 0 else font(12, r > 0)
                col = (120, 120, 120) if r == 0 else (30, 30, 30)
                d.text(((x0 + 12) * S, y * S), cells[0], font=font(10, True) if r == 0 else font(12, True), fill=col)
                for k, w in enumerate(wrapped):
                    d.text(((x0 + 12 + colw) * S, (y + 17 * k) * S), w, font=font(10, True) if r == 0 else font(12), fill=col)
                y += 17 * len(wrapped) + 6
                if r == 0:
                    d.line([(x0 + 12) * S, (y - 3) * S, (x1 - 12) * S, (y - 3) * S], fill=(215, 215, 215), width=S)
            d.rounded_rectangle([x0 * S, top * S, x1 * S, (y + 4) * S], radius=8 * S, outline=(225, 225, 225), width=S)
            y += 14
        elif line.strip():
            for w in wrap(line, x1 - x0):
                d.text((x0 * S, y * S), w, font=font(12), fill=(40, 40, 40)); y += 17
            y += 6
        i += 1
    H = y + 20
    img = img.crop((0, 0, W * S, H * S))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W * S, 28 * S], fill=(232, 232, 234))
    for k, c in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = (16 + k * 20) * S
        d.ellipse([cx - 6 * S, 8 * S, cx + 6 * S, 20 * S], fill=c)
    d.text((W * S // 2, 14 * S), "Spider Solitaire Help", font=font(12, True), fill=(70, 70, 70), anchor="mm")
    d.rectangle([0, 0, W * S - 1, H * S - 1], outline=(190, 190, 190), width=S)
    return img

a, b = window("Rules"), window("Keyboard Shortcuts")
sheet = Image.new("RGB", (a.width + b.width + 60 * S, max(a.height, b.height) + 40 * S), (210, 214, 220))
sheet.paste(a, (20 * S, 20 * S)); sheet.paste(b, (a.width + 40 * S, 20 * S))
sheet.save(out, optimize=True)
print(out)
