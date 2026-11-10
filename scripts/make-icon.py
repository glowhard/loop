# Builds the app icon and the top-bar mark from assets/logo-source.png
# (a glowing colour mark on black). Run with: python scripts/make-icon.py
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "logo-source.png"

src = Image.open(SRC).convert("RGB")
r, g, b = src.split()
bright = ImageChops.lighter(ImageChops.lighter(r, g), b)  # how lit each pixel is, whatever its colour

# Where the solid ribbon is, leaving out the glow that fades away around it.
box = bright.point(lambda v: 255 if v > 150 else 0).getbbox()
ribbon_w = box[2] - box[0]
centre = ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
edge = src.getpixel((2, 2))  # the picture's own background, so the tile continues it without a seam


def tile(size):
    """A square, rounded tile: the whole picture, scaled so the ribbon nearly fills it, glow and all."""
    scale = 4 if size < 256 else 2  # draw large, then shrink, for clean edges
    s = size * scale
    k = s * (0.92 if size <= 32 else 0.80) / ribbon_w  # tiny icons need the ribbon as large as it will go
    whole = src.resize((round(src.width * k), round(src.height * k)), Image.LANCZOS)
    face = Image.new("RGB", (s, s), edge)
    face.paste(whole, (round(s / 2 - centre[0] * k), round(s / 2 - centre[1] * k)))
    shape = Image.new("L", (s, s), 0)
    ImageDraw.Draw(shape).rounded_rectangle([0, 0, s - 1, s - 1], radius=round(s * 0.22), fill=255)
    out = face.convert("RGBA")
    out.putalpha(shape)
    return out.resize((size, size), Image.LANCZOS)


assets = ROOT / "assets"
tile(512).save(assets / "icon.png")
sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
tiles = [tile(n) for n in sizes]
tiles[-1].save(assets / "icon.ico", sizes=[(n, n) for n in sizes], append_images=tiles[:-1])

# The mark alone, for the top bar: just the ribbon, with the dark background and
# most of the glow made see-through so it stays crisp when it is small.
pad = round(ribbon_w * 0.03)
art = src.crop((box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad))
small = art.resize((320, round(320 * art.height / art.width)), Image.LANCZOS)
sr, sg, sb = small.split()
alpha = ImageChops.lighter(ImageChops.lighter(sr, sg), sb)
alpha = alpha.point(lambda v: 0 if v < 95 else min(255, round((v - 95) * 255 / 90)))
logo = Image.merge("RGBA", [sr, sg, sb, alpha])
logo.save(ROOT / "src" / "renderer" / "logo.png")

# ---- the phone app, from the same mark ----

app = ROOT / "app"
if app.exists():
    # Android: the square icon, and the round one some launchers ask for.
    for folder, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        out = app / "android" / "app" / "src" / "main" / "res" / f"mipmap-{folder}"
        out.mkdir(parents=True, exist_ok=True)
        square = tile(size)
        square.save(out / "ic_launcher.png")
        circle = Image.new("L", (size * 4, size * 4), 0)
        ImageDraw.Draw(circle).ellipse([0, 0, size * 4 - 1, size * 4 - 1], fill=255)
        round_icon = tile(size * 4)
        round_icon.putalpha(circle)
        round_icon.resize((size, size), Image.LANCZOS).save(out / "ic_launcher_round.png")

    # Android 8 and later draw their own shape around a larger square, so the
    # mark is given room and the tile's own corners are dropped.
    for folder, size in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        out = app / "android" / "app" / "src" / "main" / "res" / f"mipmap-{folder}"
        out.mkdir(parents=True, exist_ok=True)
        big = tile(size * 2).resize((round(size * 1.38), round(size * 1.38)), Image.LANCZOS)
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        layer.paste(big, (round((size - big.width) / 2), round((size - big.height) / 2)), big)
        layer.save(out / "ic_launcher_foreground.png")
    anydpi = app / "android" / "app" / "src" / "main" / "res" / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        (anydpi / name).write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background" />\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
            '</adaptive-icon>\n',
            encoding="utf-8",
        )
    values = app / "android" / "app" / "src" / "main" / "res" / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        f'    <color name="ic_launcher_background">#{edge[0]:02X}{edge[1]:02X}{edge[2]:02X}</color>\n'
        '</resources>\n',
        encoding="utf-8",
    )
    # A white mark on nothing: what Android draws in the status bar.
    bar = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    mark = logo.resize((84, round(84 * logo.height / logo.width)), Image.LANCZOS)
    white = Image.new("RGBA", mark.size, (255, 255, 255, 255))
    white.putalpha(mark.split()[3])
    bar.paste(white, (6, round((96 - mark.height) / 2)), white)
    for folder, size in [("mdpi", 24), ("hdpi", 36), ("xhdpi", 48), ("xxhdpi", 72), ("xxxhdpi", 96)]:
        out = app / "android" / "app" / "src" / "main" / "res" / f"drawable-{folder}"
        out.mkdir(parents=True, exist_ok=True)
        bar.resize((size, size), Image.LANCZOS).save(out / "ic_stat_loop.png")

    # iOS: one flat square per size, no transparency, as the App Store wants.
    ios = app / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    if ios.exists():
        for f in ios.glob("*.png"):
            size = Image.open(f).size[0]
            flat = Image.new("RGB", (size, size), edge)
            art_sq = tile(size if size >= 64 else 64).resize((size, size), Image.LANCZOS)
            flat.paste(art_sq, (0, 0), art_sq)
            flat.save(f)
    print("phone app icons written")

print("icon.png, icon.ico and logo.png written", "mark box", box)
