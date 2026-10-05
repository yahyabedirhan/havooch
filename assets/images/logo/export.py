#!/usr/bin/env python3
"""Export the Havooch logo: PNGs, AppIcon.icns and the test sheet.

Needs rsvg-convert (brew install librsvg) and iconutil (macOS).
Run build_logo.py first when the geometry changes.
"""
import base64
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PNG = os.path.join(HERE, "png")


def render(svg, out, width=None, height=None):
    cmd = ["rsvg-convert", os.path.join(HERE, svg), "-o", out]
    if width:
        cmd += ["-w", str(width)]
    if height:
        cmd += ["-h", str(height)]
    subprocess.run(cmd, check=True)


def pngs():
    os.makedirs(PNG, exist_ok=True)
    for name in ["havooch-mark", "havooch-mark-black", "havooch-mark-white", "havooch-mark-carrot"]:
        for size in [16, 32, 64, 128, 256, 512, 1024]:
            src = name.replace("havooch-mark", "havooch-mark-small") + ".svg" if size <= 32 else name + ".svg"
            render(src, os.path.join(PNG, f"{name}-{size}.png"), size, size)
    for name in ["havooch-lockup", "havooch-lockup-dark", "havooch-lockup-black", "havooch-lockup-white"]:
        render(name + ".svg", os.path.join(PNG, f"{name}-1200.png"), width=1200)
    render("havooch-app-icon.svg", os.path.join(PNG, "havooch-app-icon-1024.png"), 1024, 1024)
    # the light app icon at every size: the small cut at 16 and 32 px
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        src = "havooch-app-icon-light-small.svg" if size <= 32 else "havooch-app-icon-light.svg"
        render(src, os.path.join(PNG, f"havooch-app-icon-light-{size}.png"), size, size)


def icns(big="havooch-app-icon.svg", small="havooch-app-icon-small.svg", out="AppIcon.icns"):
    """An .icns from an .iconset: the small cut at 16 and 32 px, the full icon from 64 px up."""
    work = tempfile.mkdtemp()
    iconset = os.path.join(work, "AppIcon.iconset")
    os.makedirs(iconset)
    for pt in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            px = pt * scale
            suffix = "" if scale == 1 else "@2x"
            src = small if px <= 32 else big
            render(src, os.path.join(iconset, f"icon_{pt}x{pt}{suffix}.png"), px, px)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(HERE, out)], check=True)
    shutil.rmtree(work)


def data_uri(path):
    with open(path, "rb") as fh:
        return "data:image/png;base64," + base64.b64encode(fh.read()).decode()


def test_sheet():
    """One image with every test: backgrounds, one colour, reversed, the size ladder and 16 px pixels."""
    tmp = tempfile.mkdtemp()

    def png(svg, w, h=None):
        out = os.path.join(tmp, f"{svg}-{w}-{h}.png")
        render(svg, out, w, h)
        return data_uri(out)

    def label(x, y, text, fill="#555"):
        return f'<text x="{x}" y="{y}" font-family="Helvetica, Arial" font-size="15" fill="{fill}">{text}</text>'

    parts = ['<rect width="1600" height="1500" fill="#F4F2EE"/>',
             '<text x="48" y="64" font-family="Helvetica, Arial" font-size="30" font-weight="bold" fill="#2E1D14">Havooch logo, test sheet</text>']

    # Row 1: backgrounds and one-colour versions
    tiles = [("havooch-mark.svg", "#FFFFFF", "colour on white"),
             ("havooch-mark.svg", "#1B1F2A", "colour on dark"),
             ("havooch-mark-black.svg", "#FFFFFF", "one colour, black"),
             ("havooch-mark-white.svg", "#1B1F2A", "reversed, white"),
             ("havooch-mark-white.svg", "#F37A1F", "white on carrot"),
             ("havooch-mark-carrot.svg", "#FFFFFF", "one colour, carrot")]
    for i, (svg, bg, text) in enumerate(tiles):
        x = 48 + i * 254
        parts.append(f'<rect x="{x}" y="96" width="230" height="230" rx="16" fill="{bg}" stroke="#DDD"/>')
        parts.append(f'<image x="{x + 25}" y="121" width="180" height="180" href="{png(svg, 360, 360)}"/>')
        parts.append(label(x, 350, text))

    # Row 2: size ladder at true pixel size, light and dark
    parts.append(label(48, 400, "true size: 128 / 64 / 48 / 32 / 24 / 16 px (32 px and below use the small cut)", "#2E1D14"))
    for row, bg in enumerate(["#FFFFFF", "#1B1F2A"]):
        y = 416 + row * 150
        parts.append(f'<rect x="48" y="{y}" width="700" height="140" rx="12" fill="{bg}"/>')
        x = 64
        for size in [128, 64, 48, 32, 24, 16]:
            src = "havooch-mark-small.svg" if size <= 32 else "havooch-mark.svg"
            parts.append(f'<image x="{x}" y="{y + 6 + (128 - size) // 2}" width="{size}" height="{size}" href="{png(src, size, size)}"/>')
            x += size + 40
    # Row 2 right: app icon ladder
    parts.append(label(800, 400, "app icon: 128 / 64 / 32 / 16 px", "#2E1D14"))
    parts.append('<rect x="800" y="416" width="752" height="290" rx="12" fill="#D9DEE6"/>')
    x = 820
    for size in [128, 64, 32, 16]:
        src = "havooch-app-icon-small.svg" if size <= 32 else "havooch-app-icon.svg"
        parts.append(f'<image x="{x}" y="{430 + (128 - size) // 2}" width="{size}" height="{size}" href="{png(src, size, size)}"/>')
        x += size + 40
    parts.append('<rect x="800" y="576" width="752" height="130" rx="12" fill="#1E1E1E"/>')
    x = 820
    for size in [128, 64, 32, 16]:
        src = "havooch-app-icon-small.svg" if size <= 32 else "havooch-app-icon.svg"
        parts.append(f'<image x="{x}" y="{577 + (128 - size) // 2}" width="{size}" height="{size}" href="{png(src, size, size)}"/>')
        x += size + 40

    # Row 3: 16 px and 32 px, magnified 8x and 4x with hard pixels
    parts.append(label(48, 760, "16 px at 8x: full mark, small cut, small cut in one colour, app icon.   32 px at 4x: small cut, app icon", "#2E1D14"))
    zoom = [("havooch-mark.svg", 16, "#FFFFFF"), ("havooch-mark-small.svg", 16, "#FFFFFF"),
            ("havooch-mark-small-black.svg", 16, "#FFFFFF"), ("havooch-app-icon-small.svg", 16, "#D9DEE6"),
            ("havooch-mark-small.svg", 32, "#1B1F2A"), ("havooch-app-icon-small.svg", 32, "#D9DEE6")]
    x = 48
    for svg, size, bg in zoom:
        parts.append(f'<rect x="{x}" y="776" width="128" height="128" fill="{bg}"/>')
        parts.append(f'<image x="{x}" y="776" width="128" height="128" style="image-rendering:pixelated" '
                     f'image-rendering="optimizeSpeed" href="{png(svg, size, size)}"/>')
        x += 152
    # squint: the mark blurred
    parts.append('<defs><filter id="squint"><feGaussianBlur stdDeviation="6"/></filter></defs>')
    parts.append(f'<rect x="{x + 16}" y="776" width="128" height="128" fill="#FFFFFF"/>')
    parts.append(f'<image x="{x + 16}" y="776" width="128" height="128" filter="url(#squint)" href="{png("havooch-mark.svg", 256, 256)}"/>')
    parts.append(label(x + 16, 925, "squint"))

    # Row 4: lockups
    parts.append(label(48, 980, "lockups: colour, dark, one colour, reversed", "#2E1D14"))
    locks = [("havooch-lockup.svg", "#FFFFFF"), ("havooch-lockup-dark.svg", "#1B1F2A"),
             ("havooch-lockup-black.svg", "#FFFFFF"), ("havooch-lockup-white.svg", "#F37A1F")]
    for i, (svg, bg) in enumerate(locks):
        x, y = 48 + (i % 2) * 760, 996 + (i // 2) * 230
        parts.append(f'<rect x="{x}" y="{y}" width="744" height="210" rx="16" fill="{bg}" stroke="#DDD"/>')
        parts.append(f'<image x="{x + 40}" y="{y + 45}" width="664" height="120" href="{png(svg, 1328)}" preserveAspectRatio="xMinYMid meet"/>')
    # small lockup at menu-bar height
    parts.append(label(48, 1480, "lockup at 24 px tall:", "#2E1D14"))
    parts.append(f'<image x="210" y="1460" width="200" height="24" href="{png("havooch-lockup.svg", None, 48)}" preserveAspectRatio="xMinYMid meet"/>')

    sheet = os.path.join(tmp, "sheet.svg")
    with open(sheet, "w") as fh:
        fh.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 1500" width="1600" height="1500">'
                 + "".join(parts) + "</svg>")
    subprocess.run(["rsvg-convert", sheet, "-o", os.path.join(HERE, "havooch-test-sheet.png")], check=True)
    shutil.rmtree(tmp)


SHIPYARD_ICNS = os.environ.get(
    "SHIPYARD_ICNS", os.path.expanduser("~/Developer/yahyabedirhan/shipyard/Packaging/Icon/AppIcon.icns"))


def compare_light():
    """compare-icons-light.png: shipyard's app icon beside both light Havooch icons,
    at 1024, 128, 32 and 16 px (then 32 and 16 px magnified), on a light and a dark
    Dock-like background. Shipyard's icon is read from its .icns (SHIPYARD_ICNS)."""
    if not os.path.exists(SHIPYARD_ICNS):
        print(f"skipped compare-icons-light.png: no shipyard icon at {SHIPYARD_ICNS}")
        return
    tmp = tempfile.mkdtemp()
    iconset = os.path.join(tmp, "shipyard.iconset")
    subprocess.run(["iconutil", "-c", "iconset", SHIPYARD_ICNS, "-o", iconset], check=True)
    shipyard = {1024: "icon_512x512@2x.png", 128: "icon_128x128.png", 32: "icon_32x32.png", 16: "icon_16x16.png"}

    def havooch(folder, size):
        svg = "havooch-app-icon-light-small.svg" if size <= 32 else "havooch-app-icon-light.svg"
        out = os.path.join(tmp, f"{os.path.basename(folder)}-{size}.png")
        subprocess.run(["rsvg-convert", os.path.join(folder, svg), "-o", out, "-w", str(size), "-h", str(size)], check=True)
        return data_uri(out)

    icons = [("shipyard", lambda size: data_uri(os.path.join(iconset, shipyard[size]))),
             ("v1, Play blaze, light", lambda size: havooch(HERE, size)),
             ("v2, Havuç, light", lambda size: havooch(os.path.join(HERE, "v2-havuc"), size))]

    def text(x, y, s, size=22, weight="normal", fill="#2E1D14"):
        return (f'<text x="{x}" y="{y}" font-family="Helvetica, Arial" font-size="{size}" '
                f'font-weight="{weight}" fill="{fill}">{s}</text>')

    W, H = 3264, 1960
    parts = [f'<rect width="{W}" height="{H}" fill="#F4F2EE"/>',
             text(48, 64, "Shipyard and the light Havooch app icons", 34, "bold")]
    # 1024 px, true size, on the light Dock grey
    for i, (name, draw) in enumerate(icons):
        x = 48 + i * 1072
        parts.append(text(x, 120, f"{name}: 1024 px"))
        parts.append(f'<rect x="{x}" y="136" width="1024" height="1024" rx="24" fill="#E6E6E9"/>')
        parts.append(f'<image x="{x}" y="136" width="1024" height="1024" href="{draw(1024)}"/>')
    # 128, 32 and 16 px true size, then 32 px at 4x and 16 px at 8x, on light and dark
    for row, (bg, ink, label) in enumerate([("#E6E6E9", "#2E1D14", "light Dock"), ("#1E1E20", "#FFFFFF", "dark Dock")]):
        y = 1200 + row * 370
        for i, (name, draw) in enumerate(icons):
            x0 = 48 + i * 1072
            parts.append(text(x0, y, f"{name}, {label}: 128 / 32 / 16 px, then 32 px at 4x and 16 px at 8x"))
            parts.append(f'<rect x="{x0}" y="{y + 16}" width="1024" height="320" rx="16" fill="{bg}"/>')
            x = x0 + 24
            for size in [128, 32, 16]:
                parts.append(f'<image x="{x}" y="{y + 40 + (256 - size) // 2}" width="{size}" height="{size}" href="{draw(size)}"/>')
                x += size + 40
            for size in [32, 16]:
                parts.append(f'<image x="{x}" y="{y + 40}" width="256" height="256" style="image-rendering:pixelated" '
                             f'image-rendering="optimizeSpeed" href="{draw(size)}"/>')
                x += 256 + 32

    sheet = os.path.join(tmp, "compare.svg")
    with open(sheet, "w") as fh:
        fh.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
                 + "".join(parts) + "</svg>")
    subprocess.run(["rsvg-convert", sheet, "-o", os.path.join(HERE, "compare-icons-light.png")], check=True)
    shutil.rmtree(tmp)


if __name__ == "__main__":
    pngs()
    icns()
    icns("havooch-app-icon-light.svg", "havooch-app-icon-light-small.svg", "AppIcon-light.icns")
    test_sheet()
    compare_light()   # reads v2-havuc's light SVGs: run v2-havuc/build_logo.py first
    print("wrote png/, AppIcon.icns, AppIcon-light.icns, havooch-test-sheet.png and compare-icons-light.png")
