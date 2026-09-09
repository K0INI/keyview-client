# KOINIkeyview app icon generator - keyhole MARK only (brand rule), warm on noir.
# Geometry = the site wordmark SVG (viewBox 24x30). Run from repo root: python3 tool/gen_icons.py
# Deliberately flat (no nested blocks) so it can be typed into a web editor.
import json, os
from PIL import Image, ImageDraw
NOIR = (11, 11, 14, 255)
WARM = (255, 253, 245, 255)
def mark(size, ss=4): return _mark(size, ss)
def _mark(size, ss): S = size * ss; im = Image.new("RGBA", (S, S), NOIR); d = ImageDraw.Draw(im); u = S * 0.58 / 30.0; ox = S / 2 - 12 * u; oy = S / 2 - 15 * u; r = 2.1 * u; d.ellipse((ox + 12 * u - r, oy + 6 * u - r, ox + 12 * u + r, oy + 6 * u + r), fill=WARM); d.rounded_rectangle((ox + 10.9 * u, oy + 7.2 * u, ox + 13.1 * u, oy + 10.6 * u), radius=1.0 * u, fill=WARM); R = 7.6 * u; w = 1.5 * u; d.ellipse((ox + 12 * u - R - w / 2, oy + 20 * u - R - w / 2, ox + 12 * u + R + w / 2, oy + 20 * u + R + w / 2), outline=WARM, width=int(round(w))); return im.resize((size, size), Image.LANCZOS)
def rounded(im): s = im.size[0]; m = Image.new("L", (s * 4, s * 4), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * 0.2237), fill=255); m = m.resize((s, s), Image.LANCZOS); out = Image.new("RGBA", (s, s), (0, 0, 0, 0)); out.paste(im, (0, 0), m); return out
def macos_icon(size): inner = int(round(size * 824 / 1024)); tile = rounded(mark(inner)); out = Image.new("RGBA", (size, size), (0, 0, 0, 0)); out.paste(tile, ((size - inner) // 2, (size - inner) // 2), tile); return out
MAC = "macos/Runner/Assets.xcassets/AppIcon.appiconset"
for s in (16, 32, 64, 128, 256, 512, 1024): macos_icon(s).save(os.path.join(MAC, "app_icon_%d.png" % s))
IOS = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
IMAGES = json.load(open(os.path.join(IOS, "Contents.json")))["images"]
for img in IMAGES: mark(int(round(float(img["size"].split("x")[0]) * int(img["scale"].rstrip("x"))))).convert("RGB").save(os.path.join(IOS, img["filename"]))
for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)): mark(px).save("android/app/src/main/res/mipmap-%s/ic_launcher.png" % dpi)
WIN = "windows/runner/resources/app_icon.ico"
if os.path.isdir(os.path.dirname(WIN)): mark(256).save(WIN, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icons generated")
