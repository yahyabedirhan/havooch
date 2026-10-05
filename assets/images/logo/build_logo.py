#!/usr/bin/env python3
"""Build the Havooch logo SVGs from one set of geometry.

Run it from anywhere: python3 assets/images/logo/build_logo.py
It writes the SVG masters next to this file. The PNG exports and the
AppIcon.icns come from export.sh, which reads these SVGs.
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))

CARROT = "#F37A1F"   # the cat's orange fur
CREAM = "#FFFFFF"    # the white blaze and eyes
INK = "#2E1D14"      # the nose and the wordmark on light backgrounds
NIGHT = "#1B1F2A"    # the dark background used in tests and the app icon

# The head: one ellipse, centre (128, 146), radii 100 x 80.
CX, CY, RX, RY = 128, 146, 100, 80


def f(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def on_head(x, top=True):
    d = (x - CX) / RX
    h = RY * math.sqrt(max(0.0, 1 - d * d))
    return CY - h if top else CY + h


def toward(p, q, dist):
    length = math.hypot(q[0] - p[0], q[1] - p[1])
    t = min(dist / length, 0.5)
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


def rounded_poly(pts, r):
    """A closed polygon whose corners are rounded with quadratic curves."""
    d = ""
    n = len(pts)
    for i in range(n):
        prev, here, nxt = pts[i - 1], pts[i], pts[(i + 1) % n]
        ri = r[i] if isinstance(r, (list, tuple)) else r
        a, b = toward(here, prev, ri), toward(here, nxt, ri)
        d += ("M" if i == 0 else "L") + f"{f(a[0])} {f(a[1])}Q{f(here[0])} {f(here[1])} {f(b[0])} {f(b[1])}"
    return d + "Z"


def circle(cx, cy, r, clockwise=True):
    s = 1 if clockwise else 0
    return (f"M{f(cx - r)} {f(cy)}A{f(r)} {f(r)} 0 1 {s} {f(cx + r)} {f(cy)}"
            f"A{f(r)} {f(r)} 0 1 {s} {f(cx - r)} {f(cy)}Z")


def capsule(cx, cy, w, h):
    """A vertical capsule: a rounded bar like one half of the pause sign."""
    r = w / 2
    return (f"M{f(cx - r)} {f(cy - h / 2 + r)}A{f(r)} {f(r)} 0 0 1 {f(cx + r)} {f(cy - h / 2 + r)}"
            f"V{f(cy + h / 2 - r)}A{f(r)} {f(r)} 0 0 1 {f(cx - r)} {f(cy + h / 2 - r)}Z")


def head_outline():
    """The head and both ears as one closed outline, ears with rounded tips."""
    ear_out, ear_in, tip_x, tip_r = 34, 96, 50, 20
    tip = (tip_x, on_head(ear_in) - (ear_in - tip_x))  # the inner ear edge runs at exactly 45 degrees
    lo, li = (ear_out, on_head(ear_out)), (ear_in, on_head(ear_in))
    ro, ri = (256 - lo[0], lo[1]), (256 - li[0], li[1])
    rt = (256 - tip[0], tip[1])

    def corner(a, v, b):
        s, e = toward(v, a, tip_r), toward(v, b, tip_r)
        return f"L{f(s[0])} {f(s[1])}Q{f(v[0])} {f(v[1])} {f(e[0])} {f(e[1])}"

    d = f"M{f(lo[0])} {f(lo[1])}" + corner(lo, tip, li) + f"L{f(li[0])} {f(li[1])}"
    d += f"A{RX} {RY} 0 0 1 {f(ri[0])} {f(ri[1])}" + corner(ri, rt, ro) + f"L{f(ro[0])} {f(ro[1])}"
    d += f"A{RX} {RY} 0 1 1 {f(lo[0])} {f(lo[1])}Z"
    return d


def features(small=False):
    """The blaze, the eyes, and the ink details (nose and pupils).

    The blaze is a rounded triangle, the white stripe of an orange-and-white cat
    and a quiet play sign. The pupils are upright bars. The small cut for 16 and
    32 px drops the ink details and opens the eyes and the blaze.
    """
    if small:
        blaze = rounded_poly([(128, 90), (178, 194), (78, 194)], [14, 22, 22])
        eyes = circle(70, 128, 22) + circle(186, 128, 22)
        return blaze, eyes, ""
    blaze = rounded_poly([(128, 88), (174, 198), (82, 198)], [16, 24, 24])
    eyes = circle(78, 134, 17) + circle(178, 134, 17)
    pupils = capsule(80, 134, 10, 24) + capsule(176, 134, 10, 24)
    nose = rounded_poly([(115, 152), (141, 152), (128, 167)], 5)
    return blaze, eyes, nose + pupils


def mark_paths(fur, white, nose_colour, small=False, holes_only=False):
    """SVG elements for the cat head.

    holes_only: one colour. The blaze and the eyes are real holes, the nose an island.
    """
    blaze, eyes, nose = features(small)
    if holes_only:
        return f'<path fill="{fur}" fill-rule="evenodd" d="{head_outline()}{blaze}{eyes}{nose}"/>'
    return (f'<path fill="{white}" d="{blaze}{eyes}"/>'
            f'<path fill="{fur}" fill-rule="evenodd" d="{head_outline()}{blaze}{eyes}"/>'
            + (f'<path fill="{nose_colour}" d="{nose}"/>' if nose else ""))


# ---- the wordmark "Havooch", built from stems and rings ----------------------
# x-height 100 (y 100..200), ascender to y 60, stem 24, rounds radius 51 with overshoot.
STEM, BASE, XTOP, ASC = 24, 200, 100, 60
RO = 51            # outer radius of rounds (1 unit of overshoot above and below)
RI = RO - STEM     # inner radius
MID = (BASE + XTOP) / 2


def letter_H(x):
    w, bar_top, bar = 108, 118, 22
    return (f"M{x} {ASC}H{x + STEM}V{bar_top}H{x + w - STEM}V{ASC}H{x + w}V{BASE}H{x + w - STEM}"
            f"V{bar_top + bar}H{x + STEM}V{BASE}H{x}Z"), w


def letter_a(x):
    cx = x + RO
    sx = x + 2 * RO - STEM               # stem left edge
    dy = math.sqrt(RO * RO - (sx - cx) ** 2)
    d = (f"M{f(sx)} {XTOP}H{f(x + 2 * RO)}V{BASE}H{f(sx)}V{f(MID + dy)}"
         f"A{RO} {RO} 0 1 1 {f(sx)} {f(MID - dy)}Z")
    d += circle(cx, MID, RI, clockwise=False)
    return d, 2 * RO


def letter_v(x):
    w, half = 104, 15
    c = x + w / 2
    # the arms run at about 63 degrees; the joint is flat and wide enough to read
    return (f"M{x} {XTOP}H{x + 27}L{f(c)} {BASE - 34}L{x + w - 27} {XTOP}H{x + w}"
            f"L{f(c + half)} {BASE}H{f(c - half)}Z"), w


def letter_o(x):
    cx = x + RO
    return circle(cx, MID, RO) + circle(cx, MID, RI, clockwise=False), 2 * RO


def letter_c(x):
    cx, ang = x + RO, math.radians(42)
    ox, oy = cx + RO * math.cos(ang), MID - RO * math.sin(ang)
    obx, oby = ox, MID + RO * math.sin(ang)
    ix, iy = cx + RI * math.cos(ang), MID - RI * math.sin(ang)
    ibx, iby = ix, MID + RI * math.sin(ang)
    d = (f"M{f(ox)} {f(oy)}A{RO} {RO} 0 1 0 {f(obx)} {f(oby)}L{f(ibx)} {f(iby)}"
         f"A{RI} {RI} 0 1 1 {f(ix)} {f(iy)}Z")
    return d, 2 * RO - 6


def letter_h(x):
    r_o, r_i = 50, 26
    cx = x + r_o
    dy = math.sqrt(r_o * r_o - (STEM - r_o) ** 2)
    w = 2 * r_o
    d = (f"M{x} {ASC}H{x + STEM}V{f(MID - dy)}A{r_o} {r_o} 0 0 1 {x + w} {MID}V{BASE}H{x + w - STEM}V{MID}"
         f"A{r_i} {r_i} 0 0 0 {x + STEM} {MID}V{BASE}H{x}Z")
    return d, w


def wordmark(x0):
    # spacing: straight-to-round 16, round-to-round 12, diagonal pairs tighter
    plan = [(letter_H, 0), (letter_a, 16), (letter_v, 6), (letter_o, 6), (letter_o, 12), (letter_c, 12), (letter_h, 16)]
    d, x = "", x0
    for draw, gap in plan:
        x += gap
        part, w = draw(x)
        d += part
        x += w
    return d, x


def svg(title, body, w=256, h=256, extra="", view=None):
    view = view or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="{w}" height="{h}" '
            f'role="img" aria-labelledby="title"{extra}><title id="title">{title}</title>{body}</svg>\n')


def write(name, text):
    with open(os.path.join(HERE, name), "w") as fh:
        fh.write(text)


def lockup(word_fill, mark_body):
    word, end = wordmark(284)
    width = int(end + 28)
    body = f'<g id="symbol">{mark_body}</g><g id="wordmark"><path fill="{word_fill}" fill-rule="evenodd" d="{word}"/></g>'
    return width, body


def app_icon():
    """macOS app icon on the 1024 grid: an 824 rounded square at 100, radius 185.4, with Apple's drop shadow."""
    s = 2.75
    tx = 512 - 128 * s
    ty = 512 - 128 * s - 8  # optical centre: a little above the middle
    defs = (
        '<defs>'
        '<linearGradient id="tile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="#2A3142"/><stop offset="1" stop-color="{NIGHT}"/></linearGradient>'
        '<filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="10"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.3"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
        '</defs>'
    )
    tile = '<rect x="100" y="100" width="824" height="824" rx="185.4" fill="url(#tile)" filter="url(#shadow)"/>'
    edge = '<rect x="100.5" y="100.5" width="823" height="823" rx="185" fill="none" stroke="#FFFFFF" stroke-opacity="0.08"/>'
    cat = f'<g transform="translate({f(tx)} {f(ty)}) scale({s})">{mark_paths(CARROT, CREAM, INK)}</g>'
    return svg("Havooch app icon", defs + tile + edge + cat, 1024, 1024)


def app_icon_small():
    """The same icon for 16 and 32 px: the small-size cat, drawn larger on the tile."""
    s = 3.2
    tx = 512 - 128 * s
    ty = 512 - 128 * s - 8
    tile = f'<rect x="100" y="100" width="824" height="824" rx="185.4" fill="{NIGHT}"/>'
    cat = f'<g transform="translate({f(tx)} {f(ty)}) scale({s})">{mark_paths(CARROT, CREAM, INK, small=True)}</g>'
    return svg("Havooch app icon, small sizes", tile + cat, 1024, 1024)


# ---- the light app icon: a white tile like shipyard's ------------------------
# Measured from shipyard's app icon (yahyabedirhan/shipyard, Packaging/Icon/make-icon.swift,
# its frame and its white-* options): an 824 squircle (a superellipse, n = 5) at 100 on
# the 1024 grid; a white-to-#ECEFF3 body over a #C9CFD8 base that shows at the edge; a
# drop shadow 10 down, blur 22, black at 0.35; a 4-unit white rim at 0.6 inside the
# edge above 32 px; and the figure centred, its bounding box 483 x 571 (sized here by
# the box's geometric mean, 525), 1.1 / 0.92 times bigger below 64 px, with a soft
# shadow in its own colour. The inner shadow is ours: a barely visible inset at the edge.
LIGHT_TOP, LIGHT_BOTTOM, LIGHT_BASE = "#FFFFFF", "#ECEFF3", "#C9CFD8"
FIGURE = math.sqrt(483 * 571)   # shipyard's figure, as the geometric mean of its box
SMALL_FIGURE = 1.1 / 0.92        # shipyard draws its figure this much bigger below 64 px


def squircle(x=100, y=100, size=824, n=5, steps=240):
    """The macOS 11+ body: a superellipse filling the square, as shipyard draws it."""
    a = size / 2
    pts = []
    for i in range(steps):
        t = i / steps * 2 * math.pi
        c, s = math.cos(t), math.sin(t)
        pts.append((x + a + a * math.copysign(abs(c) ** (2 / n), c),
                    y + a + a * math.copysign(abs(s) ** (2 / n), s)))
    return "M" + "L".join(f"{f(px)} {f(py)}" for px, py in pts) + "Z"


def tip_top(a, v, b, r):
    """The highest y of an ear tip rounded as in head_outline: a quadratic from
    `r` before the corner `v`, through it as control, to `r` after it."""
    s, e = toward(v, a, r), toward(v, b, r)
    den = s[1] - 2 * v[1] + e[1]
    t = (s[1] - v[1]) / den if den else 0
    t = min(1, max(0, t))
    return (1 - t) ** 2 * s[1] + 2 * t * (1 - t) * v[1] + t * t * e[1]


def mark_bounds():
    """The head's bounding box on the 256 grid: the ellipse's width and foot, the ear tips' top."""
    ear_out, ear_in, tip_x, tip_r = 34, 96, 50, 20
    tip = (tip_x, on_head(ear_in) - (ear_in - tip_x))
    top = tip_top((ear_out, on_head(ear_out)), tip, (ear_in, on_head(ear_in)), tip_r)
    return CX - RX, min(top, CY - RY), CX + RX, CY + RY


def light_app_icon(title, mark_body, bounds, shade, small=False):
    """The white-tile app icon around `mark_body` (drawn on the 256 grid).

    `bounds` is the mark's box on that grid; the mark is scaled so its box's geometric
    mean matches shipyard's figure, and centred on the tile as shipyard centres its own.
    `shade` colours the mark's soft shadow. `small` is the cut for 16 and 32 px: the
    mark bigger, no rim.
    """
    x0, y0, x1, y1 = bounds
    s = FIGURE * (SMALL_FIGURE if small else 1) / math.sqrt((x1 - x0) * (y1 - y0))
    tx, ty = 512 - s * (x0 + x1) / 2, 512 - s * (y0 + y1) / 2
    body = squircle()
    defs = (
        '<defs>'
        '<linearGradient id="tile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{LIGHT_TOP}"/><stop offset="1" stop-color="{LIGHT_BOTTOM}"/></linearGradient>'
        f'<clipPath id="body"><path d="{body}"/></clipPath>'
        # shipyard's drop shadow: 10 down, blur 22, black at 0.35
        '<filter id="drop" x="-10%" y="-10%" width="120%" height="125%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="10"/><feOffset dy="10"/>'
        '<feComponentTransfer><feFuncA type="linear" slope="0.35"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>'
        # the inner shadow: the body's edge, blurred inward, at a few per cent
        '<filter id="inset" x="0" y="0" width="100%" height="100%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="4"/>'
        '<feComponentTransfer><feFuncA type="table" tableValues="1 0"/></feComponentTransfer>'
        '<feComposite in2="SourceAlpha" operator="in" result="edge"/>'
        '<feFlood flood-color="#1B2333" flood-opacity="0.09"/>'
        '<feComposite in2="edge" operator="in"/></filter>'
        # the mark's soft shadow in its own shade: 6 down, blur 16, at 0.22
        '<filter id="lift" x="-20%" y="-20%" width="140%" height="150%">'
        # (it sits inside the mark's scale, so its 1024-grid sizes are divided by it)
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{f(7 / s)}"/><feOffset dy="{f(6 / s)}" result="lift"/>'
        f'<feFlood flood-color="{shade}" flood-opacity="0.22"/><feComposite in2="lift" operator="in"/>'
        '</filter>'
        '</defs>'
    )
    layers = (
        f'<path d="{body}" fill="{LIGHT_BASE}" filter="url(#drop)"/>'
        f'<g clip-path="url(#body)"><path d="{body}" fill="url(#tile)"/>'
        f'<path d="{body}" fill="#000" filter="url(#inset)"/>'
    )
    mark = f'<g transform="translate({f(tx)} {f(ty)}) scale({f(s)})">'
    cat = (f'{mark}<g filter="url(#lift)">{mark_body}</g></g>'
           f'{mark}{mark_body}</g>')
    rim = "" if small else f'<path d="{body}" fill="none" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="4"/>'
    return svg(title, defs + layers + cat + rim + "</g>", 1024, 1024)


def main():
    # The full marks sit 3 units high in their square: the optical centre is above the middle.
    up = "0 3 256 256"
    write("havooch-mark.svg", svg("Havooch", mark_paths(CARROT, CREAM, INK), view=up))
    # The small cut is cropped tight, so it uses every pixel of a 16 px square.
    write("havooch-mark-small.svg", svg("Havooch, small sizes", mark_paths(CARROT, CREAM, INK, small=True),
                                        view="20 21 216 216"))
    write("havooch-mark-black.svg", svg("Havooch, one colour", mark_paths("#000000", None, None, holes_only=True), view=up))
    write("havooch-mark-white.svg", svg("Havooch, one colour reversed", mark_paths("#FFFFFF", None, None, holes_only=True), view=up))
    write("havooch-mark-carrot.svg", svg("Havooch, one colour carrot", mark_paths(CARROT, None, None, holes_only=True), view=up))
    for name, colour in [("black", "#000000"), ("white", "#FFFFFF"), ("carrot", CARROT)]:
        write(f"havooch-mark-small-{name}.svg", svg(f"Havooch, small sizes, one colour {name}",
                                                    mark_paths(colour, None, None, small=True, holes_only=True),
                                                    view="20 21 216 216"))

    w, body = lockup(INK, mark_paths(CARROT, CREAM, INK))
    write("havooch-lockup.svg", svg("Havooch", body, w))
    w, body = lockup("#FFFFFF", mark_paths(CARROT, CREAM, INK))
    write("havooch-lockup-dark.svg", svg("Havooch, for dark backgrounds", body, w))
    w, body = lockup("#000000", mark_paths("#000000", None, None, holes_only=True))
    write("havooch-lockup-black.svg", svg("Havooch, one colour", body, w))
    w, body = lockup("#FFFFFF", mark_paths("#FFFFFF", None, None, holes_only=True))
    write("havooch-lockup-white.svg", svg("Havooch, one colour reversed", body, w))

    write("havooch-app-icon.svg", app_icon())
    write("havooch-app-icon-small.svg", app_icon_small())
    write("havooch-app-icon-light.svg", light_app_icon("Havooch app icon, light", mark_paths(CARROT, CREAM, INK),
                                                       mark_bounds(), "#D9601A"))
    write("havooch-app-icon-light-small.svg", light_app_icon("Havooch app icon, light, small sizes",
                                                             mark_paths(CARROT, CREAM, INK, small=True),
                                                             mark_bounds(), "#D9601A", small=True))


if __name__ == "__main__":
    main()
