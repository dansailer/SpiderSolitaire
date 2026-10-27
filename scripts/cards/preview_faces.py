#!/usr/bin/env python3
"""Preview of both face sets at the in-app card aspect (71:96), 2x of a 120 pt card.

Row 1, Classic: the shipped PNGs placed exactly as CardView does (aspect fit, centred).
Row 2, Simple: an approximation of the code-drawn SwiftUI faces with the same metrics
(DejaVu instead of SF, simplified court panel); suit glyphs are font glyphs, uniformly scaled.
Usage: python3 scripts/cards/preview_faces.py out.png
"""
import os, sys
from PIL import Image, ImageDraw, ImageFont
HERE = os.path.dirname(os.path.abspath(__file__))
CARDS = os.path.join(HERE, "..", "..", "Sources", "SpiderSolitaire", "Resources", "Cards")
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SERIF_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
W = 240
H = round(W * 96 / 71)
R = round(W * 0.07)
GAP = 20
CARDS_SHOWN = [("king", "spades"), ("queen", "spades"), ("jack", "spades"), ("ace", "spades"),
               ("king", "hearts"), ("queen", "hearts"), ("jack", "hearts"), ("ace", "hearts"),
               ("7", "clubs"), ("10", "diamonds")]
SYMBOL = {"spades": "♠", "hearts": "♥", "diamonds": "♦", "clubs": "♣"}
LABEL = {"ace": "A", "jack": "J", "queen": "Q", "king": "K"}
RED, BLACK = (217, 0, 0), (13, 13, 13)
PIP_AREA = (0.27, 0.73, 0.17, 0.83)


def pips(rank):
    l, m, r = 0.0, 0.5, 1.0
    corners = [(l, 0), (r, 0), (l, 1), (r, 1)]
    six = corners + [(l, .5), (r, .5)]
    grid = [(x, y) for y in (0, 1 / 3, 2 / 3, 1) for x in (l, r)]
    return {"2": [(m, 0), (m, 1)], "3": [(m, 0), (m, .5), (m, 1)], "4": corners, "5": corners + [(m, .5)],
            "6": six, "7": six + [(m, .25)], "8": six + [(m, .25), (m, .75)], "9": grid + [(m, .5)],
            "10": grid + [(m, 1 / 6), (m, 5 / 6)]}[rank]


def glyph(text, size, colour, font=FONT, rotate=False):
    f = ImageFont.truetype(font, round(size))
    box = f.getbbox(text, anchor="mm")
    im = Image.new("RGBA", (box[2] - box[0] + 4, box[3] - box[1] + 4), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((im.width / 2, im.height / 2), text, font=f, fill=colour, anchor="mm")
    return im.rotate(180) if rotate else im


def put(card, im, cx, cy):
    card.alpha_composite(im, (round(cx - im.width / 2), round(cy - im.height / 2)))


def card_base():
    card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle((0, 0, W - 1, H - 1), R, fill=(255, 255, 255, 255))
    return card


def finish(card):
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, H - 1), R, fill=255)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(card, (0, 0), mask)
    ImageDraw.Draw(out).rounded_rectangle((0, 0, W - 1, H - 1), R, outline=(31, 31, 31, 255), width=2)
    return out


def classic(rank, suit):
    card = card_base()
    art = Image.open(os.path.join(CARDS, f"{suit}_{rank}.png")).convert("RGBA")
    scale = min(W / art.width, H / art.height)  # .aspectRatio(contentMode: .fit)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.LANCZOS)
    card.alpha_composite(art, ((W - art.width) // 2, (H - art.height) // 2))
    return finish(card)


def simple(rank, suit):
    card = card_base()
    colour = RED if suit in ("hearts", "diamonds") else BLACK
    sym = SYMBOL[suit]
    label = LABEL.get(rank, rank)
    # Corner index (rank over suit), top-left and rotated bottom-right.
    index = Image.new("RGBA", (round(W * 0.24), round(W * 0.42)), (0, 0, 0, 0))
    put(index, glyph(label, W * (0.17 if rank == "10" else 0.2), colour, FONT_BOLD), index.width / 2, index.height * 0.3)
    put(index, glyph(sym, W * 0.17, colour), index.width / 2, index.height * 0.72)
    put(card, index, W * 0.12, H * 0.14)
    put(card, index.rotate(180), W * 0.88, H * 0.86)
    if rank in ("jack", "queen", "king"):
        pw, ph = W * 0.56, H * 0.70
        x0, y0 = (W - pw) / 2, (H - ph) / 2
        d = ImageDraw.Draw(card)
        d.rectangle((x0, y0, x0 + pw, y0 + ph), fill=(252, 244, 222, 255), outline=(41, 77, 184, 255), width=5)
        d.rectangle((x0 + 7, y0 + 7, x0 + pw - 7, y0 + ph - 7), outline=(245, 199, 51, 255), width=3)
        half = Image.new("RGBA", (round(pw), round(ph / 2)), (0, 0, 0, 0))
        put(half, glyph(label, ph / 2 * 0.42, colour, SERIF_BOLD), half.width * 0.42, half.height * 0.62)
        put(half, glyph(sym, ph / 2 * 0.24, colour), half.width * 0.68, half.height * 0.66)
        put(card, half, W / 2, y0 + ph / 4)
        put(card, half.rotate(180), W / 2, y0 + ph * 3 / 4)
    elif rank == "ace":
        put(card, glyph(sym, W * (0.62 if suit == "spades" else 0.5), colour), W / 2, H / 2)
    else:
        x0, x1, y0, y1 = PIP_AREA
        for px, py in pips(rank):
            put(card, glyph(sym, W * 0.22, colour, rotate=py > 0.5), W * (x0 + (x1 - x0) * px), H * (y0 + (y1 - y0) * py))
    return finish(card)


def main(out):
    cols = len(CARDS_SHOWN)
    label_w = 150
    sheet = Image.new("RGBA", (label_w + GAP + cols * (W + GAP), GAP + 2 * (H + GAP)), (0, 128, 0, 255))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.truetype(FONT_BOLD, 30)
    for row, (name, make) in enumerate([("Classic", classic), ("Simple", simple)]):
        y = GAP + row * (H + GAP)
        d.text((GAP, y + H / 2), name, font=f, fill=(255, 255, 255), anchor="lm")
        for i, (rank, suit) in enumerate(CARDS_SHOWN):
            sheet.alpha_composite(make(rank, suit), (label_w + GAP + i * (W + GAP), y))
    sheet.convert("RGB").save(out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/workspace/preview-faces.png")
