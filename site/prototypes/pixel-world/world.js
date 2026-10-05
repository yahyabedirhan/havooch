// Havooch "pixel-world": a lit isometric diorama, rendered in software.
//
// Everything is drawn into a 384x216 pixel buffer by hand (no images, no
// third-party art): the sky, a floating stone island, the screening room
// with its screen, the workshop with its lamp and terminal, Havuç sitting,
// Havuç walking the path with the notes, and the replies flying back.
// A lighting pass then shades every pixel from the scene's lights with an
// ordered dither, emissive pixels get a bloom, and the result is scaled up
// with nearest-neighbour sampling.
(() => {
  "use strict";

  const W = 320, H = 180;
  const canvas = document.getElementById("world");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  canvas.width = W; canvas.height = H;
  const image = ctx.createImageData(W, H);
  const out = image.data;

  // Buffers --------------------------------------------------------------
  const base = new Float32Array(W * H * 3);   // albedo
  const emit = new Uint8Array(W * H);          // 1 = emissive, skip lighting, feeds bloom
  const bloomA = new Float32Array(W * H * 3);
  const bloomB = new Float32Array(W * H * 3);

  const hex = (s) => [parseInt(s.slice(1, 3), 16), parseInt(s.slice(3, 5), 16), parseInt(s.slice(5, 7), 16)];
  const mix = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
  const mul = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
  const hash = (x, y) => { let h = (x * 374761393 + y * 668265263) | 0; h = (h ^ (h >> 13)) * 1274126177; return ((h ^ (h >> 16)) >>> 0) / 4294967296; };
  const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];

  const put = (x, y, c, e) => {
    if (x < 0 || y < 0 || x >= W || y >= H) return;
    const i = (y * W + x);
    base[i * 3] = c[0]; base[i * 3 + 1] = c[1]; base[i * 3 + 2] = c[2];
    emit[i] = e ? 1 : 0;
  };
  const rect = (x, y, w, h, c, e) => { for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) put(x + i, y + j, c, e); };
  // A vertical column fill: the face edge runs from (x0,y0) over dx columns
  // climbing dy, and each column is h pixels tall. shade(fx, fy, sx, sy) gives
  // the colour, or null to skip the pixel; it may return [rgb, emissive].
  const face = (x0, y0, dx, dy, h, shade) => {
    const n = Math.abs(dx), sgn = Math.sign(dx) || 1;
    for (let k = 0; k <= n; k++) {
      const sx = x0 + k * sgn;
      const top = Math.round(y0 + (k / n) * dy);
      for (let j = 0; j < h; j++) {
        const r = shade(k / n, j / h, sx, top + j);
        if (!r) continue;
        if (Array.isArray(r[0])) put(sx, top + j, r[0], r[1]); else put(sx, top + j, r, false);
      }
    }
  };
  // A convex polygon fill by scanline.
  const poly = (pts, shade) => {
    let y0 = Infinity, y1 = -Infinity;
    for (const p of pts) { y0 = Math.min(y0, p[1]); y1 = Math.max(y1, p[1]); }
    for (let y = Math.ceil(y0); y <= Math.floor(y1); y++) {
      let xa = Infinity, xb = -Infinity;
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length];
        if ((y >= a[1] && y <= b[1]) || (y >= b[1] && y <= a[1])) {
          if (a[1] === b[1]) { xa = Math.min(xa, a[0], b[0]); xb = Math.max(xb, a[0], b[0]); }
          else { const x = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1]); xa = Math.min(xa, x); xb = Math.max(xb, x); }
        }
      }
      for (let x = Math.ceil(xa); x <= Math.floor(xb); x++) { const r = shade(x, y); if (r) put(x, y, r); }
    }
  };

  // Isometric projection: world (u, v, z) in tile units, tile 16x8 px.
  const OX = 140, OY = 44;
  const sx = (u, v) => Math.round(OX + (u - v) * 8);
  const sy = (u, v, z = 0) => Math.round(OY + (u + v) * 4 - z);

  // A box of w x d tiles and h px high, top at z. Faces: top, left (+v side), right (+u side).
  const box = (u, v, w, d, z, h, col, tex) => {
    const t = tex || {};
    const fl = sx(u, v + d), fy = sy(u, v + d, z);         // left corner
    const ff = sx(u + w, v + d), ffy = sy(u + w, v + d, z); // front corner
    const fr = sx(u + w, v), fry = sy(u + w, v, z);         // right corner
    // left face: from left corner to front corner, climbing down (dy>0)
    face(fl, fy, ff - fl, ffy - fy, h, (fx, fyy, px, py) => (t.left ? t.left(fx, fyy, px, py) : col.left));
    face(ff, ffy, fr - ff, fry - ffy, h, (fx, fyy, px, py) => (t.right ? t.right(fx, fyy, px, py) : col.right));
    poly([[sx(u, v), sy(u, v, z)], [fr, fry], [ff, ffy], [fl, fy]], (px, py) => (t.top ? t.top(px, py) : col.top));
  };

  // Palette ----------------------------------------------------------------
  const C = {
    skyTop: hex("#07091a"), skyMid: hex("#141334"), skyLow: hex("#2a1f45"),
    hillFar: hex("#121631"), hillNear: hex("#0d1026"),
    stoneTop: hex("#5c5f7e"), stoneTop2: hex("#54577a"), stoneLeft: hex("#3f4160"), stoneRight: hex("#2c2e48"), cliff: hex("#232540"), cliffDark: hex("#17182d"),
    pathTop: hex("#7a6f78"), pathTop2: hex("#6f6570"),
    wallTop: hex("#6e5a68"), wallLeft: hex("#4e3f52"), wallRight: hex("#3b2f40"), brick: hex("#5a4659"),
    woodTop: hex("#8a5a3a"), woodLeft: hex("#6b4229"), woodRight: hex("#4d2f1d"),
    screenBezel: hex("#10121f"), screenOff: hex("#1b2240"),
    teal: hex("#39d7dc"), tealDim: hex("#1a7f8c"),
    gold: hex("#ffc566"), goldDeep: hex("#ff9a2e"), ember: hex("#ff6a2a"),
    carrot: hex("#f37a1f"), carrotDark: hex("#b9540f"), cream: hex("#fff3e3"), creamShade: hex("#d8c6b4"),
    ink: hex("#2e1d14"), pink: hex("#f7b9a4"), nose: hex("#ee8e92"), white: hex("#ffffff"),
    paper: hex("#fbf1dc"), paperLine: hex("#c9a98a"), botBody: hex("#c0c9e0"), botDark: hex("#6a7594"), botFace: hex("#7fe0ff"),
    grass: hex("#3f7a66"), grass2: hex("#2f5f55"), crateTop: hex("#a37444"), crateLeft: hex("#7d5531"), crateRight: hex("#5a3b22"), rug: hex("#b8503a"), rugDark: hex("#7e3326"),
    moon: hex("#dfe8ff"), moonShade: hex("#b9c6ea"), star: hex("#cfd8ff"),
  };

  // Sprites ----------------------------------------------------------------
  // Letters map to the palette; "." is transparent.
  const SP = {
    O: C.carrot, o: C.carrotDark, W: C.cream, w: C.creamShade, K: C.ink, P: C.pink, N: C.nose, E: C.white,
    B: C.botBody, b: C.botDark, F: C.botFace, G: C.gold, p: C.paper, l: C.paperLine, c: C.ember, T: C.teal,
  };
  const sprite = (rows, x, y, flip, emissiveLetters) => {
    const h = rows.length;
    for (let j = 0; j < h; j++) {
      const row = rows[j];
      for (let i = 0; i < row.length; i++) {
        const ch = row[i];
        if (ch === ".") continue;
        const c = SP[ch]; if (!c) continue;
        put(x + (flip ? row.length - 1 - i : i), y + j, c, emissiveLetters && emissiveLetters.includes(ch));
      }
    }
  };

  // Havuç, sitting with his back half turned, looking up at the screen, one paw raised.
  const CAT_SIT = [
    "..OO..........OO..",
    "..OPO........OPO..",
    "..OOPO......OPOO..",
    "..OOOOOOOOOOOOOO..",
    ".OOOOOOOWWOOOOOOO.",
    ".OOOOOOOWWOOOOOOO.",
    ".OOOKKOOWWOOKKOOO.",
    ".OOOKEKOWWOKEKOOO.",
    ".OOOKKOWWWWOKKOOO.",
    "..OOOOWWWWWWOOOO..",
    "..OOOOWWNNWWOOOO..",
    "...OOOWWWWWWOOO...",
    "....OOOWWWWOOO....",
    "....OOOOOOOOOO....",
    "...OOOOOWWOOOOOO..",
    "...OOOOWWWWOOOOO..",
    "...OOOOWWWWOOOOOO.",
    "...OWOOWWWWOOOWOO.",
    "...oWooooooooWoo..",
  ];
  // The raised paw, drawn separately so it can wave.
  const CAT_PAW = ["WO", "OO"];
  // Havuç walking right, two frames of legs, with the satchel of notes.
  const CAT_WALK = [
    [
      "...OO.....OO......",
      "...OPO...OPO......",
      "...OOOOOOOOOW.....",
      "...OOKOOOOKOWW....",
      "...OOOOOOOOOWWW...",
      "....OOOOOOOWWW....",
      "OOOOOOOOOOOOW.....",
      "OOOOOOOOOOOOO.....",
      "oOOOOOOOOOOO......",
      ".oOOOOOOOOOO......",
      "..OW..OW..OW......",
      "..oW..oW..oW......",
    ],
    [
      "...OO.....OO......",
      "...OPO...OPO......",
      "...OOOOOOOOOW.....",
      "...OOKOOOOKOWW....",
      "...OOOOOOOOOWWW...",
      "....OOOOOOOWWW....",
      "OOOOOOOOOOOOW.....",
      "OOOOOOOOOOOOO.....",
      "oOOOOOOOOOOO......",
      ".oOOOOOOOOOO......",
      ".OW..OW..OW.......",
      ".oW..oW..oW.......",
    ],
  ];
  const SATCHEL = ["ppppp", "pllpp", "ppppp", "plllp"];
  // The agent: a small round robot with a glowing face.
  const BOT = [
    "....bb....",
    "...bBBb...",
    "..bFFFFb..",
    ".bFFFFFFb.",
    ".bFFFFFFb.",
    "..bFFFFb..",
    "...bBBb...",
    ".bBBBBBBb.",
    "bBBBBBBBBb",
    "bBBBBBBBBb",
    ".bBBBBBBb.",
    "..bb..bb..",
  ];
  const NOTE = ["ppppp", "plllp", "ppppp", "pllpp", "ppppp"];
  const ENVELOPE = ["cccc", "cGGc", "cccc"];

  // Scene parts ------------------------------------------------------------
  const sky = () => {
    for (let y = 0; y < H; y++) {
      const t = y / H;
      const c = t < 0.55 ? mix(C.skyTop, C.skyMid, t / 0.55) : mix(C.skyMid, C.skyLow, (t - 0.55) / 0.45);
      for (let x = 0; x < W; x++) {
        const d = (BAYER[(x & 3) + (y & 3) * 4] / 16 - 0.5) * 6;
        put(x, y, [c[0] + d, c[1] + d, c[2] + d], false);
      }
    }
    for (let k = 0; k < 80; k++) {
      const x = Math.floor(hash(k, 1) * W), y = Math.floor(hash(k, 2) * H * 0.6);
      const tw = 0.55 + 0.45 * Math.sin(frame * 0.05 + k * 1.7);
      put(x, y, mul(C.star, tw), hash(k, 3) > 0.75);
    }
    // the moon, with a quiet crater
    const mx = 268, my = 30, r = 12;
    for (let y = -r; y <= r; y++) for (let x = -r; x <= r; x++) {
      if (x * x + y * y > r * r) continue;
      const shade = (x + 5) * (x + 5) + (y - 3) * (y - 3) < 16 ? C.moonShade : C.moon;
      put(mx + x, my + y, shade, true);
    }
    // far hills and a lit town, under the island
    for (let x = 0; x < W; x++) {
      const h1 = 128 + Math.sin(x * 0.024) * 8 + Math.sin(x * 0.061 + 1.3) * 4;
      const h2 = 142 + Math.sin(x * 0.019 + 2) * 7 + Math.sin(x * 0.047) * 3;
      for (let y = Math.round(h1); y < H; y++) put(x, y, C.hillFar, false);
      for (let y = Math.round(h2); y < H; y++) put(x, y, C.hillNear, false);
    }
    for (let k = 0; k < 30; k++) {
      const x = 10 + Math.floor(hash(k, 9) * (W - 20));
      const y = 136 + Math.floor(hash(k, 8) * 34);
      if (hash(k, 7) + 0.3 * Math.sin(frame * 0.02 + k) > 0.35) put(x, y, hash(k, 6) > 0.5 ? C.gold : C.teal, true);
    }
  };

  const line = (x0, y0, x1, y1, shade) => {
    const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) || 1;
    for (let k = 0; k <= n; k++) {
      const x = Math.round(x0 + (x1 - x0) * k / n), y = Math.round(y0 + (y1 - y0) * k / n);
      const c = shade(x, y); if (c) put(x, y, c, false);
    }
  };

  const U = 14, V = 8;
  const island = () => {
    const HGT = 15;
    const stone = (px, py) => {
      const n = hash(px, py);
      return n > 0.93 ? C.stoneTop2 : (n < 0.04 ? mix(C.stoneTop, C.stoneRight, 0.5) : C.stoneTop);
    };
    box(0, 0, U, V, 0, HGT, { top: C.stoneTop, left: C.cliff, right: C.cliffDark }, {
      top: stone,
      left: (fx, fy, px, py) => (fy > 0.8 + hash(px, 1) * 0.2 ? null : (hash(px, py) > 0.88 ? C.stoneLeft : mix(C.cliff, C.cliffDark, fy))),
      right: (fx, fy, px, py) => (fy > 0.8 + hash(px, 2) * 0.2 ? null : (hash(px, py) > 0.9 ? C.stoneRight : mix(C.cliffDark, C.skyTop, fy * 0.8))),
    });
    for (let u = 0; u <= U; u++) line(sx(u, 0), sy(u, 0), sx(u, V), sy(u, V), (px, py) => (hash(px, py) > 0.3 ? C.stoneTop2 : null));
    for (let v = 0; v <= V; v++) line(sx(0, v), sy(0, v), sx(U, v), sy(U, v), (px, py) => (hash(px, py) > 0.3 ? C.stoneTop2 : null));
    // the path of flagstones from the screening room to the workshop
    poly([[sx(4.6, 3.3), sy(4.6, 3.3)], [sx(9.2, 3.3), sy(9.2, 3.3)], [sx(9.2, 4.9), sy(9.2, 4.9)], [sx(4.6, 4.9), sy(4.6, 4.9)]],
      (px, py) => (hash(px, py) > 0.78 ? C.pathTop2 : C.pathTop));
    for (let u = 4.6; u <= 9.2; u += 0.92) line(sx(u, 3.3), sy(u, 3.3), sx(u, 4.9), sy(u, 4.9), () => C.pathTop2);
    line(sx(4.6, 4.1), sy(4.6, 4.1), sx(9.2, 4.1), sy(9.2, 4.1), (px) => (px % 3 ? C.pathTop2 : null));
    // grass tufts along the front edges
    for (let k = 0; k < 14; k++) {
      const u = 0.4 + hash(k, 21) * 13, v = 6.2 + hash(k, 22) * 1.6;
      if (u > 8.4 && v < 4.6) continue;
      const x = sx(u, v), y = sy(u, v);
      const g = k % 2 ? C.grass : C.grass2;
      put(x, y - 1, g); put(x - 1, y - 1, g); put(x + 1, y - 2, g); put(x, y - 2, g);
    }
    // crates by the workshop's step, and a rolled rug by the stage
    box(8.2, 6.2, 0.9, 0.9, 10, 10, { top: C.crateTop, left: C.crateLeft, right: C.crateRight }, { left: (fx, fy) => (fy < 0.12 || fy > 0.88 || Math.abs(fx - fy) < 0.07 ? C.crateRight : C.crateLeft) });
    box(9.3, 6.4, 0.7, 0.7, 7, 7, { top: C.crateTop, left: C.crateLeft, right: C.crateRight });
    box(8.4, 5.3, 0.6, 0.6, 7, 7, { top: C.crateTop, left: C.crateLeft, right: C.crateRight });
    box(2, 6.3, 1.6, 0.5, 4, 4, { top: C.rug, left: C.rugDark, right: C.rugDark }, { top: (px, py) => ((px + py) % 3 ? C.rug : C.rugDark) });
  };

  // The screening room: a brick wall at the island's left-back, the screen on its right face.
  const screeningRoom = () => {
    const brick = (fx, fy, px, py) => {
      const row = Math.floor(fy * 12), col = Math.floor(fx * 8 + (row % 2) * 0.5);
      const seam = (fy * 12) % 1 < 0.16 || (fx * 8 + (row % 2) * 0.5) % 1 < 0.12;
      return seam ? C.wallRight : (hash(col, row) > 0.8 ? C.brick : C.wallLeft);
    };
    box(0.6, 0.4, 4.6, 5.4, 0, 3, { top: C.wallTop, left: C.wallLeft, right: C.wallRight }, { top: (px, py) => (hash(px, py) > 0.9 ? C.wallLeft : mix(C.wallTop, C.stoneTop, 0.45)) });
    const wh = 44;
    box(0.6, 0.4, 0.6, 5.4, 3 + wh, wh, { top: C.wallTop, left: C.wallLeft, right: C.wallRight }, { left: brick, right: (fx, fy, px, py) => screen(fx, fy, px, py, brick) });
    // a standing lamp at the end of the screen
    const lx = sx(4.9, 0.9), ly = sy(4.9, 0.9, 3);
    rect(lx, ly - 30, 1, 30, C.ink, false);
    rect(lx - 2, ly - 34, 5, 4, C.goldDeep, true);
    rect(lx - 1, ly - 35, 3, 1, C.gold, true);
    // Havuç, sitting on the slab, a paw up at the screen
    const cx = sx(3.3, 3.2) - 9, cy = sy(3.3, 3.2, 3) - 19;
    sprite(CAT_SIT, cx, cy, false);
    const wave = Math.round(Math.sin(frame * 0.12) * 1.5);
    sprite(CAT_PAW, cx - 2, cy + 7 - wave, false);
    // the queue of notes, floating beside him
    for (let k = 0; k < 3; k++) {
      const bob = Math.round(Math.sin(frame * 0.07 + k * 1.3) * 1.5);
      sprite(NOTE, cx + 20 + k * 3, cy + 1 - k * 6 + bob, false, "pl");
    }
  };

  const screen = (fx, fy, px, py, fallback) => {
    const bx0 = 0.07, bx1 = 0.93, by0 = 0.08, by1 = 0.72;
    if (fx < bx0 || fx > bx1 || fy < by0 || fy > by1) return fallback(fx, fy, px, py);
    const ix = (fx - bx0) / (bx1 - bx0), iy = (fy - by0) / (by1 - by0);
    const bez = 0.04;
    if (ix < bez || ix > 1 - bez || iy < bez * 1.6 || iy > 1 - bez * 1.6) return [C.screenBezel, false];
    const vx = (ix - bez) / (1 - 2 * bez), vy = (iy - bez * 1.6) / (1 - 3.2 * bez);
    let c = mix(hex("#3b62b0"), hex("#7a4fae"), vx);
    const dx = vx - 0.28, dy = (vy - 0.42) * 1.4;
    if (dx * dx + dy * dy < 0.03) c = hex("#a9c6ff");
    if (vx > 0.5 && vx < 0.84 && vy > 0.3 && vy < 0.58) c = hex("#c995e6");
    const on = Math.sin(frame * 0.08) > -0.2;
    const inRegion = vx > 0.46 && vx < 0.88 && vy > 0.21 && vy < 0.67;
    const inInner = vx > 0.5 && vx < 0.84 && vy > 0.28 && vy < 0.6;
    if (on && inRegion && !inInner) return [C.carrot, true];
    if (vx > 0.06 && vx < 0.11 && vy > 0.76 && vy < 0.92) return [C.cream, true];
    if (vx > 0.15 && vx < 0.2 && vy > 0.76 && vy < 0.92) return [C.cream, true];
    if (vy > 0.94 && vy < 0.985 && vx > 0.26 && vx < 0.92) return [vx < 0.42 ? C.carrot : hex("#7a86a8"), vx < 0.42];
    const scan = ((py + Math.floor(frame / 3)) % 5 === 0) ? 0.85 : 1;
    return [mul(mix(c, C.teal, 0.1), scan), true];
  };

  // The workshop: a plank wall at the right-back, a bench, the lamp, the terminal, the agent.
  const workshop = () => {
    const planks = (fx, fy, px, py) => ((fy * 8) % 1 < 0.13 ? C.woodRight : (hash(Math.floor(fx * 16), Math.floor(fy * 8)) > 0.85 ? C.woodTop : C.woodLeft));
    box(8.6, 0.3, 5.2, 4.3, 0, 3, { top: C.woodTop, left: C.woodLeft, right: C.woodRight }, { top: (px, py) => (((px + py * 2) % 7 === 0) ? C.woodLeft : C.woodTop) });
    box(8.6, 0.3, 5.2, 0.6, 3 + 38, 38, { top: C.woodTop, left: C.woodLeft, right: C.woodRight }, {
      left: (fx, fy, px, py) => {
        if (fx > 0.1 && fx < 0.4 && fy > 0.16 && fy < 0.5) {
          const gx = (fx - 0.1) / 0.3, gy = (fy - 0.16) / 0.34;
          if (gx < 0.08 || gx > 0.92 || gy < 0.1 || gy > 0.9) return [C.ink, false];
          if (Math.abs(gx - 0.5) < 0.045 || Math.abs(gy - 0.5) < 0.06) return [C.ink, false];
          return [mix(C.goldDeep, C.gold, gy), true];
        }
        if (fx > 0.56 && fx < 0.82 && fy > 0.18 && fy < 0.42) {
          const kx = (fx - 0.56) / 0.26, ky = (fy - 0.18) / 0.24;
          if (kx < 0.08 || kx > 0.92 || ky < 0.1 || ky > 0.9) return [C.paper, false];
          return [mix(hex("#2b4a86"), hex("#5a3a80"), kx), false];
        }
        return planks(fx, fy, px, py);
      },
    });
    box(9.8, 1.7, 3, 1, 3 + 9, 9, { top: C.woodTop, left: C.woodLeft, right: C.woodRight });
    box(10, 1.85, 1.3, 0.45, 12 + 11, 11, { top: C.botDark, left: C.ink, right: C.botDark }, {
      left: (fx, fy, px, py) => {
        if (fx < 0.08 || fx > 0.92 || fy < 0.1 || fy > 0.86) return [C.ink, false];
        const rowf = fy * 9 + frame / 9;
        const row = Math.floor(rowf % 6);
        const len = 0.3 + hash(row, 1 + Math.floor(rowf / 6)) * 0.55;
        const lit = Math.floor(fy * 9) % 2 === 0 && fx < len;
        return [lit ? (row === 2 ? C.carrot : C.teal) : hex("#0c1a20"), true];
      },
    });
    const lx = sx(13.2, 2.2), ly = sy(13.2, 2.2, 3);
    rect(lx, ly - 36, 1, 36, C.ink, false);
    rect(lx - 7, ly - 38, 7, 1, C.ink, false);
    rect(lx - 9, ly - 37, 5, 3, C.goldDeep, true);
    rect(lx - 8, ly - 34, 3, 1, C.gold, true);
    const bob = Math.round(Math.sin(frame * 0.15) * 1);
    sprite(BOT, sx(11.4, 3.4) - 5, sy(11.4, 3.4, 3) - 13 + bob, false, "F");
    for (let k = 0; k < 4; k++) {
      const t = ((frame * 0.03 + k * 0.25) % 1);
      const px = sx(10.4, 2.2) + Math.round(k * 3 - 4 + Math.sin(t * 6 + k) * 2), py = sy(10.4, 2.2, 12) - 8 - Math.round(t * 12);
      if (t < 0.8) put(px, py, k % 2 ? C.gold : C.ember, true);
    }
  };

  // Havuç carrying the notes down the path, and the replies flying back.
  const PERIOD = 420;
  const traffic = () => {
    const t = (frame % PERIOD) / PERIOD;
    if (t < 0.45) {
      const u = 4.4 + (t / 0.45) * 5;
      const stepFrame = Math.floor(frame / 7) % 2;
      const x = sx(u, 4.1) - 9, y = sy(u, 4.1) - 13 - (stepFrame ? 1 : 0);
      sprite(CAT_WALK[stepFrame], x, y, false);
      sprite(SATCHEL, x + 3, y + 3, false, "pl");
    } else if (t < 0.55) {
      const x = sx(9.4, 4.1) - 9, y = sy(9.4, 4.1) - 13;
      sprite(CAT_WALK[0], x, y, false);
    }
    if (t > 0.5 && t < 0.98) {
      const s = (t - 0.5) / 0.48;
      for (let k = 0; k < 3; k++) {
        const ss = s - k * 0.08;
        if (ss < 0 || ss > 1) continue;
        const u = 9.6 - ss * 6, v = 3.6;
        const arc = Math.sin(ss * Math.PI) * 24;
        const x = sx(u, v), y = sy(u, v, 14) - Math.round(arc);
        sprite(ENVELOPE, x - 2, y - 1, false, "cG");
        for (let q = 1; q < 4; q++) {
          const uu = u + q * 0.3;
          const aa = Math.sin(Math.min(1, ss + q * 0.012) * Math.PI) * 24;
          put(sx(uu, v) + 1, sy(uu, v, 14) - Math.round(aa), mul(C.ember, 1 - q * 0.25), true);
        }
      }
    }
    for (const u of [5.6, 7.9]) {
      const x = sx(u, 5.2), y = sy(u, 5.2);
      rect(x, y - 14, 1, 14, C.ink, false);
      rect(x - 1, y - 17, 3, 3, C.goldDeep, true);
      put(x, y - 18, C.gold, true);
    }
  };

  // Lights -----------------------------------------------------------------
  const lights = () => {
    const t = frame;
    const L = [
      { x: sx(1.2, 3.1), y: sy(1.2, 3.1, 26), r: 110, c: [0.45, 1.15, 1.3], i: 1.5 + 0.05 * Math.sin(t * 0.08) }, // the screen
      { x: sx(13.2, 2.2) - 7, y: sy(13.2, 2.2, 3) - 36, r: 72, c: [1.2, 0.82, 0.35], i: 1.1 + 0.04 * Math.sin(t * 0.3) }, // the lamp
      { x: sx(4.9, 0.9), y: sy(4.9, 0.9, 3) - 33, r: 36, c: [1.1, 0.75, 0.35], i: 0.65 },
      { x: sx(5.6, 5.2), y: sy(5.6, 5.2) - 16, r: 30, c: [1.1, 0.8, 0.4], i: 0.6 },
      { x: sx(7.9, 5.2), y: sy(7.9, 5.2) - 16, r: 30, c: [1.1, 0.8, 0.4], i: 0.6 },
      { x: 268, y: 30, r: 150, c: [0.5, 0.6, 1.0], i: 0.3 },
      { x: sx(10.4, 2.1), y: sy(10.4, 2.1, 17), r: 24, c: [0.5, 1.0, 1.0], i: 0.5 },
    ];
    const tt = (frame % PERIOD) / PERIOD;
    if (tt > 0.5 && tt < 0.98) {
      const s = (tt - 0.5) / 0.48; const u = 9.6 - s * 6;
      L.push({ x: sx(u, 3.6), y: sy(u, 3.6, 14) - Math.round(Math.sin(s * Math.PI) * 24), r: 28, c: [1.2, 0.6, 0.25], i: 0.7 });
    }
    return L;
  };

  const AMBIENT = [0.42, 0.45, 0.6];
  const compose = () => {
    const L = lights();
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = y * W + x, i3 = i * 3;
      let r = base[i3], g = base[i3 + 1], b = base[i3 + 2];
      if (emit[i]) {
        bloomA[i3] = r; bloomA[i3 + 1] = g; bloomA[i3 + 2] = b;
      } else {
        bloomA[i3] = bloomA[i3 + 1] = bloomA[i3 + 2] = 0;
        let lr = AMBIENT[0], lg = AMBIENT[1], lb = AMBIENT[2];
        for (const l of L) {
          const dx = x - l.x, dy = (y - l.y) * 1.15;
          const d = Math.sqrt(dx * dx + dy * dy);
          if (d >= l.r) continue;
          const f = (1 - d / l.r); const k = f * f * l.i;
          lr += l.c[0] * k; lg += l.c[1] * k; lb += l.c[2] * k;
        }
        // quantise the light into steps with an ordered dither, so shading reads as bands of pixels
        const dth = (BAYER[(x & 3) + (y & 3) * 4] / 16 - 0.5) / 8;
        const q = (v) => Math.round((v + dth) * 8) / 8;
        r *= q(lr); g *= q(lg); b *= q(lb);
      }
      out[i * 4] = r; out[i * 4 + 1] = g; out[i * 4 + 2] = b; out[i * 4 + 3] = 255;
    }
    // bloom: a separable box blur of the emissive pixels, added back softly
    const R = 5;
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let r = 0, g = 0, b = 0, n = 0;
        for (let k = -R; k <= R; k++) { const xx = x + k; if (xx < 0 || xx >= W) continue; const j = (y * W + xx) * 3; r += bloomA[j]; g += bloomA[j + 1]; b += bloomA[j + 2]; n++; }
        const j = (y * W + x) * 3; bloomB[j] = r / n; bloomB[j + 1] = g / n; bloomB[j + 2] = b / n;
      }
    }
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let r = 0, g = 0, b = 0, n = 0;
        for (let k = -R; k <= R; k++) { const yy = y + k; if (yy < 0 || yy >= H) continue; const j = (yy * W + x) * 3; r += bloomB[j]; g += bloomB[j + 1]; b += bloomB[j + 2]; n++; }
        const i = y * W + x;
        const k = emit[i] ? 0.18 : 0.42;
        out[i * 4] = Math.min(255, out[i * 4] + (r / n) * k);
        out[i * 4 + 1] = Math.min(255, out[i * 4 + 1] + (g / n) * k);
        out[i * 4 + 2] = Math.min(255, out[i * 4 + 2] + (b / n) * k);
      }
    }
    ctx.putImageData(image, 0, 0);
  };

  // Frame ------------------------------------------------------------------
  let frame = 60;
  const draw = () => {
    sky();
    island();
    screeningRoom();
    workshop();
    traffic();
    compose();
  };

  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  let running = false, raf = 0, last = 0;
  const tick = (now) => {
    if (!running) return;
    if (now - last >= 1000 / 24) { last = now; frame++; draw(); }
    raf = requestAnimationFrame(tick);
  };
  const start = () => { if (running || reduced.matches) return; running = true; raf = requestAnimationFrame(tick); };
  const stop = () => { running = false; cancelAnimationFrame(raf); };

  draw(); // one still frame, always
  if ("IntersectionObserver" in window) {
    new IntersectionObserver((entries) => { entries[0].isIntersecting && !document.hidden ? start() : stop(); }, { threshold: 0.1 }).observe(canvas);
  } else start();
  document.addEventListener("visibilitychange", () => (document.hidden ? stop() : start()));
  reduced.addEventListener?.("change", () => (reduced.matches ? stop() : start()));

  // The same sprites, drawn big into the page's small canvases -------------
  const paintSprite = (target, layers, scale, pad) => {
    const pc = target.getContext("2d");
    let w = 0, h = 0;
    for (const L of layers) { w = Math.max(w, L.dx + L.rows[0].length); h = Math.max(h, L.dy + L.rows.length); }
    target.width = (w + pad * 2) * scale; target.height = (h + pad * 2) * scale;
    for (const L of layers) L.rows.forEach((row, j) => [...row].forEach((ch, i) => {
      if (ch === "." || !SP[ch]) return;
      const c = SP[ch];
      pc.fillStyle = `rgb(${c[0]},${c[1]},${c[2]})`;
      pc.fillRect((L.dx + i + pad) * scale, (L.dy + j + pad) * scale, scale, scale);
    }));
  };
  const portrait = document.getElementById("portrait");
  if (portrait) paintSprite(portrait, [{ rows: CAT_SIT, dx: 2, dy: 0 }, { rows: CAT_PAW, dx: 0, dy: 7 }], 9, 0);
  const SPRITES = {
    "cat-sit": [{ rows: CAT_SIT, dx: 2, dy: 0 }, { rows: CAT_PAW, dx: 0, dy: 7 }],
    "cat-walk": [{ rows: CAT_WALK[0], dx: 0, dy: 2 }, { rows: SATCHEL, dx: 3, dy: 5 }],
    "bot": [{ rows: BOT, dx: 0, dy: 0 }],
    "envelope": [{ rows: ["WWWWWWWWW", "WoWWWWWoW", "WWoWWWoWW", "WWWoWoWWW", "WWWWoWWWW", "WWWWWWWWW", "cWWWWWWWc", ".ccccccc."], dx: 0, dy: 1 }],
    "note": [{ rows: NOTE, dx: 0, dy: 0 }],
  };
  document.querySelectorAll("canvas[data-sprite]").forEach((c) => {
    const layers = SPRITES[c.dataset.sprite];
    if (layers) paintSprite(c, layers, 6, 3);
  });
})();
