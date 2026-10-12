#!/usr/bin/env python3
"""Export the third Havooch logo (Paper cat): PNGs, AppIcon.icns and the test sheet.

Needs rsvg-convert (brew install librsvg) and iconutil (macOS).
Run build_logo.py first when the geometry changes.
"""
import importlib.util
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PNG = os.path.join(HERE, "png")

_spec = importlib.util.spec_from_file_location("v2_export", os.path.join(HERE, "..", "v2-havuc", "export.py"))
v2_export = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v2_export)
data_uri = v2_export.data_uri

# The largest size, in points, that shows the small cut. The app's
# HavoochMark follows the same rule (HavoochMarkImage.smallCutLimit).
SMALL_CUT_LIMIT = v2_export.SMALL_CUT_LIMIT
SIZES = [16, 32, 64, 128, 256, 512, 1024]


def render(svg, out, width=None, height=None):
    cmd = ["rsvg-convert", os.path.join(HERE, svg), "-o", out]
    if width:
        cmd += ["-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    subprocess.run(cmd, check=True)


def pngs():
    os.makedirs(PNG, exist_ok=True)
    for size in SIZES:
        small = size <= SMALL_CUT_LIMIT
        render("havooch-mark-small.svg" if small else "havooch-mark.svg",
               os.path.join(PNG, f"havooch-mark-{size}.png"), size, size)
        render("havooch-app-icon-small.svg" if small else "havooch-app-icon.svg",
               os.path.join(PNG, f"havooch-app-icon-{size}.png"), size, size)


def test_sheet():
    """The app icon and the mark at true sizes on light and dark, and 16 and 32 px magnified."""
    tmp = tempfile.mkdtemp()

    def png(svg, size):
        out = os.path.join(tmp, f"{svg}-{size}.png")
        render(svg, out, size, size)
        return data_uri(out)

    def label(x, y, text):
        return f'<text x="{x}" y="{y}" font-family="Helvetica, Arial" font-size="18" fill="#2E1D14">{text}</text>'

    def ladder(kind, y, bg):
        parts = [f'<rect x="48" y="{y}" width="1104" height="170" rx="14" fill="{bg}"/>']
        x = 72
        for size in [128, 64, 32, 16]:
            src = f"havooch-{kind}-small.svg" if size <= SMALL_CUT_LIMIT else f"havooch-{kind}.svg"
            parts.append(f'<image x="{x}" y="{y + 21 + (128 - size) // 2}" width="{size}" height="{size}" href="{png(src, size)}"/>')
            x += size + 48
        # 32 px at 4x and 16 px at 8x, with hard pixels
        for size, src in [(32, f"havooch-{kind}.svg"), (16, f"havooch-{kind}-small.svg")]:
            parts.append(f'<image x="{x}" y="{y + 21}" width="128" height="128" image-rendering="optimizeSpeed" '
                         f'style="image-rendering:pixelated" href="{png(src, size)}"/>')
            x += 128 + 48
        return "".join(parts)

    parts = ['<rect width="1200" height="1700" fill="#F4F2EE"/>',
             '<text x="48" y="70" font-family="Helvetica, Arial" font-size="32" font-weight="bold" fill="#2E1D14">'
             'Havooch logo v3 (Paper cat), test sheet</text>',
             label(48, 112, "app icon, 1024 px"),
             f'<image x="48" y="128" width="540" height="540" href="{png("havooch-app-icon.svg", 1080)}"/>',
             label(612, 112, "mark, on light and dark"),
             '<rect x="612" y="128" width="540" height="262" rx="14" fill="#FFFFFF"/>',
             f'<image x="751" y="139" width="240" height="240" href="{png("havooch-mark.svg", 480)}"/>',
             '<rect x="612" y="406" width="540" height="262" rx="14" fill="#1B1F2A"/>',
             f'<image x="751" y="417" width="240" height="240" href="{png("havooch-mark.svg", 480)}"/>']
    y = 720
    for kind, title in [("app-icon", "app icon"), ("mark", "mark")]:
        for bg, name in [("#E6E8EC", "light"), ("#1E1E1E", "dark")]:
            parts.append(label(48, y - 10, f"{title} on {name}: 128 / 64 / 32 / 16 px (16 px is the small cut), "
                                           "then 32 px at 4x and the small cut at 16 px at 8x"))
            parts.append(ladder(kind, y, bg))
            y += 240
    sheet = os.path.join(tmp, "sheet.svg")
    with open(sheet, "w") as fh:
        fh.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 1700" width="1200" height="1700">'
                 + "".join(parts) + "</svg>")
    subprocess.run(["rsvg-convert", sheet, "-o", os.path.join(HERE, "havooch-test-sheet.png")], check=True)


def main():
    pngs()
    v2_export.HERE = HERE   # build the .icns from this folder's SVGs, into this folder
    v2_export.icns()
    test_sheet()


if __name__ == "__main__":
    main()
