extends RefCounted

## Purr-fect Timing: procedural pixel-art helpers (palette, 5x7 pixel font, shapes).
## Everything is drawn with draw_rect / draw_circle / draw_polygon on integer coordinates
## inside the 320x180 play SubViewport (nearest filter), so no image imports are needed.
## No class_name on purpose: preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd").

const OUTLINE := Color("#4A3426")
const CREAM := Color("#FFF6EA")
const OAK := Color("#C9A27A")
const OAK_DARK := Color("#A87C55")
const SAGE := Color("#8FBF9F")
const SAGE_DARK := Color("#6E9E80")
const HONEY := Color("#E8B04B")
const HONEY_LIGHT := Color("#F5D48A")
const ALERT := Color("#E07A3F")  # overflow only
const WALL := Color("#F6E6D2")
const WALL_DOT := Color("#EED8BE")
const COFFEE := Color("#6B4A35")
const CREMA := Color("#B5814F")
const MILK := Color("#FFFDF7")
const FOAM := Color("#F3E3C9")
const MATCHA := Color("#9DBF6B")
const MATCHA_DARK := Color("#7FA352")
const DOUGH := Color("#F0D3A0")
const DOUGH_DARK := Color("#D9B47A")
const STEEL := Color("#D9DDE4")
const STEEL_DARK := Color("#AEB4BF")
const PINK := Color("#F2B5B0")
const SHADOW := Color(0.29, 0.2, 0.15, 0.18)

const GLYPH_W := 5
const GLYPH_H := 7
const ADVANCE := 6

# ============================================================== art style switch
## One switch for every draw helper (and the overlay chrome). "A" is today's art, untouched:
## every helper keeps its original code path when legacy() is true, so A renders byte-identical.
## B..F follow the shared minigame style options (same letters in every minigame).
##   outline_px      outer outline thickness of outlined shapes (grows outward, fill unchanged)
##   chunky          per-object simplification: 2px minimum features, merged 1px details,
##                   rounder corners, fewer tones (each object's draw code checks chunky())
##   rim_highlight   1px light rim on the top/left inside edge of filled shapes
##   cel_shade       2-tone fill: base + darker shade on the bottom/right
##   halo            1px cream sticker halo outside the outline (object-level, see PTGame FX group)
##   drop_shadow     1px offset cocoa contact shadow (object-level, see PTGame FX group)
##   panel_border_px ink outline around the window / pause card; buttons get border 2 + this - 1
##   font_weight     1 = bold pixel font for big text (scale >= 2) and bold UI font
##   ui_embolden     system-font embolden for the window chrome (0.6 ~ weight 700, shared rule)
##   text_ring       min outline ring (px) on every pixel-font label; 0 = only popups keep theirs
##   text_halo       E: 1px cream halo outside the text ring
##   text_shadow     F: 1px cocoa drop shadow under the text
## Shared text rule (same letters in every minigame): A today; B/C bold; D bold + 1px outline;
## E bold + outline + cream halo; F bold + 2px outline + shadow (1px outline below scale 2).
## Titles / descriptions are the shared cross-game wording (art_options/shared/style_table.json).
const STYLE_ORDER: Array[String] = ["A", "B", "C", "D", "E", "F"]
const STYLES: Dictionary = {
	"A": {"name": "Current (today)", "desc": "Exactly today's art, unchanged", "outline_px": 1, "chunky": false, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "panel_border_px": 0, "font_weight": 0, "ui_embolden": 0.0, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"B": {"name": "2px outline", "desc": "2px outer outline, same shapes", "outline_px": 2, "chunky": false, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "panel_border_px": 2, "font_weight": 1, "ui_embolden": 0.6, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"C": {"name": "2px + chunky shapes", "desc": "2px outline + chunky simplified shapes (2px min), fewer colours", "outline_px": 2, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": false, "panel_border_px": 2, "font_weight": 1, "ui_embolden": 0.6, "text_ring": 0, "text_halo": false, "text_shadow": false},
	"D": {"name": "Chunky + rim light + cel shade", "desc": "2px outline + chunky + 1px top/left rim light + 2-tone cel shade", "outline_px": 2, "chunky": true, "rim_highlight": true, "cel_shade": true, "halo": false, "drop_shadow": false, "panel_border_px": 2, "font_weight": 1, "ui_embolden": 0.6, "text_ring": 1, "text_halo": false, "text_shadow": false},
	"E": {"name": "Sticker: outline + cream halo", "desc": "Sticker: 2px outline + cream halo + chunky", "outline_px": 2, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": true, "drop_shadow": false, "panel_border_px": 2, "font_weight": 1, "ui_embolden": 0.6, "text_ring": 1, "text_halo": true, "text_shadow": false},
	"F": {"name": "3px outline + chunky + drop shadow", "desc": "Heavy: 3px outline + chunky + 1px cocoa drop shadow", "outline_px": 3, "chunky": true, "rim_highlight": false, "cel_shade": false, "halo": false, "drop_shadow": true, "panel_border_px": 3, "font_weight": 1, "ui_embolden": 0.6, "text_ring": 2, "text_halo": false, "text_shadow": true},
}
const HALO_COL := Color("#FFF6EA")
const DROP_COL := Color(0.169, 0.129, 0.161, 0.35)  # cocoa #2B2129 @ 35%

## Owner's pick (2026-10-26): F = 3px outline + chunky + drop shadow. A stays available for comparison.
const DEFAULT_STYLE: String = "F"

static var style: String = DEFAULT_STYLE
static var S: Dictionary = STYLES[DEFAULT_STYLE]
## True while a draw runs inside an E / F FX CanvasGroup: the group shader already adds the
## halo / drop shadow, so text skips its own copy.
static var fx_wrapped: bool = false


static func set_style(letter: String) -> void:
	var l: String = letter.strip_edges().to_upper()
	if not STYLES.has(l):
		l = "A"
	style = l
	S = STYLES[l]


static func legacy() -> bool:
	return style == "A"


## Outline thickness in px (1 for A).
static func ow() -> int:
	return int(S["outline_px"])


## Chrome border thickness (step strip, chips, card dividers): 2px B..E, 3px F, 0 for A.
static func chrome_px() -> int:
	return int(S["panel_border_px"])


static func chunky() -> bool:
	return bool(S["chunky"])


## Minimum line / detail width: 2px in chunky styles, else 1px.
static func lw() -> float:
	return 2.0 if chunky() else 1.0


static func shade_of(c: Color) -> Color:
	return Color(c.darkened(0.16), c.a)


static func rim_of(c: Color) -> Color:
	return Color(c.lightened(0.45), c.a)


static func _cel(outline: Color, fill: Color) -> bool:
	return bool(S["cel_shade"]) and fill.a > 0.99 and outline != fill


static func _rim(outline: Color, fill: Color) -> bool:
	return bool(S["rim_highlight"]) and fill.a > 0.99 and outline != fill

const GLYPHS: Dictionary = {
	"A": ["..#..", ".#.#.", "#...#", "#...#", "#####", "#...#", "#...#"],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
	"K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
	"N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
	"Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
	"X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
	"Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
	"Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
	"0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
	"1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
	"2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
	"3": ["####.", "....#", "....#", ".###.", "....#", "....#", "####."],
	"4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
	"5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
	"6": [".###.", "#....", "#....", "####.", "#...#", "#...#", ".###."],
	"7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
	"8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
	"9": [".###.", "#...#", "#...#", ".####", "....#", "....#", ".###."],
	"!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
	"?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	".": [".....", ".....", ".....", ".....", ".....", ".....", "..#.."],
	",": [".....", ".....", ".....", ".....", ".....", "..#..", ".#..."],
	"-": [".....", ".....", ".....", ".###.", ".....", ".....", "....."],
	"+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
	"$": ["..#..", ".####", "#.#..", ".###.", "..#.#", "####.", "..#.."],
	":": [".....", "..#..", ".....", ".....", ".....", "..#..", "....."],
	"/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
	"'": ["..#..", "..#..", ".....", ".....", ".....", ".....", "....."],
	"%": ["##..#", "##..#", "...#.", "..#..", ".#...", "#..##", "#..##"],
	"x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
	")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
	">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
	"<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
	"=": [".....", ".....", "#####", ".....", "#####", ".....", "....."],
}


static func text_width(s: String, scale: int = 1) -> int:
	if s.is_empty():
		return 0
	if legacy():
		return (s.length() * ADVANCE - 1) * scale
	return s.length() * _adv(scale) - scale


## Glyph advance: bold scale-1 text gets one extra px so bold glyphs never touch.
static func _adv(scale: int) -> int:
	if scale == 1 and _bold(1) > 0:
		return ADVANCE + 1
	return ADVANCE * scale


## Extra px added to the right of every glyph run (bold pixel font) for this scale.
static func _bold(scale: int) -> int:
	if legacy() or int(S["font_weight"]) <= 0:
		return 0
	return maxi(1, scale / 2)


## Pixel text. `shadow` draws a 1-scale outline-colored drop shadow for readability in A;
## in B..F it asks for a 1px outline ring, then the shared per-letter text rule applies.
static func text(ci: CanvasItem, pos: Vector2, s: String, col: Color, scale: int = 1, shadow: bool = false) -> void:
	var x: float = roundf(pos.x)
	var y: float = roundf(pos.y)
	if legacy():
		if shadow:
			_text_raw(ci, x + scale, y + scale, s, Color(OUTLINE, col.a), scale)
		_text_raw(ci, x, y, s, col, scale)
		return
	_styled_text(ci, x, y, s, col, scale, 1 if shadow else 0)


static func text_centered(ci: CanvasItem, center_x: float, y: float, s: String, col: Color, scale: int = 1, shadow: bool = false) -> void:
	text(ci, Vector2(roundf(center_x - text_width(s, scale) / 2.0), y), s, col, scale, shadow)


## Text with a full 1px outline ring (for stamps and popups over busy art).
static func text_outlined(ci: CanvasItem, center_x: float, y: float, s: String, col: Color, scale: int = 1) -> void:
	var x: float = roundf(center_x - text_width(s, scale) / 2.0)
	var oc := Color(OUTLINE, col.a)
	if not legacy():
		_styled_text(ci, x, y, s, col, scale, 1)
		return
	var offs: Array = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(1, 1)]
	if scale >= 2:
		offs = [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2), Vector2(2, 2), Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2)]
	for d in offs:
		_text_raw(ci, x + d.x, y + d.y, s, oc, scale)
	_text_raw(ci, x, y, s, col, scale)


## B..F text rule. base_ring: outline ring the call site always wants (popups / hints = 1).
## Dark / mid-tone labels get a cream ring instead of an ink one (an ink ring around ink or
## oak-dark body text is just a blob). Below scale 2 the ring is capped at 1px and E's halo is
## left off (F's 2px ring / a cream band would fill the 1px glyph gaps).
static func _styled_text(ci: CanvasItem, x: float, y: float, s: String, col: Color, scale: int, base_ring: int) -> void:
	var bold: int = _bold(scale)
	if col.a < 0.5:
		_text_raw(ci, x, y, s, col, scale, 0, bold)
		return
	var ring: int = maxi(base_ring, int(S["text_ring"]))
	if scale < 2:
		ring = mini(ring, 1)
	var light_ring: bool = col.get_luminance() < 0.6 and base_ring == 0
	var rc: Color = Color(CREAM, col.a) if light_ring else Color(OUTLINE, col.a)
	var halo: bool = bool(S["text_halo"]) and not fx_wrapped and ring > 0 and not light_ring and scale >= 2
	var outer: int = ring + (1 if halo else 0)
	if bool(S["text_shadow"]) and not fx_wrapped:
		_text_mask(ci, x + 1, y + 1, s, Color(DROP_COL, DROP_COL.a * col.a), scale, outer, bold)
	if halo:
		_text_raw(ci, x, y, s, Color(HALO_COL, col.a), scale, ring + 1, bold)
	if ring > 0:
		_text_raw(ci, x, y, s, rc, scale, ring, bold)
	_text_raw(ci, x, y, s, col, scale, 0, bold)


## Translucent footprint (each pixel drawn once, so overlapping runs never double the alpha).
static func _text_mask(ci: CanvasItem, x: float, y: float, s: String, col: Color, scale: int, grow: int, bold: int) -> void:
	var px: Dictionary = {}
	var cx: int = int(x)
	var adv: int = _adv(scale)
	for ch in s:
		var key: String = ch
		if not GLYPHS.has(key):
			key = ch.to_upper()
		var g: Array = GLYPHS.get(key, [])
		if not g.is_empty():
			for r in GLYPH_H:
				var row: String = g[r]
				for c in GLYPH_W:
					if row[c] == "#":
						var x0: int = cx + c * scale - grow
						var x1: int = cx + (c + 1) * scale + bold + grow
						var y0: int = int(y) + r * scale - grow
						var y1: int = int(y) + (r + 1) * scale + grow
						for yy in range(y0, y1):
							for xx in range(x0, x1):
								px[Vector2i(xx, yy)] = true
		cx += adv
	var rows: Dictionary = {}
	for p in px.keys():
		var pv: Vector2i = p
		if not rows.has(pv.y):
			rows[pv.y] = []
		(rows[pv.y] as Array).append(pv.x)
	for yy in rows.keys():
		var xs: Array = rows[yy]
		xs.sort()
		var i: int = 0
		while i < xs.size():
			var j: int = i
			while j + 1 < xs.size() and int(xs[j + 1]) == int(xs[j]) + 1:
				j += 1
			ci.draw_rect(Rect2(int(xs[i]), int(yy), int(xs[j]) - int(xs[i]) + 1, 1), col)
			i = j + 1


## grow: every glyph run rect grown by this many px (outline ring); bold: px added on the right.
static func _text_raw(ci: CanvasItem, x: float, y: float, s: String, col: Color, scale: int, grow: int = 0, bold: int = 0) -> void:
	var cx: float = x
	var adv: int = ADVANCE * scale if legacy() else _adv(scale)
	for ch in s:
		var key: String = ch
		if not GLYPHS.has(key):
			key = ch.to_upper()
		var g: Array = GLYPHS.get(key, [])
		if not g.is_empty():
			for r in GLYPH_H:
				var row: String = g[r]
				var c: int = 0
				while c < GLYPH_W:
					if row[c] == "#":
						# merge horizontal runs into one rect
						var run: int = 1
						while c + run < GLYPH_W and row[c + run] == "#":
							run += 1
						var rr := Rect2(cx + c * scale, y + r * scale, run * scale + bold, scale)
						if grow > 0:
							rr = rr.grow(grow)
						ci.draw_rect(rr, col)
						c += run
					else:
						c += 1
		cx += adv


## Filled rect with a 1px outline (B..F: outline_px thick, grown outward so the fill keeps its size).
static func box(ci: CanvasItem, r: Rect2, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_rect(r, outline)
		ci.draw_rect(r.grow(-1), fill)
		return
	ci.draw_rect(r.grow(ow() - 1), outline)
	var inner: Rect2 = r.grow(-1)
	ci.draw_rect(inner, fill)
	_rect_tones(ci, inner, fill, outline)


## Rect with the corner pixels knocked out (soft pixel corners). B..F: thicker outline,
## chunky styles also round the fill corners.
static func soft_box(ci: CanvasItem, r: Rect2, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_rect(Rect2(r.position.x + 1, r.position.y, r.size.x - 2, r.size.y), outline)
		ci.draw_rect(Rect2(r.position.x, r.position.y + 1, r.size.x, r.size.y - 2), outline)
		ci.draw_rect(Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, r.size.y - 2), fill)
		return
	var o: int = ow()
	var inner: Rect2 = r.grow(-1)
	var fr: int = 1 if chunky() and minf(inner.size.x, inner.size.y) >= 8.0 else 0
	rrect(ci, r.grow(o - 1), fr + o, outline)
	rrect(ci, inner, fr, fill)
	_rect_tones(ci, inner, fill, outline, fr)


## Chrome box (chips / strips): soft_box with an ink border of chrome_px (2px B..E, 3px F).
static func chrome_box(ci: CanvasItem, r: Rect2, fill: Color) -> void:
	var o: int = chrome_px()
	var inner: Rect2 = r.grow(-1)
	var fr: int = 1 if chunky() and minf(inner.size.x, inner.size.y) >= 8.0 else 0
	rrect(ci, r.grow(o - 1), fr + o, OUTLINE)
	rrect(ci, inner, fr, fill)
	_rect_tones(ci, inner, fill, OUTLINE, fr)


## Chrome divider line: an ink rule chrome_px thick.
static func divider(ci: CanvasItem, x: float, y: float, w: float) -> void:
	ci.draw_rect(Rect2(x, y, w, chrome_px()), OUTLINE)


## Pixel rounded rect: corner radius rad (0..4) built from horizontal spans.
static func rrect(ci: CanvasItem, r: Rect2, rad: int, col: Color) -> void:
	var insets: Array = [[], [1], [2, 1], [3, 1, 1], [4, 2, 1, 1]][clampi(rad, 0, 4)]
	var n: int = insets.size()
	if n == 0 or r.size.y < n * 2 + 1 or r.size.x < n * 2 + 1:
		ci.draw_rect(r, col)
		return
	ci.draw_rect(Rect2(r.position.x, r.position.y + n, r.size.x, r.size.y - n * 2), col)
	for i in n:
		var ins: float = float(insets[i])
		ci.draw_rect(Rect2(r.position.x + ins, r.position.y + i, r.size.x - ins * 2.0, 1), col)
		ci.draw_rect(Rect2(r.position.x + ins, r.end.y - 1 - i, r.size.x - ins * 2.0, 1), col)


## D: cel shade band (bottom/right) + rim highlight (top/left) inside a rect fill.
static func _rect_tones(ci: CanvasItem, inner: Rect2, fill: Color, outline: Color, rad: int = 0) -> void:
	if inner.size.x < 4 or inner.size.y < 4:
		return
	if _cel(outline, fill):
		# a 1..3px shade band: big panels get a lip, not a grey slab
		var sh: float = clampf(roundf(inner.size.y * 0.28), 1.0, 3.0)
		ci.draw_rect(Rect2(inner.position.x + rad, inner.end.y - sh, inner.size.x - rad * 2, sh), shade_of(fill))
		ci.draw_rect(Rect2(inner.end.x - 1, inner.position.y + rad, 1, inner.size.y - rad * 2), shade_of(fill))
	if _rim(outline, fill):
		ci.draw_rect(Rect2(inner.position.x + 1 + rad, inner.position.y, inner.size.x - 2 - rad * 2, 1), rim_of(fill))
		ci.draw_rect(Rect2(inner.position.x, inner.position.y + 1 + rad, 1, roundf(inner.size.y * 0.6) - rad), rim_of(fill))


## Filled disc with a 1px outline ring (B..F: outline_px ring).
static func disc(ci: CanvasItem, c: Vector2, rad: float, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_circle(c, rad + 1.0, outline)
		ci.draw_circle(c, rad, fill)
		return
	ci.draw_circle(c, rad + float(ow()), outline)
	ci.draw_circle(c, rad, fill)
	_round_tones(ci, c, rad, rad, fill, outline)


static func ellipse_points(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_colored_polygon(ellipse_points(c, rx + 1.0, ry + 1.0), outline)
		ci.draw_colored_polygon(ellipse_points(c, rx, ry), fill)
		return
	var o: float = float(ow())
	var n: int = 28 if maxf(rx, ry) > 12.0 else 20
	ci.draw_colored_polygon(ellipse_points(c, rx + o, ry + o, n), outline)
	ci.draw_colored_polygon(ellipse_points(c, rx, ry, n), fill)
	_round_tones(ci, c, rx, ry, fill, outline)


## D: shade crescent on the bottom/right, 1px rim arc on the top/left of a disc / ellipse.
static func _round_tones(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, outline: Color) -> void:
	if minf(rx, ry) < 3.0:
		return
	if _cel(outline, fill):
		ci.draw_colored_polygon(ellipse_points(c, rx, ry, 24), shade_of(fill))
		ci.draw_colored_polygon(ellipse_points(c + Vector2(-1, -1.5), rx - 1.0, ry - 1.5, 24), fill)
	if _rim(outline, fill):
		var pts := PackedVector2Array()
		for i in 9:
			var a: float = lerpf(PI * 1.05, PI * 1.55, float(i) / 8.0)
			pts.append(c + Vector2(cos(a) * (rx - 1.5), sin(a) * (ry - 1.5)))
		ci.draw_polyline(pts, rim_of(fill), 1.0)


## Closed polygon with outline. A: fill + 1px polyline (the original look). B..F: the outline
## is the polygon grown outward by outline_px (mitred joins), then the fill, then D tones.
static func poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: Color = OUTLINE) -> void:
	if legacy():
		ci.draw_colored_polygon(pts, fill)
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), outline)
		return
	var grown: Array = Geometry2D.offset_polygon(pts, float(ow()), Geometry2D.JOIN_MITER)
	if not grown.is_empty():
		ci.draw_colored_polygon(grown[0], outline)
	ci.draw_colored_polygon(pts, fill)
	if _cel(outline, fill):
		var inner: Array = Geometry2D.offset_polygon(pts, -1.5, Geometry2D.JOIN_MITER)
		if not inner.is_empty():
			ci.draw_colored_polygon(pts, shade_of(fill))
			var sh := PackedVector2Array()
			for p in (inner[0] as PackedVector2Array):
				sh.append(p + Vector2(-1, -1))
			ci.draw_colored_polygon(sh, fill)
	if _rim(outline, fill):
		var inner2: Array = Geometry2D.offset_polygon(pts, -1.0, Geometry2D.JOIN_MITER)
		if not inner2.is_empty():
			var ip: PackedVector2Array = inner2[0]
			var cw: bool = Geometry2D.is_polygon_clockwise(ip)
			for i in ip.size():
				var a: Vector2 = ip[i]
				var b: Vector2 = ip[(i + 1) % ip.size()]
				var d: Vector2 = (b - a).normalized()
				var nrm := Vector2(-d.y, d.x) if cw else Vector2(d.y, -d.x)
				if nrm.dot(Vector2(-0.6, -1.0).normalized()) > 0.35:
					ci.draw_line(a, b, rim_of(fill), 1.0)


## Thick arc "handle" (cup / pitcher / kettle): outline arc of width w plus an optional inner
## colour arc of width inner_w. A: exactly the original draw_arc calls.
static func handle(ci: CanvasItem, c: Vector2, rad: float, a0: float, a1: float, n: int, w: float, inner: Color = Color(0, 0, 0, 0), inner_w: float = 0.0) -> void:
	if legacy():
		ci.draw_arc(c, rad, a0, a1, n, OUTLINE, w)
		if inner.a > 0.0:
			ci.draw_arc(c, rad, a0, a1, n, inner, inner_w)
		return
	var iw: float = inner_w
	if chunky() and inner.a > 0.0:
		iw = maxf(inner_w, 2.0)
	ci.draw_arc(c, rad, a0, a1, n, OUTLINE, maxf(w, iw + 2.0) + float(ow() - 1) * 2.0)
	if inner.a > 0.0:
		ci.draw_arc(c, rad, a0, a1, n, inner, iw)


## Outlined straight bar (crank arm): A = width-w outline line + width-1 inner line.
static func bar_line(ci: CanvasItem, a: Vector2, b: Vector2, inner: Color, w: float = 3.0) -> void:
	if legacy():
		ci.draw_line(a, b, OUTLINE, w)
		ci.draw_line(a, b, inner, 1.0)
		return
	var iw: float = lw()
	ci.draw_line(a, b, OUTLINE, iw + float(ow()) * 2.0)
	ci.draw_line(a, b, inner, iw)


## Arc polyline (pixel-ish, width 1..2).
static func arc(ci: CanvasItem, c: Vector2, rad: float, a0: float, a1: float, col: Color, width: float = 1.0, n: int = 16) -> void:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a: float = lerpf(a0, a1, float(i) / float(n))
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	ci.draw_polyline(pts, col, width)


## Paw print: one big pad and four toe beans. size ~ pad radius in px.
## Chunky styles never go below size 2 (toes stay >= 2px wide).
static func paw(ci: CanvasItem, c: Vector2, size: float, col: Color, outline: bool = true) -> void:
	if legacy():
		_paw_legacy(ci, c, size, col, outline)
		return
	var o: float = float(ow())
	if chunky():
		size = maxf(size, 2.0)
	var pad_r: float = size
	var toe_r: float = maxf(1.0, size * 0.45)
	if chunky():
		toe_r = maxf(1.25, size * 0.5)
	var toes: Array[Vector2] = [
		Vector2(-size * 1.05, -size * 0.75), Vector2(-size * 0.38, -size * 1.35),
		Vector2(size * 0.38, -size * 1.35), Vector2(size * 1.05, -size * 0.75)]
	var pc: Vector2 = c + Vector2(0, size * 0.15)
	if outline:
		var oc := Color(OUTLINE, col.a)
		ci.draw_colored_polygon(ellipse_points(pc, pad_r + o, pad_r * 0.8 + o, 14), oc)
		for t in toes:
			ci.draw_circle(c + t, toe_r + o, oc)
	ci.draw_colored_polygon(ellipse_points(pc, pad_r, pad_r * 0.8, 14), col)
	for t in toes:
		ci.draw_circle(c + t, toe_r, col)
	if outline and col.a > 0.99 and size >= 3.0:
		if bool(S["cel_shade"]):
			ci.draw_colored_polygon(ellipse_points(pc, pad_r, pad_r * 0.8, 14), shade_of(col))
			ci.draw_colored_polygon(ellipse_points(pc + Vector2(-0.5, -1.0), pad_r - 1.0, pad_r * 0.8 - 1.0, 14), col)
		if bool(S["rim_highlight"]):
			ci.draw_rect(Rect2((pc + Vector2(-pad_r * 0.5, -pad_r * 0.5)).round(), Vector2(2, 1)), rim_of(col))


static func _paw_legacy(ci: CanvasItem, c: Vector2, size: float, col: Color, outline: bool) -> void:
	var pad_r: float = size
	var toe_r: float = maxf(1.0, size * 0.45)
	var toes: Array[Vector2] = [
		Vector2(-size * 1.05, -size * 0.75), Vector2(-size * 0.38, -size * 1.35),
		Vector2(size * 0.38, -size * 1.35), Vector2(size * 1.05, -size * 0.75)]
	if outline:
		ci.draw_colored_polygon(ellipse_points(c + Vector2(0, size * 0.15), pad_r + 1.0, pad_r * 0.8 + 1.0, 14), OUTLINE)
		for t in toes:
			ci.draw_circle(c + t, toe_r + 1.0, OUTLINE)
	ci.draw_colored_polygon(ellipse_points(c + Vector2(0, size * 0.15), pad_r, pad_r * 0.8, 14), col)
	for t in toes:
		ci.draw_circle(c + t, toe_r, col)


## Little heart (for the purr chain chip). `outline` adds an outline ring in B..F only
## (A never outlined it).
static func heart(ci: CanvasItem, p: Vector2, col: Color, outline: bool = false) -> void:
	var rows: Array[String] = [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
	if outline and not legacy():
		var g: float = float(maxi(1, ow() - 1))
		for r in rows.size():
			for c in rows[r].length():
				if rows[r][c] == "#":
					ci.draw_rect(Rect2(p.x + c, p.y + r, 1, 1).grow(g), Color(OUTLINE, col.a))
	for r in rows.size():
		for c in rows[r].length():
			if rows[r][c] == "#":
				ci.draw_rect(Rect2(p.x + c, p.y + r, 1, 1), col)
	if outline and not legacy() and bool(S["rim_highlight"]):
		ci.draw_rect(Rect2(p.x + 1, p.y + 1, 2, 1), rim_of(col))


## Soft steam puff (three overlapping cream circles with an outline).
static func puff(ci: CanvasItem, c: Vector2, rad: float, alpha: float, col: Color = MILK) -> void:
	if legacy():
		var oc0 := Color(OUTLINE, 0.35 * alpha)
		var fc0 := Color(col, 0.9 * alpha)
		var offs0: Array[Vector2] = [Vector2(-rad * 0.7, rad * 0.2), Vector2(rad * 0.7, rad * 0.2), Vector2(0, -rad * 0.35)]
		for o in offs0:
			ci.draw_circle(c + o, rad * 0.8 + 1.0, oc0)
		for o in offs0:
			ci.draw_circle(c + o, rad * 0.8, fc0)
		return
	if chunky():
		rad = maxf(2.5, roundf(rad))
	var oc := Color(OUTLINE, 0.6 * alpha)
	var fc := Color(col, 0.95 * alpha)
	var offs: Array[Vector2] = [Vector2(-rad * 0.7, rad * 0.2), Vector2(rad * 0.7, rad * 0.2), Vector2(0, -rad * 0.35)]
	for off in offs:
		ci.draw_circle((c + off).round(), rad * 0.8 + float(ow()), oc)
	for off in offs:
		ci.draw_circle((c + off).round(), rad * 0.8, fc)


static func judgement_color(j: String) -> Color:
	match j:
		"purrfect":
			return HONEY
		"good":
			return SAGE
		_:
			return OAK


static func judgement_text(j: String) -> String:
	match j:
		"purrfect":
			return "PURR-FECT!"
		"good":
			return "GOOD!"
		_:
			return "OK"
