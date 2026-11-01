extends RefCounted

## Shared procedural pixel art for "Paw & Pour" (no image assets): verb / station icons, grade
## stamps, and finished-dish sprites for all 10 recipes in two quality looks.
##
## Everything is drawn in art pixels from 1px rects / pixel rows, so it stays crisp at any integer
## scale. Callers outside the 320x180 PlayArea (host header, result card, demo launcher) scale with
## ci.draw_set_transform(offset, 0, Vector2(k, k)) using an integer k.
##
## Usage (no class_name; preload by path):
##   const KitchenArt = preload("res://Scripts/minigame/cooking/KitchenArt.gd")
##   KitchenArt.verb_icon(ci, top_left, "pour")                      # 10x10 art px
##   KitchenArt.grade_stamp(ci, center, "S")                        # ~22x22 art px
##   KitchenArt.dish(ci, bottom_center, recipe_id, dish_def, info)  # fits a 64x56 box above bottom
##   info = KitchenArt.dish_info(result_steps, precision)           # {great, art, browns, ...}
##
## Palette: warm dark-brown outline, cream / oak / sage / honey. Alert orange is never used here
## (it is reserved for spills inside the verbs).

const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")

const OUTLINE := Color("#4A3426")
const CREAM := Color("#FFF6EA")
const CREAM_DARK := Color("#F1E2CC")
const OAK := Color("#C9A27A")
const OAK_DARK := Color("#A57C55")
const SAGE := Color("#8FBF9F")
const SAGE_DARK := Color("#6E9E80")
const HONEY := Color("#E8B04B")
const HONEY_LIGHT := Color("#F4D58D")
const HONEY_DARK := Color("#B9862F")
const COFFEE := Color("#7A4E33")
const MILK := Color("#FBF3E4")
const BLUSH := Color("#F2B8A8")
const COCOA := Color("#5A3A2A")
const BEAN := Color("#8C4A3A")
const GLASS := Color("#FBF7F0")

## Precision at or above this uses the "great" dish look (S/A territory).
const GREAT_PRECISION := 0.75

const ICON_SIZE := 10

const PAL: Dictionary = {
	"o": OUTLINE, "c": CREAM, "C": CREAM_DARK, "k": OAK, "K": OAK_DARK, "s": SAGE, "S": SAGE_DARK,
	"h": HONEY, "H": HONEY_LIGHT, "d": HONEY_DARK, "f": COFFEE, "m": MILK, "b": BLUSH,
}

## 10x10 station icons ('.' = transparent). Keys = verb types + "serve" + "counter".
const ICONS: Dictionary = {
	"pour": [
		"oooooo....",
		"occcccoo..",
		".occccof..",
		"..oooo.f..",
		".......f..",
		"....o..f.o",
		"....offffo",
		"....occcco",
		"....occcco",
		".....oooo.",
	],
	"keep_zone": [
		"...oooo...",
		"...occo...",
		".ooossooo.",
		"...osso..h",
		"...osso.hh",
		"...osso..h",
		".ooossooo.",
		"...occo...",
		"...occo...",
		"...oooo...",
	],
	"trace": [
		"...oooo...",
		".oommmmoo.",
		".ommmmmmo.",
		"ommffmffmo",
		"ommfffffmo",
		"ommmfffmmo",
		"ommmmfmmmo",
		".ommmmmmo.",
		".oommmmoo.",
		"...oooo...",
	],
	"place": [
		"..o....o..",
		"..oooooo..",
		"..occcco..",
		"..ofccfo..",
		"..oooooo..",
		"....ss....",
		"..ssssss..",
		"...ssss...",
		"....ss....",
		".ohhhhhho.",
	],
	"back_burner": [
		"....oo....",
		"..oKKKKo..",
		".oooooooo.",
		"oossssssoo",
		".osssssso.",
		".osssssso.",
		"..oooooo..",
		"..h.hh.h..",
		"..hhhhhh..",
		".kkkkkkkk.",
	],
	"stop_ring": [
		"...oooo...",
		"....oo....",
		"..oooooo..",
		".ommhhhmo.",
		"ommmmommmo",
		"ommmmommmo",
		"ommmmoommo",
		".ommmmmmo.",
		"..oooooo..",
		"..........",
	],
	"serve": [
		"....oo....",
		"...oooo...",
		"..ohhhho..",
		".ohHhhhho.",
		".ohHhhhho.",
		"ohhhhhhhho",
		"oooooooooo",
		".kkkkkkkk.",
		".oooooooo.",
		"..........",
	],
	"counter": [
		"..........",
		"....o.o...",
		"...o.o.o..",
		"..........",
		"..ooooooo.",
		".occcccco.",
		"oooooooooo",
		"okkkkkkkko",
		"oKKKKKKKKo",
		"oooooooooo",
	],
}

## Short labels for station chips (verbs) when a step has no label.
const VERB_NAMES: Dictionary = {
	"pour": "Pour", "keep_zone": "Keep zone", "stop_ring": "Stop ring", "trace": "Trace",
	"place": "Place", "back_burner": "Back burner",
}

const GRADE_STAMPS: Dictionary = {
	"S": {"bg": "#E8B04B", "text": "PURR-FECT!", "sub": "Gold paw!"},
	"A": {"bg": "#8FBF9F", "text": "Great!", "sub": "Lovely work"},
	"B": {"bg": "#FFF6EA", "text": "Yummy!", "sub": "Happy nom"},
	"C": {"bg": "#F6E7D2", "text": "Still tasty!", "sub": "made with love"},
}


# --- Low-level pixel helpers ---------------------------------------------------------------

## Draws a bitmap of palette characters (see PAL). Runs of the same colour become one rect.
static func bitmap(ci: CanvasItem, top_left: Vector2, rows: Array, pal: Dictionary = PAL) -> void:
	var o: Vector2 = PixelDraw.snap(top_left)
	if not PixelDraw.legacy():
		_bitmap_styled(ci, o, rows, pal)
		return
	for y in range(rows.size()):
		var row: String = String(rows[y])
		var x: int = 0
		while x < row.length():
			var ch: String = row[x]
			if ch == "." or not pal.has(ch):
				x += 1
				continue
			var run: int = 1
			while x + run < row.length() and row[x + run] == ch:
				run += 1
			ci.draw_rect(Rect2(o.x + x, o.y + y, run, 1), pal[ch], true)
			x += run


## B..F bitmap: outlined bitmaps (an 'o' ink entry) get the whole silhouette grown by
## 1px in ink first (thicker outer outline, same shape); chunky styles merge the light
## tints into their base tone (fewer colours); D adds a 1px rim on the top-left fill pixels.
static func _bitmap_styled(ci: CanvasItem, o: Vector2, rows: Array, pal: Dictionary) -> void:
	var outlined: bool = pal.has("o") and PixelDraw._is_ink(pal["o"])
	var p2: Dictionary = pal
	if PixelDraw.chunky() and pal == PAL:
		p2 = pal.duplicate()
		p2["H"] = HONEY
		p2["C"] = CREAM
	# +1px max: tiny bitmaps (10px icons, stamp paws) would clog their 1-2px gaps at +2
	var g: float = minf(float(PixelDraw.ow() - 1), 1.0)
	if outlined and g > 0.0:
		var oc: Color = pal["o"]
		for y in range(rows.size()):
			var row: String = String(rows[y])
			var x: int = 0
			while x < row.length():
				if row[x] == "." or not pal.has(row[x]):
					x += 1
					continue
				var run: int = 1
				while x + run < row.length() and row[x + run] != "." and pal.has(row[x + run]):
					run += 1
				ci.draw_rect(Rect2(o.x + x, o.y + y, run, 1).grow(g), oc, true)
				x += run
	for y in range(rows.size()):
		var row: String = String(rows[y])
		var x: int = 0
		while x < row.length():
			var ch: String = row[x]
			if ch == "." or not p2.has(ch):
				x += 1
				continue
			var run: int = 1
			while x + run < row.length() and row[x + run] == ch:
				run += 1
			ci.draw_rect(Rect2(o.x + x, o.y + y, run, 1), p2[ch], true)
			x += run
	if outlined and bool(PixelDraw.S["rim_highlight"]):
		# rim: fill pixels whose top or left neighbour is the ink outline
		for y in range(1, rows.size()):
			var row: String = String(rows[y])
			var up: String = String(rows[y - 1])
			for x in range(1, row.length()):
				var ch: String = row[x]
				if ch == "." or ch == "o" or not p2.has(ch):
					continue
				var t: String = up[x] if x < up.length() else "."
				var l: String = row[x - 1]
				if t == "o" or l == "o":
					ci.draw_rect(Rect2(o.x + x, o.y + y, 1, 1), PixelDraw.rim_of(p2[ch]), true)


## Filled ellipse as 1px rows (no outline).
static func ellipse(ci: CanvasItem, center: Vector2, rx: float, ry: float, col: Color) -> void:
	var c: Vector2 = PixelDraw.snap(center)
	var ri: int = maxi(int(ceilf(ry)), 1)
	for row in range(-ri, ri):
		var dy: float = (float(row) + 0.5) / maxf(ry, 0.5)
		var hw: float = roundf(rx * sqrt(maxf(1.0 - dy * dy, 0.0)))
		if hw > 0.0:
			ci.draw_rect(Rect2(c.x - hw, c.y + row, hw * 2.0, 1), col, true)


## Ellipse with a 1px outline.
static func oval(ci: CanvasItem, center: Vector2, rx: float, ry: float, fill: Color, outline: Color = OUTLINE) -> void:
	if PixelDraw.legacy():
		ellipse(ci, center, rx, ry, outline)
		if rx > 1.5 and ry > 1.5:
			ellipse(ci, center, rx - 1.0, ry - 1.0, fill)
		return
	var g: float = float(PixelDraw.ow() - 1)
	ellipse(ci, center, rx + g, ry + g, outline)
	if rx > 1.5 and ry > 1.5:
		ellipse(ci, center, rx - 1.0, ry - 1.0, fill)
		PixelDraw._round_tones(ci, center, rx - 1.0, ry - 1.0, fill, outline)


## 5x5 paw print (reads at tiny sizes, unlike a scaled-down disc paw).
static func paw5(ci: CanvasItem, center: Vector2, col: Color) -> void:
	bitmap(ci, PixelDraw.snap(center) - Vector2(2, 2), [".x.x.", "x...x", ".xxx.", "xxxxx", ".xxx."], {"x": col})


## 3x3 mini paw for very small spots.
static func paw3(ci: CanvasItem, center: Vector2, col: Color) -> void:
	if not PixelDraw.legacy() and PixelDraw.chunky():
		paw5(ci, center, col)
		return
	bitmap(ci, PixelDraw.snap(center) - Vector2(1, 1), ["x.x", ".x.", "xxx"], {"x": col})


static func poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline: Color = OUTLINE) -> void:
	var snapped := PackedVector2Array()
	for p in pts:
		snapped.append(PixelDraw.snap(p))
	if not PixelDraw.legacy():
		PixelDraw.outlined_poly(ci, snapped, fill, outline)
		return
	ci.draw_colored_polygon(snapped, fill)
	snapped.append(snapped[0])
	for i in range(snapped.size() - 1):
		PixelDraw.line(ci, snapped[i], snapped[i + 1], outline)


static func _brown(b: float) -> Color:
	# 0 raw -> 0.5 golden -> 1 toasty (no orange: toasty is warm oak brown)
	var x: float = clampf(b, 0.0, 1.0)
	if x <= 0.5:
		return CREAM_DARK.lerp(HONEY, x / 0.5)
	return HONEY.lerp(COFFEE, (x - 0.5) / 0.5)


# --- Station / verb icons ------------------------------------------------------------------

static func has_icon(id: String) -> bool:
	return ICONS.has(id)


## 10x10 verb icon at `top_left` (art px). Unknown ids draw the counter icon.
static func verb_icon(ci: CanvasItem, top_left: Vector2, id: String) -> void:
	var rows: Array = ICONS.get(id, ICONS["counter"])
	bitmap(ci, top_left, rows)


# --- Grade stamps --------------------------------------------------------------------------

## Grade stamp art (~22x22 art px) centred on `center`.
## S gold paw, A sage paw, B cream paw + heart, C sleepy cat with a thumbs-up paw.
static func grade_stamp(ci: CanvasItem, center: Vector2, grade: String) -> void:
	var c: Vector2 = PixelDraw.snap(center)
	match grade:
		"S":
			PixelDraw.circle(ci, c, 11, HONEY_DARK)
			PixelDraw.disc(ci, c, 9, HONEY)
			_big_paw(ci, c + Vector2(0, 1), HONEY_LIGHT, OUTLINE)
			PixelDraw.sparkle(ci, c + Vector2(-11, -9), 1, CREAM)
			PixelDraw.sparkle(ci, c + Vector2(11, -10), 2, CREAM)
			PixelDraw.sparkle(ci, c + Vector2(10, 9), 1, CREAM)
		"A":
			PixelDraw.circle(ci, c, 11, SAGE_DARK)
			PixelDraw.disc(ci, c, 9, SAGE)
			_big_paw(ci, c + Vector2(0, 1), CREAM, OUTLINE)
		"B":
			PixelDraw.circle(ci, c, 11, OAK)
			PixelDraw.disc(ci, c, 9, CREAM)
			_big_paw(ci, c + Vector2(0, 1), OAK, OUTLINE)
			bitmap(ci, c + Vector2(7, -12), [".x.x.", "xxxxx", ".xxx.", "..x.."], {"x": BLUSH})
		_:
			_sleepy_cat(ci, c)


## 17x14 outlined paw (pad + 4 toes) centred on `c`.
static func _big_paw(ci: CanvasItem, c: Vector2, fill: Color, outline: Color) -> void:
	var o: Vector2 = PixelDraw.snap(c) - Vector2(8, 7)
	var pal: Dictionary = {"o": outline, "f": fill}
	var toe: Array = [".ooo.", "offfo", "offfo", "offfo", ".ooo."]
	for p in [Vector2(3, 0), Vector2(9, 0), Vector2(0, 5), Vector2(12, 5)]:
		bitmap(ci, o + (p as Vector2), toe, pal)
	bitmap(ci, o + Vector2(4, 7), ["..ooooo..", ".offfffo.", "offfffffo", "offfffffo", "offfffffo", ".offfffo.", "..ooooo.."], pal)


static func _sleepy_cat(ci: CanvasItem, c: Vector2) -> void:
	# ears
	poly(ci, PackedVector2Array([c + Vector2(-10, -2), c + Vector2(-8, -11), c + Vector2(-3, -6)]), CREAM)
	poly(ci, PackedVector2Array([c + Vector2(10, -2), c + Vector2(8, -11), c + Vector2(3, -6)]), CREAM)
	PixelDraw.px(ci, Rect2(c.x - 8, c.y - 7, 1, 2), BLUSH)
	PixelDraw.px(ci, Rect2(c.x + 7, c.y - 7, 1, 2), BLUSH)
	oval(ci, c + Vector2(0, 1), 10, 8, CREAM)
	# closed eyes (little arcs), nose, blush
	bitmap(ci, c + Vector2(-7, 0), ["x...x", ".xxx."], {"x": OUTLINE})
	bitmap(ci, c + Vector2(3, 0), ["x...x", ".xxx."], {"x": OUTLINE})
	PixelDraw.px(ci, Rect2(c.x - 1, c.y + 3, 2, 1), BLUSH.darkened(0.2))
	bitmap(ci, c + Vector2(-2, 4), ["x..x", ".xx."], {"x": OUTLINE})
	PixelDraw.px(ci, Rect2(c.x - 8, c.y + 3, 2, 1), BLUSH)
	PixelDraw.px(ci, Rect2(c.x + 6, c.y + 3, 2, 1), BLUSH)
	# thumbs-up paw
	PixelDraw.circle(ci, c + Vector2(9, 8), 3.5, CREAM)
	PixelDraw.outlined_rect(ci, Rect2(c.x + 8, c.y + 1, 3, 5), CREAM)
	# z z
	bitmap(ci, c + Vector2(6, -14), ["xxx", "..x", ".x.", "x..", "xxx"], {"x": OUTLINE})
	bitmap(ci, c + Vector2(11, -11), ["xx", ".x", "x.", "xx"], {"x": OAK_DARK})


static func grade_style(grade: String) -> Dictionary:
	return GRADE_STAMPS.get(grade, GRADE_STAMPS["B"])


# --- Dish info -----------------------------------------------------------------------------

## Builds the `info` dictionary for dish() from result steps ([{type, accuracy, extra}]).
## great: precision >= GREAT_PRECISION; art: the player's TRACE strokes (normalized -1..1);
## browns: STOP_RING browning per step (0.5 = golden); placed: PLACE mean offset score.
static func dish_info(step_results: Array, precision: float) -> Dictionary:
	var info: Dictionary = {"great": precision >= GREAT_PRECISION, "precision": precision, "art": [], "browns": []}
	var place_scores: Array = []
	for r in step_results:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		var ex: Dictionary = d.get("extra", {}) if d.get("extra", {}) is Dictionary else {}
		match String(d.get("type", "")):
			"trace":
				if (info["art"] as Array).is_empty() and ex.get("art", []) is Array and not (ex.get("art", []) as Array).is_empty():
					info["art"] = ex["art"]
					info["ink"] = String(ex.get("ink", ""))
					info["ink2"] = String(ex.get("ink2", ""))
					info["canvas"] = String(ex.get("canvas", ""))
			"stop_ring":
				if ex.has("browns") and ex["browns"] is Array and (ex["browns"] as Array).size() == 1:
					(info["browns"] as Array).append(float((ex["browns"] as Array)[0]))
				elif ex.has("brown"):
					(info["browns"] as Array).append(float(ex["brown"]))
			"place":
				place_scores.append(float(d.get("accuracy", 1.0)))
	if not place_scores.is_empty():
		var s: float = 0.0
		for v in place_scores:
			s += float(v)
		info["place"] = s / float(place_scores.size())
	return info


# --- Dish sprites ---------------------------------------------------------------------------

## Draws the finished dish for `recipe_id` with its bottom centre at `bottom` (art px).
## Fits roughly a 64x56 box above `bottom`. info: see dish_info(); extra keys t (anim time),
## reduced (bool, no sparkles/steam motion), fx (bool, default true: sparkles / heart; false for
## small icons), coat (Color, Kitten Mochi coat).
static func dish(ci: CanvasItem, bottom: Vector2, recipe_id: String, dish_def: Dictionary = {}, info: Dictionary = {}) -> void:
	var b: Vector2 = PixelDraw.snap(bottom)
	var great: bool = bool(info.get("great", true))
	match recipe_id:
		"paw_print_cookies":
			_cookies(ci, b, great, info)
		"catpuccino":
			_catpuccino(ci, b, great, info)
		"purrfect_matcha_latte":
			_matcha(ci, b, great, info)
		"tuxedo_cocoa":
			_cocoa(ci, b, great, info)
		"not_tuna_taiyaki":
			_taiyaki(ci, b, great, info)
		"kitten_mochi":
			_mochi(ci, b, great, info)
		"toe_bean_milk_tea":
			_milk_tea(ci, b, great, info)
		"cat_nap_chamomile":
			_chamomile(ci, b, great, info)
		"calico_pancake_stack":
			_pancakes(ci, b, great, info)
		"tuxedo_affogato":
			_affogato(ci, b, great, info)
		_:
			_generic(ci, b, great, dish_def)
	if bool(info.get("fx", true)):
		_quality_fx(ci, b, great, info)


static func _quality_fx(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var t: float = float(info.get("t", 0.0))
	var reduced: bool = bool(info.get("reduced", false))
	if great:
		var tw: float = 0.0 if reduced else roundf(sin(t * 6.0))
		PixelDraw.sparkle(ci, b + Vector2(-29, -46 - tw), 2, HONEY)
		PixelDraw.sparkle(ci, b + Vector2(28, -38 + tw), 1, HONEY)
		PixelDraw.sparkle(ci, b + Vector2(24, -54 - tw), 1, HONEY_LIGHT)
	else:
		# homely look: a little "made with love" heart floating up
		var off: float = 0.0 if reduced else roundf(fmod(t * 6.0, 6.0))
		bitmap(ci, b + Vector2(24, -46 - off), ["x.x", "xxx", ".x."], {"x": BLUSH})


static func _steam(ci: CanvasItem, top: Vector2, info: Dictionary) -> void:
	var t: float = float(info.get("t", 0.0))
	var reduced: bool = bool(info.get("reduced", false))
	var col := Color(1, 1, 1, 0.75)
	for k in range(2):
		var ph: float = 0.0 if reduced else fmod(t * 8.0 + float(k) * 5.0, 10.0)
		var x: float = top.x - 4.0 + float(k) * 8.0 + (0.0 if reduced else roundf(sin(t * 3.0 + float(k)) * 1.0))
		var y: float = top.y - 4.0 - roundf(ph)
		ci.draw_rect(Rect2(x, y, 1, 3), Color(col, 0.75 - ph * 0.05), true)
		ci.draw_rect(Rect2(x + 1, y - 3, 1, 3), Color(col, 0.6 - ph * 0.05), true)


static func _plate(ci: CanvasItem, b: Vector2, hw: float) -> void:
	PixelDraw.shadow(ci, b + Vector2(0, 1), hw + 2, 2)
	oval(ci, b + Vector2(0, -3), hw, 5, CREAM)
	ellipse(ci, b + Vector2(0, -4), hw - 5, 2.5, CREAM_DARK)


## Mug on a saucer. Returns the liquid surface ellipse as [center, rx, ry].
static func _mug(ci: CanvasItem, b: Vector2, w: int, h: int, body: Color, surface: Color, rim: Color = Color(0, 0, 0, 0)) -> Array:
	PixelDraw.shadow(ci, b + Vector2(0, 1), w * 0.5 + 8, 2)
	oval(ci, b + Vector2(0, -2), w * 0.5 + 7, 3, CREAM_DARK)
	var left: float = b.x - w * 0.5
	var top: float = b.y - 4 - h
	# handle
	PixelDraw.rounded_rect(ci, Rect2(left + w - 2, top + 6, 9, h - 10), 3, body)
	ci.draw_rect(Rect2(left + w, top + 9, 3, h - 16), CREAM_DARK, true)
	# body (rounded bottom)
	PixelDraw.rounded_rect(ci, Rect2(left, top, w, h + 1), 4, body)
	PixelDraw.hl(ci, Rect2(left + 2, top + 5, 2, h - 9), Color(1, 1, 1, 0.35))
	# rim + liquid surface (seen a little from above)
	var c := Vector2(b.x, top + 1)
	var rx: float = w * 0.5
	oval(ci, c, rx, 5, body)
	ellipse(ci, c, rx - 2, 3, rim if rim.a > 0.0 else surface.darkened(0.15))
	ellipse(ci, c + Vector2(0, 0), rx - 3, 2.5, surface)
	return [c, rx - 3.0, 2.5]


## Draws the player's TRACE strokes (normalized -1..1) into an ellipse.
static func _art(ci: CanvasItem, c: Vector2, rx: float, ry: float, art: Array, ink: Color, ink2: Color) -> void:
	for st in art:
		if not (st is Dictionary):
			continue
		var pts: Variant = (st as Dictionary).get("pts", PackedVector2Array())
		var col: Color = ink2 if bool((st as Dictionary).get("ink2", false)) else ink
		var prev := Vector2.INF
		for p in pts:
			var v: Vector2 = p
			var q: Vector2 = PixelDraw.snap(c + Vector2(v.x * rx, v.y * ry))
			if prev != Vector2.INF and prev.distance_to(q) > 0.5:
				ci.draw_line(prev + Vector2(0.5, 0.5), q + Vector2(0.5, 0.5), col, 1.0, false)
			else:
				ci.draw_rect(Rect2(q, Vector2.ONE), col, true)
			prev = q


static func _has_art(info: Dictionary) -> bool:
	return info.get("art", []) is Array and not (info.get("art", []) as Array).is_empty()


static func _col(s: Variant, fallback: Color) -> Color:
	var str_: String = String(s) if s != null else ""
	if str_ == "" or not Color.html_is_valid(str_):
		return fallback
	return Color(str_)


## Top-down latte-art thumbnail of the player's trace (result card "your latte-art").
static func latte_art(ci: CanvasItem, center: Vector2, r: float, info: Dictionary) -> void:
	var c: Vector2 = PixelDraw.snap(center)
	PixelDraw.shadow(ci, c + Vector2(0, r + 2), r + 2, 2)
	PixelDraw.circle(ci, c, r + 4, CREAM)
	PixelDraw.circle(ci, c, r, _col(info.get("canvas", ""), MILK))
	_art(ci, c, r * 0.82, r * 0.82, info.get("art", []), _col(info.get("ink", ""), COFFEE), _col(info.get("ink2", ""), OUTLINE))


# One function per recipe -----------------------------------------------------------------------

static func _cookies(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	_plate(ci, b, 30)
	var browns: Array = info.get("browns", [])
	var bake: float = float(browns[browns.size() - 1]) if not browns.is_empty() else 0.5
	var base: Color = _brown(bake) if not great else _brown(clampf(bake, 0.42, 0.58))
	var spots: Array = [Vector2(-11, -10), Vector2(11, -10), Vector2(0, -6)]
	for i in range(3):
		var p: Vector2 = b + spots[i]
		var col: Color = base
		var paw_off := Vector2.ZERO
		var r: float = 9.0
		if not great:
			if i == 1:
				col = base.darkened(0.22)
				r = 8.0
			if i == 2:
				paw_off = Vector2(2, 1)
				p += Vector2(2, 0)
		PixelDraw.circle(ci, p, r, col)
		PixelDraw.hl(ci, Rect2(p.x - 5, p.y - 6, 4, 1), col.lightened(0.3))
		paw5(ci, p + Vector2(0, 1) + paw_off, COFFEE)
	if not great:
		for q in [Vector2(-22, -4), Vector2(19, -3), Vector2(-15, -2)]:
			PixelDraw.px(ci, Rect2(b + (q as Vector2), Vector2(2, 1)), base.darkened(0.3))


static func _catpuccino(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var s: Array = _mug(ci, b, 34, 24, CREAM, MILK, COFFEE)
	var c: Vector2 = s[0]
	if _has_art(info):
		_art(ci, c, 12, 2.5, info["art"], COFFEE, COFFEE)
	elif great:
		# little cat face in the foam
		bitmap(ci, c + Vector2(-5, -2), ["x.....x", "xx...xx", "x.x.x.x", ".x...x."], {"x": COFFEE})
	else:
		bitmap(ci, c + Vector2(-4, -2), ["..xx..", ".xxxx.", "xxxxx."], {"x": COFFEE})
	_steam(ci, c + Vector2(0, -4), info)


static func _matcha(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var s: Array = _mug(ci, b, 34, 24, CREAM, SAGE, SAGE_DARK)
	var c: Vector2 = s[0]
	# sage band on the mug
	ci.draw_rect(Rect2(b.x - 16, b.y - 16, 32, 3), SAGE, true)
	paw3(ci, Vector2(b.x - 10, b.y - 10), SAGE_DARK)
	if _has_art(info):
		_art(ci, c, 12, 2.5, info["art"], MILK, MILK)
	elif great:
		paw5(ci, c + Vector2(0, 0), MILK)
	else:
		paw5(ci, c + Vector2(3, 0), MILK)
		PixelDraw.px(ci, Rect2(c.x - 4, c.y, 4, 1), MILK)
	_steam(ci, c + Vector2(0, -4), info)


static func _cocoa(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var s: Array = _mug(ci, b, 34, 24, COCOA, COFFEE.darkened(0.1), OUTLINE)
	var c: Vector2 = s[0]
	# tuxedo bow tie on the mug
	var bt := Vector2(b.x - 2, b.y - 13)
	bitmap(ci, bt - Vector2(4, 2), ["xx...xx", "xxx.xxx", "xxxxxxx", "xxx.xxx", "xx...xx"], {"x": CREAM})
	ci.draw_rect(Rect2(bt.x - 1, bt.y - 1, 3, 3), HONEY_LIGHT, true)
	if _has_art(info):
		_art(ci, c, 12, 2.5, info["art"], CREAM, CREAM)
	# marshmallow cat heads bobbing on top
	var offs: Array = [Vector2(-9, -2), Vector2(0, -3), Vector2(9, -2)]
	if not great:
		offs = [Vector2(-11, -1), Vector2(1, -5), Vector2(7, 0)]
	for i in range(3):
		var p: Vector2 = c + (offs[i] as Vector2)
		bitmap(ci, p - Vector2(3, 4), [
			"o.....o",
			"oo...oo",
			"occccco",
			"ocfcfco",
			"occbcco",
			".ooooo.",
		], {"o": OUTLINE, "c": CREAM, "f": OUTLINE, "b": BLUSH})


static func _taiyaki(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	_plate(ci, b, 30)
	var browns: Array = info.get("browns", [])
	var bake: float = float(browns[0]) if not browns.is_empty() else 0.5
	var body: Color = _brown(clampf(bake, 0.4, 0.6)) if great else _brown(maxf(bake, 0.68))
	var c := b + Vector2(-4, -12)
	# tail
	poly(ci, PackedVector2Array([c + Vector2(13, 0), c + Vector2(25, -8), c + Vector2(22, 0), c + Vector2(25, 7)]), body)
	oval(ci, c, 17, 8, body)
	# fins
	poly(ci, PackedVector2Array([c + Vector2(-2, -7), c + Vector2(4, -11), c + Vector2(6, -7)]), body)
	# scale chevrons
	var sc: Color = body.darkened(0.2)
	for k in range(3):
		bitmap(ci, c + Vector2(-2 + k * 5, -2), ["x.x", ".x."], {"x": sc})
		bitmap(ci, c + Vector2(0 + k * 5, 2), ["x.x", ".x."], {"x": sc})
	# eye + smile
	ci.draw_rect(Rect2(c.x - 11, c.y - 3, 2, 2), OUTLINE, true)
	bitmap(ci, c + Vector2(-15, 1), ["x..", ".xx"], {"x": OUTLINE})
	PixelDraw.hl(ci, Rect2(c.x - 9, c.y - 6, 4, 1), body.lightened(0.35))
	if not great:
		# red bean peeking out of the belly + a toasty patch
		ellipse(ci, c + Vector2(2, 8), 4, 2, BEAN)
		ellipse(ci, c + Vector2(8, -3), 3, 2, body.darkened(0.3))


static func _mochi(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	_plate(ci, b, 26)
	var coat: Color = info.get("coat", CREAM) if info.get("coat", null) is Color else CREAM
	var c := b + Vector2(0, -12)
	var ry: float = 10.0 if great else 9.0
	# ears
	var lear_y: float = 0.0 if great else 2.0
	poly(ci, PackedVector2Array([c + Vector2(-12, -4 + lear_y), c + Vector2(-10, -14 + lear_y), c + Vector2(-4, -8 + lear_y)]), coat)
	poly(ci, PackedVector2Array([c + Vector2(12, -4), c + Vector2(10, -14), c + Vector2(4, -8)]), coat)
	PixelDraw.px(ci, Rect2(c.x - 9, c.y - 10 + lear_y, 1, 2), BLUSH)
	PixelDraw.px(ci, Rect2(c.x + 8, c.y - 10, 1, 2), BLUSH)
	oval(ci, c, 15, ry, coat)
	ellipse(ci, c + Vector2(-5, -5), 4, 1.5, Color(1, 1, 1, 0.5))
	# face
	var eye_dy: int = 0 if great else 2
	ci.draw_rect(Rect2(c.x - 6, c.y - 1, 2, 2), OUTLINE, true)
	ci.draw_rect(Rect2(c.x + 4 + (0 if great else 1), c.y - 1 + eye_dy, 2, 2), OUTLINE, true)
	bitmap(ci, c + Vector2(-2, 2), ["x.x.x", ".x.x."], {"x": OUTLINE})
	PixelDraw.px(ci, Rect2(c.x - 10, c.y + 2, 3, 1), BLUSH)
	PixelDraw.px(ci, Rect2(c.x + 7, c.y + 2, 3, 1), BLUSH)


static func _milk_tea(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var w: float = 24.0
	var h: float = 44.0
	var r := Rect2(b.x - w * 0.5, b.y - h, w, h)
	PixelDraw.shadow(ci, b + Vector2(0, 1), 16, 2)
	# straw (behind the front glass)
	ci.draw_rect(Rect2(r.position.x + 13, r.position.y - 9, 3, 30), SAGE, true)
	PixelDraw.hl(ci, Rect2(r.position.x + 13, r.position.y - 9, 1, 30), SAGE_DARK)
	PixelDraw.rounded_rect(ci, r, 2, GLASS)
	var inner: Rect2 = r.grow(-1)
	var tea_h: float = roundf(inner.size.y * 0.52)
	var milk_h: float = roundf(inner.size.y * 0.34)
	var tea := Rect2(inner.position.x, inner.end.y - tea_h, inner.size.x, tea_h)
	ci.draw_rect(tea, OAK, true)
	var milk := Rect2(inner.position.x, tea.position.y - milk_h, inner.size.x, milk_h)
	ci.draw_rect(milk, MILK, true)
	if great:
		# scalloped calico seam
		for x in range(int(inner.position.x), int(inner.end.x), 4):
			PixelDraw.px(ci, Rect2(x, tea.position.y - 1, 2, 1), OAK)
	else:
		ci.draw_rect(Rect2(inner.position.x, tea.position.y - 3, inner.size.x, 5), OAK.lerp(MILK, 0.5), true)
	# pearls
	var n: int = 7 if great else 4
	for k in range(n):
		var px: float = inner.position.x + 2 + float((k * 5) % int(inner.size.x - 4))
		var py: float = inner.end.y - 3 - float((k % 2) * 3)
		ci.draw_rect(Rect2(px, py, 2, 2), OUTLINE, true)
	# shine + toe beans on the glass
	PixelDraw.hl(ci, Rect2(r.position.x + 2, r.position.y + 3, 1, h - 10), Color(1, 1, 1, 0.6))
	paw5(ci, Vector2(b.x - 3, b.y - 24), BLUSH)
	PixelDraw.line(ci, Vector2(r.position.x, r.position.y), Vector2(r.end.x - 1, r.position.y), OUTLINE)


static func _chamomile(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var s: Array = _mug(ci, b, 34, 24, CREAM, HONEY_LIGHT, HONEY)
	var c: Vector2 = s[0]
	if _has_art(info):
		_art(ci, c, 12, 2.5, info["art"], HONEY_DARK, HONEY_DARK)
	elif great:
		# sleepy cat face drizzled in honey
		bitmap(ci, c + Vector2(-5, -2), ["x.....x", "xx...xx", ".......", ".x...x."], {"x": HONEY_DARK})
	else:
		bitmap(ci, c + Vector2(-4, -2), [".xxx.", "x...x", ".x.x."], {"x": HONEY_DARK})
	# chamomile flower on the saucer
	var f := Vector2(b.x - 20, b.y - 4)
	bitmap(ci, f - Vector2(3, 3), [".ccc.", "cchcc", "chhhc", "cchcc", ".ccc."], {"c": CREAM, "h": HONEY})
	PixelDraw.px(ci, Rect2(f.x + 2, f.y + 2, 1, 2), SAGE_DARK)
	_steam(ci, c + Vector2(0, -4), info)


static func _pancakes(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	_plate(ci, b, 30)
	var browns: Array = info.get("browns", [])
	var offs: Array = [0, 0, 0] if great else [3, -4, 2]
	var spots: Array = [OAK_DARK, COFFEE, CREAM]
	var top_y: float = 0.0
	for i in range(3):
		var bb: float = float(browns[i]) if i < browns.size() else 0.5
		if great:
			bb = clampf(bb, 0.4, 0.6)
		var col: Color = _brown(bb)
		var y: float = b.y - 9 - float(i) * 6.0
		var x: float = b.x + float(offs[i])
		PixelDraw.rounded_rect(ci, Rect2(x - 20, y - 3, 40, 7), 3, col)
		PixelDraw.hl(ci, Rect2(x - 18, y - 2, 36, 1), col.lightened(0.25))
		# calico patches on the side
		for k in range(3):
			ci.draw_rect(Rect2(x - 14 + k * 11 + i * 2, y + 1, 4, 2), spots[(k + i) % 3], true)
		top_y = y - 3
	var tx: float = b.x + float(offs[2])
	# butter pat + syrup
	PixelDraw.outlined_rect(ci, Rect2(tx - 4, top_y - 3, 8, 4), HONEY_LIGHT)
	var syrup: Color = HONEY_DARK
	PixelDraw.px(ci, Rect2(tx - 14, top_y, 26, 1), syrup)
	ci.draw_rect(Rect2(tx - 15, top_y, 2, 6 if great else 10), syrup, true)
	ci.draw_rect(Rect2(tx + 12, top_y, 2, 9 if great else 4), syrup, true)


static func _affogato(ci: CanvasItem, b: Vector2, great: bool, info: Dictionary) -> void:
	var w: float = 30.0
	var h: float = 26.0
	var r := Rect2(b.x - w * 0.5, b.y - h, w, h)
	PixelDraw.shadow(ci, b + Vector2(0, 1), 18, 2)
	PixelDraw.rounded_rect(ci, r, 3, GLASS)
	var inner: Rect2 = r.grow(-1)
	var esp_h: float = 10.0 if great else 13.0
	ci.draw_rect(Rect2(inner.position.x, inner.end.y - esp_h, inner.size.x, esp_h), COFFEE.darkened(0.2), true)
	PixelDraw.px(ci, Rect2(inner.position.x, inner.end.y - esp_h, inner.size.x, 1), HONEY_DARK)
	# vanilla scoop
	var sc := Vector2(b.x, r.position.y - 3)
	var sry: float = 8.0 if great else 6.0
	oval(ci, sc, 12, sry, CREAM)
	ellipse(ci, sc + Vector2(-4, -3), 3, 1.5, Color(1, 1, 1, 0.8))
	# espresso cap on the scoop
	if _has_art(info):
		_art(ci, sc + Vector2(0, -1), 8, 4, info["art"], _col(info.get("ink", ""), OUTLINE), _col(info.get("ink2", ""), COFFEE))
	else:
		bitmap(ci, sc + Vector2(-5, -2), ["xx...xx", "xxx.xxx", "xxxxxxx", "xxx.xxx", "xx...xx"], {"x": OUTLINE})
	# tuxedo buttons on the glass
	var bx: float = b.x if great else b.x + 3.0
	PixelDraw.circle(ci, Vector2(bx, b.y - 17), 2, CREAM)
	PixelDraw.circle(ci, Vector2(bx, b.y - 10), 2, CREAM)
	PixelDraw.hl(ci, Rect2(r.position.x + 2, r.position.y + 3, 1, h - 7), Color(1, 1, 1, 0.6))
	if not great:
		# espresso ran down the side (warm brown, never alert orange)
		ci.draw_rect(Rect2(r.end.x - 3, r.position.y - 1, 2, 9), COFFEE, true)
		ci.draw_rect(Rect2(r.end.x - 3, r.position.y + 8, 2, 2), COFFEE.darkened(0.2), true)


static func _generic(ci: CanvasItem, b: Vector2, great: bool, dish_def: Dictionary) -> void:
	var cols: Array = dish_def.get("colors", ["#E8B04B"]) if dish_def.get("colors", []) is Array else ["#E8B04B"]
	var c0: Color = _col(cols[0] if cols.size() > 0 else "", HONEY)
	var c1: Color = _col(cols[1] if cols.size() > 1 else "", COFFEE)
	match String(dish_def.get("kind", "plate")):
		"mug":
			var s: Array = _mug(ci, b, 34, 24, CREAM, c0)
			paw5(ci, s[0], c1)
		"glass":
			var r := Rect2(b.x - 13, b.y - 40, 26, 40)
			PixelDraw.rounded_rect(ci, r, 2, GLASS)
			var gi: Rect2 = r.grow(-1)
			for k in range(cols.size()):
				var hh: float = roundf(gi.size.y * 0.85 / float(cols.size()))
				ci.draw_rect(Rect2(gi.position.x, gi.end.y - hh * float(k + 1), gi.size.x, hh), _col(cols[k], c0), true)
		_:
			_plate(ci, b, 30)
			for k in range(3):
				var p := Vector2(b.x - 14 + k * 14, b.y - 9 - (4 if k == 1 else 0))
				PixelDraw.circle(ci, p, 7, c0 if great else c0.darkened(0.15))
				paw5(ci, p, c1)
