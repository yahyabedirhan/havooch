#!/usr/bin/env python3
"""Build the third Havooch logo ("Paper cat") SVGs from one set of geometry.

Run it from anywhere: python3 assets/images/logo/v3-paper-cat/build_logo.py
It writes the SVG masters next to this file. export.py reads them.

Havuç's head, folded from paper in the style of Swift Lab's logo
(`yahyabedirhan/swift-lab`): flat faces lit from the right, no lines and no
gradients. One fold runs down the middle of the head, the white muzzle and
the nose, so the left half is shaded and the right half is lit. Each ear
folds from its tip to the middle of its foot, an orange outer face and a
peach inner face. The tile is Swift Lab's graphite tile with its two rims.

The helpers come from the first logo's build_logo.py, and the nose and the
mouth from the second logo's, two folders up and one folder over.
"""
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


v2 = _load("v2", os.path.join("..", "v2-havuc", "build_logo.py"))
v1 = v2.v1
f, circle, rounded_poly, svg = v1.f, v1.circle, v1.rounded_poly, v1.svg

CARROT, CARROT_SHADE = "#F37A1F", "#D4621A"     # the fur: the lit half and the shaded half
EAR, EAR_SHADE = "#F6863A", "#C95B17"           # the ears' outer faces
PEACH, PEACH_SHADE = "#F7B9A4", "#E39E89"       # the ears' inner faces
WHITE, WHITE_SHADE = "#FFFFFF", "#ECE4DC"       # the muzzle
INK = v2.INK                                    # the eyes and the mouth
PINK = v2.PINK                                  # the nose
GRAPHITE_TOP, GRAPHITE_FOOT = "#222529", "#131417"   # Swift Lab's tile

# The head, on the 256 grid: big upright ears set wide, a broad brow, cheek
# points and a soft chin. Corners are rounded, the ear tips the most.
HEAD = [(42, 20), (100, 80), (156, 80), (214, 20), (226, 110), (238, 158), (198, 212), (128, 230),
        (58, 212), (18, 158), (30, 110)]
HEAD_R = [14, 10, 10, 14, 8, 10, 12, 14, 12, 10, 8]
# The white: a narrow stripe down the nose that opens into the muzzle and chin.
MUZZLE = [(122, 96), (134, 96), (141, 150), (178, 164), (198, 188), (164, 212), (128, 220),
          (92, 212), (58, 188), (78, 164), (115, 150)]
MUZZLE_R = [5, 5, 4, 10, 10, 12, 12, 12, 10, 10, 4]

# The left ear's fold: from the tip to the middle of the ear's foot, run on
# past the tip so the fold leaves the outline cleanly.
TIP, FOOT, NOTCH = (42, 20), (30, 110), (100, 80)
MID = ((FOOT[0] + NOTCH[0]) / 2, (FOOT[1] + NOTCH[1]) / 2)
UP = (TIP[0] - (MID[0] - TIP[0]) * 0.4, TIP[1] - (MID[1] - TIP[1]) * 0.4)
EAR_OUTER = [UP, MID, FOOT, (-10, FOOT[1]), (-10, -10)]
EAR_INNER = [UP, (130, -10), NOTCH, MID]


def mirror(pts):
    return [(256 - x, y) for x, y in pts][::-1]


def poly(pts):
    return "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts) + "Z"


def halves(left, right):
    """The middle fold: a shaded left half and a lit right half. They overlap
    by one unit, so no seam shows between them."""
    return (f'<rect x="-10" y="-10" width="138.5" height="290" fill="{left}"/>'
            f'<rect x="127.5" y="-10" width="138.5" height="290" fill="{right}"/>')


def eye_geometry(small=False):
    """Left and right eye centres and the radius."""
    return ((86, 140), (170, 140), 27) if small else ((88, 140), (168, 140), 24)


def fur():
    """Every face of the fur, before it is clipped to the head (or to an eye ring)."""
    return (halves(CARROT_SHADE, CARROT)
            + f'<path fill="{EAR_SHADE}" d="{poly(EAR_OUTER)}"/>'
            + f'<path fill="{PEACH}" d="{poly(EAR_INNER)}"/>'
            + f'<path fill="{PEACH_SHADE}" d="{poly(mirror(EAR_INNER))}"/>'
            + f'<path fill="{EAR}" d="{poly(mirror(EAR_OUTER))}"/>')


def mark(prefix="", small=False):
    """The mark in colour, as defs and a body. `prefix` keeps the clip ids
    unique when two marks share one file."""
    (lx, ly), (rx, ry), r = eye_geometry(small)
    rings = circle(lx, ly, r + 5) + circle(rx, ry, r + 5)
    eyes = circle(lx, ly, r) + circle(rx, ry, r)
    off, gr = (9, 9.5) if small else (8, 7)
    glints = circle(lx + off, ly - off, gr) + circle(rx + off, ry - off, gr)
    nose = v2.nose(small)
    ids = {k: f"{prefix}{k}" for k in ("head", "muzzle", "rings", "nose")}
    defs = (f'<clipPath id="{ids["head"]}"><path d="{rounded_poly(HEAD, HEAD_R)}"/></clipPath>'
            f'<clipPath id="{ids["muzzle"]}"><path d="{rounded_poly(MUZZLE, MUZZLE_R)}"/></clipPath>'
            f'<clipPath id="{ids["rings"]}"><path d="{rings}"/></clipPath>'
            f'<clipPath id="{ids["nose"]}"><path d="{nose}"/></clipPath>')
    body = "".join([
        f'<g clip-path="url(#{ids["head"]})">{fur()}</g>',
        f'<g clip-path="url(#{ids["muzzle"]})">{halves(WHITE_SHADE, WHITE)}</g>',
        f'<g clip-path="url(#{ids["rings"]})">{fur()}</g>',   # the fur wraps each eye
        f'<path fill="{INK}" d="{eyes}"/>',
        f'<path fill="{WHITE}" d="{glints}"/>',
        f'<g clip-path="url(#{ids["nose"]})">{halves(PINK, PINK)}</g>',
        v2.mouth(small),
    ])
    return defs, body


# The mark's box on the 256 grid: x 18 to 238, y 20 (the ear tips) to 230 (the chin).
FULL_VIEW = "0 -1 256 256"     # the head a little above the middle, the optical centre
SMALL_VIEW = "14 11 228 228"   # the small cut, cropped tight to use every pixel


def mark_file(title, small=False):
    defs, body = mark(small=small)
    view = SMALL_VIEW if small else FULL_VIEW
    return svg(title, f"<defs>{defs}</defs>{body}", view=view)


def app_icon(small=False):
    """macOS app icon on the 1024 grid: an 824 squircle at 100 with a drop
    shadow, filled with Swift Lab's graphite gradient. Its two rims, a bright
    outer one and a faint inner one, fade from top to bottom. The 16 pt icon
    (16 and 32 px) drops the rims and draws the small-cut cat larger."""
    k = 824 / 256   # Swift Lab's rims are set on a 256 tile
    defs = (
        '<linearGradient id="tile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{GRAPHITE_TOP}"/><stop offset="1" stop-color="{GRAPHITE_FOOT}"/></linearGradient>'
        '<linearGradient id="rim" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.32"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.08"/></linearGradient>'
        '<linearGradient id="rim-inner" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0.03"/></linearGradient>'
        '<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="11"/><feOffset dy="10"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.35"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
    )
    body = f'<path d="{v1.squircle()}" fill="url(#tile)" filter="url(#shadow)"/>'
    if not small:
        o, i = 4 * k, 12 * k
        body += (f'<path d="{v1.squircle(100 + o, 100 + o, 824 - 2 * o)}" fill="none" '
                 f'stroke="url(#rim)" stroke-width="{f(2 * k)}"/>')
        body += (f'<path d="{v1.squircle(100 + i, 100 + i, 824 - 2 * i)}" fill="none" '
                 f'stroke="url(#rim-inner)" stroke-width="{f(1.5 * k)}"/>')
    scale, dy = (3.15, -2) if small else (2.7, -6)
    cat_defs, cat = mark(small=small)
    tx = 512 - 128 * scale
    ty = 512 - 128 * scale + dy
    body += f'<g transform="translate({f(tx)} {f(ty)}) scale({scale})">{cat}</g>'
    title = "Havooch app icon, paper cat" + (", small sizes" if small else "")
    return svg(title, f"<defs>{defs}{cat_defs}</defs>{body}", 1024, 1024)


def write(name, text):
    with open(os.path.join(HERE, name), "w") as fh:
        fh.write(text)


def main():
    write("havooch-mark.svg", mark_file("Havooch, paper cat"))
    write("havooch-mark-small.svg", mark_file("Havooch, paper cat, small sizes", small=True))
    write("havooch-app-icon.svg", app_icon())
    write("havooch-app-icon-small.svg", app_icon(small=True))


if __name__ == "__main__":
    main()
