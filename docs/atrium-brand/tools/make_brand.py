"""Generate atrium logo SVGs with outlined Open Sans Bold text.
usage: make_brand.py <OpenSans variable ttf> <out dir>"""
import sys, os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen

font = instantiateVariableFont(TTFont(sys.argv[1]), {"wght": 700, "wdth": 100})
OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
gs = font.getGlyphSet(); cmap = font.getBestCmap(); hmtx = font["hmtx"]; UPM = font["head"].unitsPerEm

def gname(ch): return cmap[ord(ch)]
def bounds(name):
    bp = BoundsPen(gs); gs[name].draw(bp); return bp.bounds

# i-dot: the contour of "i" that lies above the dotless stem
rec = RecordingPen(); gs[gname("i")].draw(rec)
contours, cur = [], []
for op, args in rec.value:
    cur.append((op, args))
    if op in ("closePath", "endPath"): contours.append(cur); cur = []
stem = bounds(gname("ı"))
dot = None
for c in contours:
    bp = BoundsPen(gs); r = RecordingPen(); r.value = c; r.replay(bp)
    if bp.bounds and bp.bounds[1] > stem[3]: dot = bp.bounds
assert dot, "no dot contour found"
STEM_W = stem[2] - stem[0]; STEM_CX = (stem[0] + stem[2]) / 2; DOT_CY = (dot[1] + dot[3]) / 2

ORANGE = "#f29400"
def text_paths(s, size, track_em, x0, base):
    """outlined text; returns (svg path d, x of each glyph origin, bbox)"""
    k = size / UPM; x = x0; ds = []; xs = []; bb = [1e9, 1e9, -1e9, -1e9]
    for ch in s:
        n = gname(ch); xs.append(x)
        sp = SVGPathPen(gs, ntos=lambda v: ("%.2f" % v).rstrip("0").rstrip("."))
        gs[n].draw(TransformPen(sp, (k, 0, 0, -k, x, base)))
        ds.append(sp.getCommands())
        b = bounds(n)
        if b:
            bb = [min(bb[0], x + b[0]*k), min(bb[1], base - b[3]*k), max(bb[2], x + b[2]*k), max(bb[3], base - b[1]*k)]
        x += hmtx[n][0] * k + track_em * size
    return " ".join(ds), xs, bb

def wordmark(size, x0, base):
    s = "atrıum"; d, xs, bb = text_paths(s, size, -0.01, x0, base)
    k = size / UPM; side = STEM_W * k
    cx = xs[3] + STEM_CX * k; cy = base - DOT_CY * k
    sq = (cx - side/2, cy - side/2, side)
    bb[1] = min(bb[1], sq[1])
    return d, sq, bb

ROOMS = [(0,0,31,15),(33,0,15,31),(17,33,31,15),(0,17,15,31)]
def mark(x, y, h, ink, court):
    k = h / 48
    r = "".join(f'<rect x="{x+a*k:.2f}" y="{y+b*k:.2f}" width="{w*k:.2f}" height="{hh*k:.2f}" rx="{k:.2f}" fill="{ink}"/>' for a,b,w,hh in ROOMS)
    return r + f'<rect x="{x+17*k:.2f}" y="{y+17*k:.2f}" width="{14*k:.2f}" height="{14*k:.2f}" rx="{k:.2f}" fill="{court}"/>'

def svg(w, h, body, title, extra=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.2f} {h:.2f}" width="{w:.0f}" height="{h:.0f}" role="img">'
            f'<title>{title}</title>{extra}{body}</svg>\n')

TONES = {("navy",""): "#1b2438", ("navy","-dark"): "#e6eaf2", ("grey",""): "#767a7d", ("grey","-dark"): "#efe9df"}
F = 54.0  # wordmark size; everything scales from it

def write(name, content):
    open(os.path.join(OUT, name), "w").write(content); print(name, len(content), "bytes")

for (tone, mode), ink in TONES.items():
    write(f"atrium-mark-{tone}{mode}.svg", svg(48, 48, mark(0, 0, 48, ink, ORANGE), "atrium"))
    # primary lockup: mark from baseline up to the top of the court-dot
    base = 100.0
    d, sq, bb = wordmark(F, 0, base)
    H = base - sq[1]; G = 0.26 * F
    d, sq, bb = wordmark(F, H + G, base)
    pad = 1
    top = min(bb[1], base - H) - pad; bottom = max(bb[3], base) + pad; right = bb[2] + pad
    body = f'<g transform="translate({pad:.2f} {-top:.2f})">' + mark(0, base - H, H, ink, ORANGE) + f'<path d="{d}" fill="{ink}"/>' + f'<rect x="{sq[0]:.2f}" y="{sq[1]:.2f}" width="{sq[2]:.2f}" height="{sq[2]:.2f}" fill="{ORANGE}"/></g>'
    write(f"atrium-lockup-{tone}{mode}.svg", svg(right + pad, bottom - top, body, "atrium"))
    # alternative: "iSAQB" above the wordmark
    f2 = 0.31 * F
    d, sq, bb = wordmark(F, 0, base)
    org_base = sq[1] - 0.12 * F
    od, oxs, obb = text_paths("iSAQB", f2, 0.09, 0, org_base)
    H2 = base - obb[1]
    x_text = H2 + G
    d, sq, bb = wordmark(F, x_text, base)
    a_xmin = bounds(gname("a"))[0] * F / UPM; i_xmin = bounds(gname("i"))[0] * f2 / UPM
    od, oxs, obb = text_paths("iSAQB", f2, 0.09, x_text + a_xmin - i_xmin, org_base)
    top = min(obb[1], base - H2) - pad; bottom = max(bb[3], base) + pad; right = max(bb[2], obb[2]) + pad
    body = (f'<g transform="translate({pad:.2f} {-top:.2f})">' + mark(0, base - H2, H2, ink, ORANGE)
            + f'<path d="{od}" fill="{ink}"/><path d="{d}" fill="{ink}"/>'
            + f'<rect x="{sq[0]:.2f}" y="{sq[1]:.2f}" width="{sq[2]:.2f}" height="{sq[2]:.2f}" fill="{ORANGE}"/></g>')
    write(f"atrium-isaqb-lockup-{tone}{mode}.svg", svg(right + pad, bottom - top, body, "iSAQB atrium"))

write("atrium-mark-on-orange.svg", svg(64, 64, '<rect width="64" height="64" fill="#f29400"/>' + mark(8, 8, 48, "#1b2438", "#fdefd9"), "atrium"))
fav_style = '<style>.r{fill:#1b2438}@media (prefers-color-scheme: dark){.r{fill:#e6eaf2}}</style>'
fav = "".join(f'<rect class="r" x="{a}" y="{b}" width="{w}" height="{h}" rx="1"/>' for a,b,w,h in ROOMS) + f'<rect x="17" y="17" width="14" height="14" rx="1" fill="{ORANGE}"/>'
write("favicon.svg", svg(48, 48, fav, "atrium", fav_style))
