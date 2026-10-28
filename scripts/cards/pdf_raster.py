"""Rasterises a Classic card face PDF for the preview and website scripts (not used by the app,
which renders the PDFs itself). Uses poppler's pdftoppm when present (Linux, `brew install
poppler`), else macOS `sips`; both draw the vectors directly at the requested height."""
import io, os, shutil, subprocess, tempfile
from PIL import Image


def render_pdf(path, height):
    """Page 1 of `path` as an RGBA image `height` px tall (the page's own aspect)."""
    if shutil.which("pdftoppm"):
        png = subprocess.run(["pdftoppm", "-png", "-singlefile", "-r", "300", "-scale-to-y", str(height),
                              "-scale-to-x", "-1", "-transp", path, "-"], capture_output=True, check=True).stdout
        return Image.open(io.BytesIO(png)).convert("RGBA")
    if shutil.which("sips"):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "page.png")
            # sips renders at 72 dpi, so scale the page to the wanted height first.
            subprocess.run(["sips", "-s", "format", "png", "--resampleHeight", str(height), path, "--out", out],
                           capture_output=True, check=True)
            return Image.open(out).convert("RGBA")
    raise SystemExit("need pdftoppm (poppler) or macOS sips to rasterise " + path)
