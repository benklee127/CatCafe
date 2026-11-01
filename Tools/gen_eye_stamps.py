# Generates every pixel eye stamp (all shapes x buckets x expressions) from the
# open-eye silhouettes in Tools/eye_silhouettes.txt and rewrites the EYES table
# in Scripts/prototype3d/CatPixelFace.gd.
#   python Tools/gen_eye_stamps.py            write CatPixelFace.gd
#   python Tools/gen_eye_stamps.py --preview  print every stamp side by side
# Then check: godot --path . --script res://Tools/render_cat_seeds.gd -- out.png pixel faces
#
# The silhouettes give only the outline ("#") and the inside; everything else
# is built here from SPEC (the per-shape design picked on the eye option
# sheets): light eye line (no heavy lid; the lower half of the outline in the
# dark-iris tone), pupil size, iris tones, glints. Every pupil keeps >= 1px of
# iris / glint between it and the eye line on the left, right and below (the
# top may touch the lid); the compact XS stamps have no room for that ring and
# get a centre pupil. Expressions derive from the open eye (pupil scale PK,
# lid cuts CUTS, closed / happy arcs).
#
# GROW shapes (big, big_slit) are drawn 1px larger than their silhouette. Each
# bucket also gets the alternates "<bucket>-t" (+1 tall only), "-w" (+1 wide
# only) and "-0" (silhouette size); Cat2D tries them in that order before the
# next smaller bucket (CatPixelFace.stamp_chain), so the biggest eye that keeps
# the spacing rules is used.
#
# XXS (tiny last-resort stamps, no outline) keep the legacy layered build
# (legacy_grid).
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(ROOT, 'Scripts', 'prototype3d', 'CatPixelFace.gd')
SIL = os.path.join(ROOT, 'Tools', 'eye_silhouettes.txt')
BUCKETS = ['S', 'M', 'L', 'XS', 'XXS']
SMALL = ('S', 'XS', 'XXS')
SHAPES = ['round', 'big', 'almond', 'slit', 'big_slit', 'gentle', 'mischievous', 'wide']
EXPR = ['open', 'stressed', 'sleepy', 'closed', 'happy', 'angry', 'worried', 'sad', 'surprised', 'smug']
LINE = set('#L')
ALT_SUFFIX = ['-t', '-w', '-0']

# Per-shape design. frac / hfrac: pupil width / height as a fraction of the
# iris width / the rows that can hold pupil; glint: one | big (2x2) | two
# (main + small lower-left); iris3: strong 3-tone iris (light lower crescent);
# slit: slit width (capped so the ring stays); src: silhouette to use;
# grow: draw 1px larger (with -t / -w / -0 fallbacks).
BASE = dict(frac=0.68, hfrac=0.9, glint='one', iris3=False, slit=2, src=None, grow=False, kind='eye')
SPEC = {
    'round': dict(BASE, iris3=True, glint='two'),
    'big': dict(BASE, frac=0.84, hfrac=1.0, glint='big', grow=True),
    'almond': dict(BASE, iris3=True, glint='two'),
    'slit': dict(BASE, iris3=True, glint='two', kind='slit'),
    'big_slit': dict(BASE, slit=3, src='slit', grow=True, kind='slit'),
    'gentle': dict(BASE, iris3=True, glint='two'),
    'mischievous': dict(BASE, iris3=True, glint='two'),
    'wide': dict(BASE, iris3=True, glint='two'),
}
# per-expression pupil scale
PK = {'open': 1.0, 'stressed': 0.62, 'surprised': 0.42, 'worried': 0.8, 'sad': 0.95,
      'angry': 0.8, 'smug': 1.0, 'sleepy': 1.0}
# expressions that keep the second (lower) glint
TWO_GLINT_EXPR = ('open', 'sad', 'smug', 'worried')
SMALL_GLINT_EXPR = ('surprised', 'stressed', 'angry')
# legacy XXS pupil width/height fraction, lift
PUPIL = {
    'round': (0.68, 0.82, 0.08), 'big': (0.76, 0.86, 0.08), 'almond': (0.62, 0.9, 0.0),
    'slit': (0.0, 0.0, 0.0), 'big_slit': (0.0, 0.0, 0.0), 'gentle': (0.68, 0.85, 0.0),
    'mischievous': (0.55, 0.9, 0.0), 'wide': (0.52, 0.9, 0.0),
}


def load():
    data = {}
    cur = None
    for line in open(SIL, encoding='utf-8'):
        line = line.strip()
        if not line or line.startswith('# ') or line == '#':
            continue
        if line.startswith('=='):
            _, b, s = line.split()
            cur = data.setdefault(b, {}).setdefault(s, [])
            continue
        cur.append(line)
    return data


def grow(rows, tall=True, wide=True):
    """Duplicate the middle row / column (keeps the outline)."""
    rows = list(rows)
    if tall:
        m = len(rows) // 2
        rows = rows[:m] + [rows[m]] + rows[m:]
    if wide:
        m = len(rows[0]) // 2
        rows = [r[:m] + r[m] + r[m:] for r in rows]
    return rows


def interior_of(rows):
    return {(r, c) for r, row in enumerate(rows) for c, ch in enumerate(row) if ch not in '.#'}


def ellipse_cells(cells, cx, cy, rx, ry):
    out = set()
    for (r, c) in cells:
        dx = (c + 0.5 - cx) / max(rx, 0.01)
        dy = (r + 0.5 - cy) / max(ry, 0.01)
        if dx * dx + dy * dy <= 1.0:
            out.add((r, c))
    return out


def eye_grid(bucket, shape, sil, expr):
    """Open-style eye (light line) with the expression's pupil / glints."""
    o = SPEC[shape]
    H, W = len(sil), len(sil[0])
    g = [['.' if ch == '.' else '#' for ch in row] for row in sil]
    I0 = interior_of(sil)
    if not I0:
        return g
    lid = set()
    for c in range(W):
        col = [r for r in range(H) if sil[r][c] != '.']
        if col:
            lid.add((col[0], c))
    I = I0 - lid
    rt, rb = min(r for r, _ in I), max(r for r, _ in I)
    cl, cr = min(c for _, c in I0), max(c for _, c in I0)
    ih, iw = rb - rt + 1, cr - cl + 1
    cx = (cl + cr + 1) / 2.0
    # cells that can hold pupil: iris left, right and below
    E = {(r, c) for (r, c) in I if (r, c - 1) in I and (r, c + 1) in I and (r + 1, c) in I}
    for (r, c) in I:
        fr = (r - rt) / max(1, ih - 1)
        row_cs = [cc for rr, cc in I if rr == r]
        side = c == min(row_cs) or c == max(row_cs)
        if o['iris3']:
            ch = 'l' if (r == rb or (fr >= 0.5 and side) or (ih >= 6 and fr > 0.72)) else 'd' if fr < 0.34 else 'o'
        else:
            ch = 'l' if (r == rb or (ih >= 6 and fr > 0.78)) else 'd' if fr < 0.3 else 'o'
        g[r][c] = ch
    if not E:
        # compact stamps: no room for a ring, centre pupil
        cy = (rt + rb + 1) / 2.0
        E = {min(I, key=lambda p: (p[0] + 0.5 - cy) ** 2 + (p[1] + 0.5 - cx) ** 2)}
        if iw >= 2:
            E |= {p for p in I if p[0] == next(iter(E))[0] and abs(p[1] + 0.5 - cx) <= 1.0}
    er = sorted({r for r, _ in E})
    ew_max = max(len([c for rr, c in E if rr == r]) for r in er)
    k = PK.get(expr, 1.0)
    glint = o['glint']
    if expr in SMALL_GLINT_EXPR:
        glint = 'single'
    elif glint == 'two' and expr not in TWO_GLINT_EXPR:
        glint = 'one'
    glints = []
    if o['kind'] == 'slit':
        sw = min(o['slit'], max(1, iw - 2))
        lo, hi = rt, (rb - 1 if ih >= 3 else rb)
        if expr in ('stressed', 'surprised'):
            sw = 1
            if hi - lo >= 3:
                lo, hi = lo + 1, hi - 1
        c0 = int(round(cx - sw / 2.0))
        pupil = {(r, c) for (r, c) in I if c0 <= c < c0 + sw and lo <= r <= hi
                 and (r, c - 1) in I and (r, c + 1) in I and (r + 1, c) in I}
        if not pupil:
            pupil = set(E)
        if sw == 3 and len({r for r, _ in pupil}) >= 3:
            prs = [r for r, _ in pupil]
            for r in (min(prs), max(prs)):
                pupil.discard((r, c0))
                pupil.discard((r, c0 + 2))
        top = min(r for r, _ in pupil)
        right = max(c for r, c in pupil if r == top)
        if (top, right + 1) in I:
            glints.append((top, right + 1))
        if glint == 'two':
            bot = max(r for r, _ in pupil)
            left = min(c for r, c in pupil if r == bot)
            if (bot, left - 1) in I:
                glints.append((bot, left - 1))
    else:
        frac, hfrac = o['frac'] * k, o['hfrac'] * k
        pw = max(1, min(ew_max, int(round(frac * iw))))
        if (iw - pw) % 2 and pw + 1 <= ew_max and frac > 0.75:
            pw += 1
        elif (iw - pw) % 2 and pw > 1:
            pw -= 1 if frac <= 0.75 else 0
        eh = er[-1] - er[0] + 1
        ph = max(1, min(eh, int(round(hfrac * eh + 0.01))))
        top = er[0]
        cy = top + ph / 2.0
        if k < 1.0:
            # smaller pupil: centred in the pupil area
            cy = (er[0] + er[-1] + 1) / 2.0
        pad = 0.45 if frac > 0.75 else 0.3
        pupil = ellipse_cells(E, cx, cy, pw / 2.0 + pad, ph / 2.0 + pad)
        if not pupil:
            pupil = {min(E, key=lambda p: (p[0] + 0.5 - cy) ** 2 + (p[1] + 0.5 - cx) ** 2)}
        pr = sorted({r for r, _ in pupil})
        pc = sorted({c for _, c in pupil})
        ptop = pr[0]
        right = max(c for r, c in pupil if r <= ptop + 1)
        quad = [(ptop, right), (ptop, right - 1), (ptop + 1, right), (ptop + 1, right - 1)]
        if glint in ('big', 'two') and len(pr) >= 3 and len(pc) >= 3:
            gl = quad if len(pupil) >= 10 else quad[:2]
        elif glint == 'one' and bucket == 'L' and len(pr) >= 3 and len(pc) >= 3:
            gl = quad
        elif glint == 'one' and bucket == 'M' and len(pr) >= 3 and len(pc) >= 3:
            gl = [(ptop, right), (ptop + 1, right)]
        else:
            gl = [(ptop, right)]
        glints = [p for p in gl if p in pupil]
        if len(pupil) <= 6:
            # tiny pupil: keep it dark, glint in the iris above / beside it
            for p in ((ptop - 1, right), (ptop, right + 1)):
                if p in I:
                    glints = [p]
                    break
        if glint == 'two' and len(pr) >= 3 and len(pc) >= 2 and len(pupil) >= 6:
            bot = pr[-1]
            bl = (bot, min(c for r, c in pupil if r == bot))
            if bl not in glints:
                glints.append(bl)
    for (r, c) in pupil:
        g[r][c] = 'p'
    if expr != 'sleepy':
        for (r, c) in glints:
            g[r][c] = 'w'
    for (r, c) in lid:
        g[r][c] = 'L'
    # light line: lower half of the outline in the dark-iris tone
    midr = (min(r for r in range(H) for c in range(W) if g[r][c] != '.') + H - 1) / 2.0
    for r in range(H):
        for c in range(W):
            if g[r][c] in LINE and r > midr:
                g[r][c] = 'd'
    return g


def legacy_grid(bucket, shape, rows, expr):
    """Pre-v5 layered eye; used for the tiny XXS stamps only."""
    kind = SPEC[shape]['kind']
    H, W = len(rows), len(rows[0])
    g = [['.' if ch == '.' else '#' for ch in row] for row in rows]
    I = interior_of(rows)
    if not I:
        return g
    rs = [r for r, _ in I]
    cs = [c for _, c in I]
    rt, rb = min(rs), max(rs)
    cl, cr = min(cs), max(cs)
    iw = cr - cl + 1
    lid_cells = set()
    for c in range(W):
        col = [r for r in range(H) if rows[r][c] != '.']
        if not col:
            continue
        lid_cells.add((col[0], c))
        ins = [r for r in col if (r, c) in I]
        if bucket not in SMALL and len(ins) >= 5:
            lid_cells.add((ins[0], c))
    I = {p for p in I if p not in lid_cells}
    rs = [r for r, _ in I]
    rt = min(rs)
    ih = rb - rt + 1
    for (r, c) in I:
        fr = (r - rt) / max(1, ih - 1)
        row_cs = [cc for rr, cc in I if rr == r]
        side = c == min(row_cs) or c == max(row_cs)
        if r == rb or (ih >= 6 and fr > 0.78):
            ch = 'l'
        elif fr < 0.3 or (side and iw >= 5 and fr < 0.65):
            ch = 'd'
        else:
            ch = 'o'
        g[r][c] = ch
    k = PK.get(expr, 1.0)
    cx = (cl + cr + 1) / 2.0
    pupil = set()
    if kind == 'slit':
        calm = expr in ('smug', 'sleepy', 'sad', 'open')
        sw = 1
        if calm and bucket not in SMALL:
            sw = 2 if iw % 2 == 0 else 3 if bucket == 'L' and expr != 'open' else 1
        if expr == 'surprised' or expr == 'stressed':
            sw = 1
        c0 = int(round(cx - sw / 2.0))
        lo = rt
        hi = rb - 1 if ih >= 4 else rb
        if expr in ('stressed', 'surprised'):
            lo += 1
            hi -= 1
        for (r, c) in I:
            if c0 <= c < c0 + sw and lo <= r <= hi:
                pupil.add((r, c))
        if sw == 3:
            for r in (lo, hi):
                pupil.discard((r, c0))
                pupil.discard((r, c0 + 2))
    else:
        pw, ph, lift = PUPIL[shape]
        cy = (rt + rb + 1) / 2.0 - lift * ih - 0.25
        rx = max(0.55, pw * iw / 2.0 * k)
        ry = max(0.55, ph * ih / 2.0 * k)
        pupil = ellipse_cells(I, cx, cy, rx, ry)
        if ih >= 3:
            pupil = {(r, c) for (r, c) in pupil if r != rb}
        if not pupil:
            best = min(I, key=lambda p: (p[0] + 0.5 - cy) ** 2 + (p[1] + 0.5 - cx) ** 2)
            pupil = {best}
    for (r, c) in pupil:
        g[r][c] = 'p'
    if expr not in ('sleepy',) and pupil:
        pr = [r for r, _ in pupil]
        pc = [c for _, c in pupil]
        top = min(pr)
        right = max(c for r, c in pupil if r <= top + 1)
        big = (bucket not in SMALL and len(set(pc)) >= 3 and len(set(pr)) >= 3 and expr not in ('surprised', 'stressed', 'angry'))
        if kind == 'slit':
            gl = [(top, right + 1)] if (top, right + 1) in I else []
        elif big:
            gl = [(top, right), (top, right - 1), (top + 1, right), (top + 1, right - 1)]
        else:
            gl = [(top, right)]
        for p in gl:
            if p in I:
                g[p[0]][p[1]] = 'w'
    for (r, c) in lid_cells:
        g[r][c] = 'L'
    return g


def lid_cut(g, I, f, lid='L'):
    """f(t) -> fraction of eye height cut from the top at column position t
    (0 = inner/left, 1 = outer/right)."""
    H, W = len(g), len(g[0])
    cols = [c for c in range(W) if any(g[r][c] != '.' for r in range(H))]
    if not cols:
        return g
    c0, c1 = min(cols), max(cols)
    rows_all = [r for r in range(H) for c in range(W) if g[r][c] != '.']
    top_all, bot_all = min(rows_all), max(rows_all)
    eh = bot_all - top_all + 1
    for c in cols:
        t = (c - c0) / max(1, c1 - c0)
        col = [r for r in range(H) if g[r][c] != '.']
        ct, cb = col[0], col[-1]
        cut = int(round(top_all + f(t) * eh))
        cut = max(ct, min(cut, cb))
        for r in range(ct, cut):
            g[r][c] = '.'
        g[cut][c] = lid
    return g


def arc(H, W, closed):
    g = [['.'] * W for _ in range(H)]
    three = W >= 7 and H >= 5
    n = 3 if three else 2
    if closed:
        a = min(H - n, max(0, int(round(H * 0.55))))
        g[a][0] = g[a][W - 1] = '#'
        if three:
            g[a + 1][1] = g[a + 1][W - 2] = '#'
            for c in range(2, W - 2):
                g[a + 2][c] = '#'
        else:
            for c in range(1, W - 1):
                g[a + 1][c] = '#'
    else:
        a = max(0, min(H - n, int(round(H * 0.22))))
        if three:
            for c in range(2, W - 2):
                g[a][c] = '#'
            g[a + 1][1] = g[a + 1][W - 2] = '#'
            g[a + 2][0] = g[a + 2][W - 1] = '#'
        else:
            for c in range(1, W - 1):
                g[a][c] = '#'
            g[a + 1][0] = g[a + 1][W - 1] = '#'
    return g


CUTS = {
    'sleepy': lambda t: 0.55,
    'smug': lambda t: 0.4,
    'angry': lambda t: 0.62 - 0.42 * t,
    'worried': lambda t: 0.05 + 0.3 * t,
    'sad': lambda t: 0.1 + 0.42 * t,
}


def make(bucket, shape, rows):
    H, W = len(rows), len(rows[0])
    I = interior_of(rows)
    out = {}
    for e in EXPR:
        if e == 'closed':
            g = arc(H, W, True)
        elif e == 'happy':
            g = arc(H, W, False)
        else:
            g = legacy_grid(bucket, shape, rows, e) if bucket == 'XXS' else eye_grid(bucket, shape, rows, e)
            if e in CUTS:
                g = lid_cut(g, I, CUTS[e])
                if e == 'sleepy':
                    g = [[('.' if ch == 'w' else ch) for ch in row] for row in g]
        out[e] = [''.join(r) for r in g]
    return out


def build():
    data = load()
    eyes = {b: {} for b in BUCKETS}
    alts = {}
    for s in SHAPES:
        spec = SPEC[s]
        src = spec['src'] or s
        for b in BUCKETS:
            sil = data[b][src]
            if spec['grow'] and b != 'XXS':
                eyes[b][s] = make(b, s, grow(sil))
                for suf, rows in zip(ALT_SUFFIX, [grow(sil, wide=False), grow(sil, tall=False), sil]):
                    alts.setdefault(b + suf, {})[s] = make(b, s, rows)
            else:
                eyes[b][s] = make(b, s, sil)
    for b in BUCKETS:
        for suf in ALT_SUFFIX:
            if b + suf in alts:
                eyes[b + suf] = alts[b + suf]
    return eyes


def main():
    eyes = build()
    if '--preview' in sys.argv:
        for b in eyes:
            for s in eyes[b]:
                print('==', b, s)
                st = eyes[b][s]
                for i in range(len(st['open'])):
                    print('   '.join(st[e][i] for e in EXPR))
        return
    out = ['const EYES: Dictionary = {']
    for b in eyes:
        out.append('\t"%s": {' % b)
        for s in eyes[b]:
            out.append('\t\t"%s": {' % s)
            for e in EXPR:
                out.append('\t\t\t"%s": [' % e)
                for r in eyes[b][s][e]:
                    out.append('\t\t\t\t"%s",' % r)
                out.append('\t\t\t],')
            out.append('\t\t},')
        out.append('\t},')
    out.append('}\n\n')
    src = open(P, encoding='utf-8').read()
    a = src.index('const EYES: Dictionary = {')
    z = src.index('# Nose + mouth stamps')
    src = src[:a] + '\n'.join(out) + src[z:]
    open(P, 'w', encoding='utf-8', newline='\n').write(src)
    print('written')


if __name__ == '__main__':
    main()
