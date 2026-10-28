#!/usr/bin/env python3
"""Draws classic faces the way CardView does (white rounded card, art, 1 px border) on felt."""
import os, sys
from PIL import Image, ImageDraw
from pdf_raster import render_pdf
CARDS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Sources", "SpiderSolitaire", "Resources", "Cards")
names = sys.argv[2:] or ["spades_king", "spades_queen", "spades_jack", "spades_ace",
                         "hearts_king", "hearts_queen", "hearts_jack", "hearts_ace"]
W, H, R, GAP = 240, 324, 17, 24  # R = 0.07 * width, like CardStyle.cornerRadius
cols = int(os.environ.get("COLS", "4"))
rows = (len(names) + cols - 1) // cols
sheet = Image.new("RGBA", (GAP + cols * (W + GAP), GAP + rows * (H + GAP)), (0, 128, 0, 255))
for i, n in enumerate(names):
    x, y = GAP + (i % cols) * (W + GAP), GAP + (i // cols) * (H + GAP)
    card = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, H - 1), R, fill=255)
    face = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    # Like the app: the vector art rendered straight at the card height (2:3, fits the 71:96 card), centred.
    art = render_pdf(os.path.join(CARDS, n + ".pdf"), H)
    face.alpha_composite(art, ((W - art.width) // 2, (H - art.height) // 2))
    card.paste(face, (0, 0), mask)
    ImageDraw.Draw(card).rounded_rectangle((0, 0, W - 1, H - 1), R, outline=(31, 31, 31, 255), width=2)
    sheet.alpha_composite(card, (x, y))
sheet.convert("RGB").save(sys.argv[1] if len(sys.argv) > 1 else "/workspace/classic-preview.png")
