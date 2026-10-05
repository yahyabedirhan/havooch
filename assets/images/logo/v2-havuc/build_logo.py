#!/usr/bin/env python3
"""Build the second Havooch logo ("Havuç") SVGs from one set of geometry.

Run it from anywhere: python3 assets/images/logo/v2-havuc/build_logo.py
It writes the SVG masters next to this file. export.py reads them.

The wordmark, the helpers and the app-icon tile come from the first logo's
build_logo.py one folder up, so both logos share the same "Havooch" paths.
"""
import importlib.util
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("v1", os.path.join(HERE, "..", "build_logo.py"))
v1 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v1)
f, circle, toward, svg, wordmark = v1.f, v1.circle, v1.toward, v1.svg, v1.wordmark

CARROT = v1.CARROT   # the orange fur
WHITE = "#FFFFFF"    # the stripe, the muzzle and the catchlights
INK = v1.INK         # the eyes, the mouth and the wordmark on light backgrounds
NIGHT = v1.NIGHT     # the app icon tile and the dark test background
PEACH = "#F7B9A4"    # the inner ears
PINK = "#EE8E92"     # the nose
TABBY = "#D9601A"    # the faint forehead stripes

# The head: one wide ellipse, a little lower and rounder than the first logo, so
# the big ears fit above it and the face reads young.
CX, CY, RX, RY = 128, 150, 104, 82
RIM = 11  # orange kept below the white chin, so the head keeps its outline on white


def on_ellipse(x, rx, ry, top=True):
    d = (x - CX) / rx
    h = ry * math.sqrt(max(0.0, 1 - d * d))
    return CY - h if top else CY + h


def ear_points():
    """Left ear: outer foot, tip, inner foot. Large, upright and set wide."""
    out_x, in_x, tip_x = 32, 104, 50
    inner_y = on_ellipse(in_x, RX, RY)
    tip = (tip_x, inner_y - (in_x - tip_x))  # the inner ear edge runs at exactly 45 degrees
    return (out_x, on_ellipse(out_x, RX, RY)), tip, (in_x, inner_y)


def head_outline():
    """The head and both ears as one closed outline, ears with soft round tips."""
    lo, tip, li = ear_points()
    ro, rt, ri = (256 - lo[0], lo[1]), (256 - tip[0], tip[1]), (256 - li[0], li[1])
    tip_r = 26

    def corner(a, v, b):
        s, e = toward(v, a, tip_r), toward(v, b, tip_r)
        return f"L{f(s[0])} {f(s[1])}Q{f(v[0])} {f(v[1])} {f(e[0])} {f(e[1])}"

    d = f"M{f(lo[0])} {f(lo[1])}" + corner(lo, tip, li) + f"L{f(li[0])} {f(li[1])}"
    d += f"A{RX} {RY} 0 0 1 {f(ri[0])} {f(ri[1])}" + corner(ri, rt, ro) + f"L{f(ro[0])} {f(ro[1])}"
    d += f"A{RX} {RY} 0 1 1 {f(lo[0])} {f(lo[1])}Z"
    return d


def inner_ears():
    """Peach inner ears: a tall narrow triangle inside each ear, its outer edge
    upright and its inner edge at 60 degrees, its corners softened."""
    lo, tip, _ = ear_points()
    apex = (tip[0] + 7, tip[1] + 26)
    foot_y = lo[1] - 12
    run = (foot_y - apex[1]) * math.tan(math.radians(30))
    pts = [(apex[0], foot_y), apex, (apex[0] + run, foot_y)]
    d = ""
    for side in (1, -1):
        p = [(x if side == 1 else 256 - x, y) for x, y in pts]
        if side == -1:
            p = p[::-1]
        d += v1.rounded_poly(p, [10, 14, 10])
    return d


def eye_geometry(small=False):
    """Left and right eye centres and the radius."""
    return ((80, 140), (176, 140), 26) if small else ((88, 140), (168, 140), 24)


def stripe_geometry(small=False):
    """Half-width at the top, half-width at eye level, and the top of the stripe."""
    return (13, 18, 84) if small else (8, 12, 96)


def white_face(small=False):
    """The white: a narrow stripe from mid-forehead down the nose, opening below
    the eyes into a round muzzle and chin. An inverted Y, like a candle flame.

    One outline, all arcs and lines: a round-topped stripe that widens a little
    toward the eyes; a ring round each eye that just crosses the stripe, so the
    orange wraps the eye and the stripe flows into the muzzle with no sliver; a
    round cheek pad below each eye; and an ellipse inset RIM units from the head
    that carries the white round the chin.
    """
    ht, hb, top = stripe_geometry(small)
    pad_dx, pad_y, pad_r = (40, 182, 42) if small else (36, 184, 36)
    erx, ery = RX - RIM, RY - RIM
    _, (ex, ey), er = eye_geometry(small)
    ring = (ex - er) - (CX + hb) + 1.5 + er   # crosses the stripe edge by 1.5 units
    pcx = CX + pad_dx

    def in_ring(x, y):
        return (x - ex) ** 2 + (y - ey) ** 2 < ring ** 2

    def in_chin(x, y):
        return ((x - CX) / erx) ** 2 + ((y - CY) / ery) ** 2 < 1

    # walk down the right stripe edge until it meets the ring
    y0 = top + ht
    t = 0.0
    while True:
        t += 0.0005
        x, y = CX + ht + (hb - ht) * t, y0 + (ey - y0) * t
        if in_ring(x, y):
            meet = (x, y)
            break
    # walk the right pad clockwise from its top until it leaves the ring, then the chin
    a, leave = -math.pi, None
    while True:
        a += 0.0005
        x, y = pcx + pad_r * math.cos(a), pad_y + pad_r * math.sin(a)
        if leave is None:
            if (x - ex) ** 2 + (y - ey) ** 2 >= ring ** 2 and x > ex - ring * 0.2 and in_ring(
                    pcx + pad_r * math.cos(a - 0.01), pad_y + pad_r * math.sin(a - 0.01)):
                leave = (x, y)
        elif not in_chin(x, y):
            exit_ = (x, y)
            break

    def arc(r, sweep, pt):
        return f"A{f(r)} {f(r)} 0 0 {sweep} {f(pt[0])} {f(pt[1])}"

    right = [("L", None, None, meet), ("A", ring, 0, leave), ("A", pad_r, 1, exit_)]
    d = f"M{f(CX - ht)} {f(y0)}A{ht} {ht} 0 0 1 {f(CX + ht)} {f(y0)}"
    for kind, r, sweep, pt in right:
        d += f"L{f(pt[0])} {f(pt[1])}" if kind == "L" else arc(r, sweep, pt)
    d += f"A{erx} {ery} 0 0 1 {f(256 - exit_[0])} {f(exit_[1])}"
    # the left side: the right side mirrored and walked backwards (the sweep is unchanged)
    starts = [(CX + ht, y0)] + [c[3] for c in right[:-1]]
    for (kind, r, sweep, _), pt in zip(reversed(right), reversed(starts)):
        q = (256 - pt[0], pt[1])
        d += f"L{f(q[0])} {f(q[1])}" if kind == "L" else arc(r, sweep, q)
    return d + "Z"


def eyes(small=False):
    """Big round dark eyes, set wide and a little low: the face looks young and gentle."""
    left, right, r = eye_geometry(small)
    whole = circle(*left, r) + circle(*right, r)
    if small:
        return whole, ""
    glint = circle(left[0] + 8, left[1] - 8, 7) + circle(right[0] + 8, right[1] - 8, 7)
    return whole, glint


def nose():
    return v1.rounded_poly([(118, 160), (138, 160), (128, 172)], [6, 6, 5])


def stroke_bar(p, q, w):
    """A straight bar with round ends from p to q, as a filled outline."""
    r = w / 2
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = math.hypot(dx, dy)
    nx, ny = -dy / n * r, dx / n * r
    return (f"M{f(p[0] + nx)} {f(p[1] + ny)}L{f(q[0] + nx)} {f(q[1] + ny)}"
            f"A{f(r)} {f(r)} 0 0 0 {f(q[0] - nx)} {f(q[1] - ny)}L{f(p[0] - nx)} {f(p[1] - ny)}"
            f"A{f(r)} {f(r)} 0 0 0 {f(p[0] + nx)} {f(p[1] + ny)}Z")


def mouth():
    """A small 'w' under the nose: a short stem and two half rings with round ends.

    Every piece winds clockwise, so they merge under the nonzero fill rule.
    """
    w, r = 4.5, 7
    ro, ri, cy = r + w / 2, r - w / 2, 177
    d = stroke_bar((128, 170), (128, cy), w)
    for cx in (128 - r, 128 + r):
        d += (f"M{f(cx + ro)} {cy}A{f(ro)} {f(ro)} 0 0 1 {f(cx - ro)} {cy}"
              f"L{f(cx - ri)} {cy}A{f(ri)} {f(ri)} 0 0 0 {f(cx + ri)} {cy}Z")
        d += circle(cx - r, cy, w / 2) + circle(cx + r, cy, w / 2)
    return f'<path fill="{INK}" d="{d}"/>'


def tabby():
    """Three faint forehead marks, the 'M' of a ginger tabby. Large sizes only."""
    marks = [((128, 74), (128, 88)), ((104, 80), (110, 94)), ((152, 80), (146, 94))]
    return f'<path fill="{TABBY}" d="{"".join(stroke_bar(p, q, 7) for p, q in marks)}"/>'


def mark_colour(small=False):
    """The mark in full colour, painted back to front."""
    eye, glint = eyes(small)
    parts = [f'<path fill="{CARROT}" d="{head_outline()}"/>']
    if not small:
        parts.append(f'<path fill="{PEACH}" d="{inner_ears()}"/>')
        parts.append(tabby())
    parts.append(f'<path fill="{WHITE}" d="{white_face(small)}"/>')
    parts.append(f'<path fill="{INK}" d="{eye}"/>')
    if glint:
        parts.append(f'<path fill="{WHITE}" d="{glint}"/>')
    if not small:
        parts.append(f'<path fill="{PINK}" d="{nose()}"/>')
        parts.append(mouth())
    return "".join(parts)


def mark_mono(colour, small=False):
    """One colour: the head solid, the white face and the eyes cut out as holes.

    The catchlights come back as islands inside the eye holes, and the nose as an
    island inside the muzzle hole. Inner ears, tabby marks and the mouth drop out.
    """
    eye, glint = eyes(small)
    d = head_outline() + white_face(small) + eye + glint
    if not small:
        d += nose()
    return f'<path fill="{colour}" fill-rule="evenodd" d="{d}"/>'


def write(name, text):
    with open(os.path.join(HERE, name), "w") as fh:
        fh.write(text)


def lockup(word_fill, mark_body):
    word, end = wordmark(284)
    width = int(end + 28)
    body = f'<g id="symbol">{mark_body}</g><g id="wordmark"><path fill="{word_fill}" fill-rule="evenodd" d="{word}"/></g>'
    return width, body


def app_icon():
    """macOS app icon on the 1024 grid: the first logo's night tile, with the Havuç head."""
    s = 2.75
    tx = 512 - 128 * s
    ty = 512 - 128 * s - 8
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
    cat = f'<g transform="translate({f(tx)} {f(ty)}) scale({s})">{mark_colour()}</g>'
    return svg("Havooch app icon, Havuç", defs + tile + edge + cat, 1024, 1024)


def app_icon_small():
    """The same icon for 16 and 32 px: the small-cut cat, drawn larger on the tile."""
    s = 3.25
    tx = 512 - 128 * s
    ty = 512 - 128 * s - 4
    tile = f'<rect x="100" y="100" width="824" height="824" rx="185.4" fill="{NIGHT}"/>'
    cat = f'<g transform="translate({f(tx)} {f(ty)}) scale({s})">{mark_colour(small=True)}</g>'
    return svg("Havooch app icon, Havuç, small sizes", tile + cat, 1024, 1024)


def main():
    up = "0 6 256 256"            # optical centre: the head sits a little above the middle
    tight = "18 14 220 220"       # the small cut is cropped tight to use every pixel
    write("havooch-mark.svg", svg("Havooch, Havuç", mark_colour(), view=up))
    write("havooch-mark-small.svg", svg("Havooch, Havuç, small sizes", mark_colour(small=True), view=tight))
    for name, colour in [("black", "#000000"), ("white", "#FFFFFF"), ("carrot", CARROT)]:
        write(f"havooch-mark-{name}.svg", svg(f"Havooch, Havuç, one colour {name}", mark_mono(colour), view=up))
        write(f"havooch-mark-small-{name}.svg", svg(f"Havooch, Havuç, small sizes, one colour {name}",
                                                    mark_mono(colour, small=True), view=tight))

    for name, word_fill, body in [
        ("havooch-lockup.svg", INK, mark_colour()),
        ("havooch-lockup-dark.svg", "#FFFFFF", mark_colour()),
        ("havooch-lockup-black.svg", "#000000", mark_mono("#000000")),
        ("havooch-lockup-white.svg", "#FFFFFF", mark_mono("#FFFFFF")),
    ]:
        w, b = lockup(word_fill, body)
        write(name, svg("Havooch", b, w))

    write("havooch-app-icon.svg", app_icon())
    write("havooch-app-icon-small.svg", app_icon_small())


if __name__ == "__main__":
    main()
