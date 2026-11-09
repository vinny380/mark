# Builds Resources/AppIcon.icns from Resources/AppIcon.png (1024px) with small, palette-optimized PNGs.
# Writes the .icns container directly (iconutil re-encodes PNGs and undoes the optimization).
# Needs Pillow at build time only:  /tmp/v/bin/python scripts/make-icon.py
import io, os, struct
from PIL import Image
root = os.path.join(os.path.dirname(__file__), "..", "Resources")
src = Image.open(os.path.join(root, "AppIcon.png")).convert("RGBA")

def png(px):
    buf = io.BytesIO()
    src.resize((px, px), Image.LANCZOS).quantize(colors=64, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(buf, "PNG", optimize=True)
    return buf.getvalue()

# icns entry types that hold PNG data, by pixel size (16, 32, 64, 128, 256, 512, 1024)
types = [("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64), ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]
cache = {}
body = b"".join(t.encode() + struct.pack(">I", 8 + len(d)) + d for t, d in ((t, cache.setdefault(px, png(px))) for t, px in types))
out = os.path.join(root, "AppIcon.icns")
with open(out, "wb") as f:
    f.write(b"icns" + struct.pack(">I", 8 + len(body)) + body)
print("icns:", os.path.getsize(out) // 1024, "KB")
