"""Rasterises a Classic card face PDF for the preview and website scripts (not used by the app,
which renders the PDFs itself). Uses poppler's pdftocairo when present (Linux, `brew install
poppler`), else macOS `sips`; both draw the vectors directly at the requested height, on a
transparent background."""
import io, os, shutil, subprocess, tempfile
from PIL import Image


def render_pdf(path, height):
    """Page 1 of `path` as an RGBA image `height` px tall (the page's own aspect)."""
    if shutil.which("pdftocairo"):
        # pdftoppm has no -transp; pdftocairo keeps the page transparent. `-` writes the PNG to stdout.
        png = subprocess.run(["pdftocairo", "-png", "-transp", "-singlefile", "-f", "1", "-l", "1",
                              "-scale-to-y", str(height), "-scale-to-x", "-1", path, "-"],
                             capture_output=True, check=True).stdout
        return Image.open(io.BytesIO(png)).convert("RGBA")
    if shutil.which("sips"):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "page.png")
            # sips renders at 72 dpi, so scale the page to the wanted height first.
            subprocess.run(["sips", "-s", "format", "png", "--resampleHeight", str(height), path, "--out", out],
                           capture_output=True, check=True)
            return Image.open(out).convert("RGBA")
    raise SystemExit("need pdftocairo (poppler: `brew install poppler` or `apt install poppler-utils`) "
                     "or macOS sips to rasterise " + path)
