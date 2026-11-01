# spark-shell wallpaper motion: orbit (MIT, the repository's license)
"""The moving orbit: a ringed planet in the flat style of the drawings.

python3 -I orbit.py OUT_DIR writes one loop of SVG frames, OUT_DIR/f0000.svg
and on, at 30 frames a second. The frames use the colors of orbit.svg's roles
line alone, so spark-shell draws each one in the palette in use as it draws
the still. Every motion has a period that divides the loop, so the last frame
runs back into the first. Python's standard library only.
"""
import math
import random
import sys

W, H = 1920, 1080
FPS = 30
T = 90.0                      # loop length, seconds
N = int(T * FPS)

BG, LINE, CUR, DARK = "#282a36", "#44475a", "#383a4a", "#21222c"
FG, COMMENT, PURPLE, PINK, CYAN = "#f8f8f2", "#6272a4", "#bd93f9", "#ff79c6", "#8be9fd"

TAU = 2 * math.pi
rnd = random.Random(174)

# stars: (layer, x, y, r, color, base opacity, twinkle depth, k, phase)
LAYERS = {0: 3.0, 1: 7.0, 2: 14.0}   # sway amplitude per layer, px
STARS = []
for layer, count, rr, op in ((0, 90, (0.7, 1.1), (0.22, 0.42)),
                             (1, 46, (1.0, 1.5), (0.32, 0.55)),
                             (2, 14, (1.5, 2.1), (0.50, 0.72))):
    for _ in range(count):
        x = rnd.uniform(-20, W + 20)
        y = rnd.uniform(34, H - 10)
        color = rnd.choices((PURPLE, PINK, FG, CYAN), weights=(5, 3, 3, 2))[0]
        depth = rnd.uniform(0.25, 0.6) if rnd.random() < 0.6 else 0.0
        STARS.append((layer, x, y, rnd.uniform(*rr), color, rnd.uniform(*op),
                      depth, rnd.randint(3, 12), rnd.uniform(0, TAU)))

PX, PY, PR = 1340.0, 500.0, 150.0     # the planet
TILT = -14.0                          # the axis and the ring plane, degrees
SQUASH = 0.22                         # the ring's b/a: how far we look down on it
RINGS = ((212, PURPLE, 0.55, 2.0), (236, COMMENT, 0.45, 7.0), (262, PURPLE, 0.30, 1.5))
MOON_A, MOON_R = 330.0, 9.0
METEOR = (54.0, 0.8, (380.0, 150.0), (760.0, 360.0), 150.0)   # start s, length s, from, to, tail


def sway(t, amp):
    return (amp * math.sin(TAU * t / T), 0.4 * amp * math.sin(2 * TAU * t / T + 0.7))


def f(v):
    return f"{v:.2f}"


def ring_arc(a, front):
    b = a * SQUASH
    # the front half is the lower one: we look down on the ring
    sweep = 0 if front else 1
    return f'M{f(-a)} 0 A{f(a)} {f(b)} 0 0 {sweep} {f(a)} 0'


def frame(i):
    t = i / FPS
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">',
           '<defs><clipPath id="disk"><circle cx="0" cy="0" r="%s"/></clipPath>' % f(PR),
           f'<linearGradient id="tail" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{FG}" stop-opacity="0"/>'
           f'<stop offset="1" stop-color="{FG}" stop-opacity="1"/></linearGradient></defs>',
           f'<rect width="{W}" height="{H}" fill="{BG}"/>']

    for layer, amp in LAYERS.items():
        dx, dy = sway(t, amp)
        out.append(f'<g transform="translate({f(dx)} {f(dy)})">')
        for (ly, x, y, r, color, op, depth, k, ph) in STARS:
            if ly != layer:
                continue
            o = op * (1 - depth + depth * (0.5 + 0.5 * math.sin(TAU * k * t / T + ph)))
            out.append(f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{color}" opacity="{o:.3f}"/>')
        out.append('</g>')

    # the meteor, once a loop
    m0, mlen, (x0, y0), (x1, y1), tail = METEOR
    if m0 <= t < m0 + mlen:
        u = (t - m0) / mlen
        hx, hy = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
        ang = math.degrees(math.atan2(y1 - y0, x1 - x0))
        o = math.sin(math.pi * u) ** 1.5
        out.append(f'<g transform="translate({f(hx)} {f(hy)}) rotate({f(ang)})" opacity="{o:.3f}">'
                   f'<rect x="{f(-tail)}" y="-0.8" width="{f(tail)}" height="1.6" rx="0.8" fill="url(#tail)"/>'
                   f'<circle cx="0" cy="0" r="1.6" fill="{FG}"/></g>')

    dx, dy = sway(t, 10.0)
    cx, cy = PX + dx, PY + dy
    th = TAU * t / T                       # the moon goes round once a loop
    mx, my = MOON_A * math.cos(th), MOON_A * SQUASH * math.sin(th)
    moon_front = math.sin(th) > 0
    moon = f'<circle cx="{f(mx)}" cy="{f(my)}" r="{f(MOON_R)}" fill="{FG}" opacity="0.92"/>' \
           f'<circle cx="{f(mx + 3.2)}" cy="{f(my + 2.4)}" r="{f(MOON_R - 0.6)}" fill="{BG}" opacity="0.55"/>'

    out.append(f'<g transform="translate({f(cx)} {f(cy)}) rotate({TILT})">')
    for a, color, op, w in RINGS:               # the back of the rings
        out.append(f'<path d="{ring_arc(a, False)}" fill="none" stroke="{color}" opacity="{op}" stroke-width="{w}"/>')
    if not moon_front:
        out.append(moon)

    # the planet: bands and storms turn with it, the night side stays
    out.append(f'<circle cx="0" cy="0" r="{f(PR)}" fill="{COMMENT}"/>')
    out.append('<g clip-path="url(#disk)">')
    for lat, h, color, op in ((-0.62, 26, LINE, 0.55), (-0.30, 14, PURPLE, 0.40), (0.05, 38, LINE, 0.35),
                              (0.36, 12, PINK, 0.28), (0.58, 22, CUR, 0.70)):
        y = -PR * math.sin(lat)
        out.append(f'<rect x="{f(-PR)}" y="{f(y - h / 2)}" width="{f(2 * PR)}" height="{h}" fill="{color}" opacity="{op}"/>')
    for lat, lon0, rx, ry, color, op in ((0.12, 0.0, 26, 9, PURPLE, 0.55), (-0.38, 2.4, 16, 6, PINK, 0.40),
                                         (0.42, 4.1, 12, 5, FG, 0.25)):
        lon = lon0 + TAU * t / T
        c = math.cos(lon)
        if c <= 0.02:
            continue
        sx = PR * math.cos(lat) * math.sin(lon)
        sy = -PR * math.sin(lat)
        out.append(f'<ellipse cx="{f(sx)}" cy="{f(sy)}" rx="{f(rx * c)}" ry="{ry}" fill="{color}" '
                   f'opacity="{op * c ** 0.6:.3f}"/>')
    out.append('</g>')
    out.append(f'<g transform="rotate({-TILT})" clip-path="url(#disk)">'
               f'<circle cx="{f(0.42 * PR)}" cy="{f(0.30 * PR)}" r="{f(PR)}" fill="{DARK}" opacity="0.72"/></g>')
    out.append(f'<circle cx="0" cy="0" r="{f(PR - 1)}" fill="none" stroke="{PURPLE}" opacity="0.28" stroke-width="2"/>')

    for a, color, op, w in RINGS:               # the front of the rings
        out.append(f'<path d="{ring_arc(a, True)}" fill="none" stroke="{color}" opacity="{op}" stroke-width="{w}"/>')
    if moon_front:
        out.append(moon)
    out.append('</g></svg>')
    return '\n'.join(out)


if __name__ == '__main__':
    out_dir = sys.argv[1]
    for i in range(N):
        with open(f'{out_dir}/f{i:04d}.svg', 'w') as fh:
            fh.write(frame(i))
