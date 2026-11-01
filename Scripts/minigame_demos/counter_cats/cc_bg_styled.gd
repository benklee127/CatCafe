extends RefCounted

## Counter Cats kitchen background for art styles B-F (style A keeps the original
## painter in cc_game.gd untouched). Same layout and palette; every prop gets the
## style's outline thickness, and optionally chunky simplification, rim light,
## cel shade, cream halo and cocoa drop shadow.

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")

static func paint() -> ImageTexture:
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	var o: int = Art.ow()
	var ch: bool = Art.chunky()
	img.fill(Art.WALL)
	# wall stripes
	for x in range(0, 320, 16):
		img.fill_rect(Rect2i(x, 0, 6, 112), Art.WALL_STRIPE)
	# wainscot band
	img.fill_rect(Rect2i(0, 84, 320, 28), Color("#EBCFAE"))
	img.fill_rect(Rect2i(0, 84, 320, 2), Art.OAK)
	for x in range(8, 320, 24):
		img.fill_rect(Rect2i(x, 88, 18, 20), Color("#E3C39F"))
		if Art.flag("cel"):
			img.fill_rect(Rect2i(x, 106, 18, 2), Color("#D9B892"))
	# window (right)
	var wr := Rect2i(222, 12, 64, 46)
	box(img, wr, Art.OAK)
	img.fill_rect(wr.grow(-3), Art.SKY)
	img.fill_rect(Rect2i(wr.position.x + 3 + 29, wr.position.y + 3, 2, 40), Art.OAK)
	img.fill_rect(Rect2i(wr.position.x + 3, wr.position.y + 3 + 19, 58, 2), Art.OAK)
	if ch:
		img.fill_rect(Rect2i(232, 20, 12, 4), Color.WHITE)
		img.fill_rect(Rect2i(234, 18, 6, 2), Color.WHITE)
		img.fill_rect(Rect2i(262, 40, 10, 4), Color.WHITE)
	else:
		img.fill_rect(Rect2i(232, 22, 12, 3), Color.WHITE)
		img.fill_rect(Rect2i(235, 20, 6, 2), Color.WHITE)
		img.fill_rect(Rect2i(262, 40, 10, 3), Color.WHITE)
	box(img, Rect2i(218, 58, 72, 4), Art.OAK_DARK)
	# little plant on the sill
	box(img, Rect2i(274, 43, 4, 8), Art.SAGE_DARK)
	box(img, Rect2i(279, 41, 4, 10), Art.SAGE)
	box(img, Rect2i(276, 50, 8, 9), Color("#C9785A"))
	# shelf (left) with jars
	box(img, Rect2i(10, 40, 76, 4), Art.OAK)
	var jars: Array = [[13, Color("#F2C14E")], [26, Color("#9FD3E0")], [39, Color("#E79AA0")], [52, Color("#C9A27A")], [65, Color("#8FBF9F")]]
	for j in jars:
		var x: int = j[0]
		box(img, Rect2i(x + 2, 26, 7, 3 + (1 if ch else 0)), Art.OAK_LIGHT)
		box(img, Rect2i(x, 28, 11, 12), j[1])
		if not Art.flag("rim"):
			img.fill_rect(Rect2i(x + 2, 31, 2 if ch else 1, 6), Color(1, 1, 1, 0.6) if not ch else Color(j[1]).lightened(0.5))
	# counter top surface + front
	img.fill_rect(Rect2i(0, 110, 320, 12), Art.OAK)
	img.fill_rect(Rect2i(0, 110, 320, o), Art.OUTLINE)
	img.fill_rect(Rect2i(0, 110 + o, 320, 2), Art.OAK_LIGHT)
	img.fill_rect(Rect2i(0, 122, 320, o), Art.OUTLINE)
	img.fill_rect(Rect2i(0, 122 + o, 320, 58 - o), Art.OAK_DARK)
	img.fill_rect(Rect2i(0, 122 + o, 320, 2), Art.OAK_DEEP)
	for x in range(40, 320, 56):
		box(img, Rect2i(x, 130, 46, 42), Color("#B48862"))
		if not (Art.flag("rim") or ch):
			img.fill_rect(Rect2i(x + 1, 131, 44, 1), Color("#C79C74"))
	# cake under a glass cloche (left end of the pass counter)
	box(img, Rect2i(12, 113, 44, 4), Color("#F7EBDD"))
	box(img, Rect2i(22, 101, 24, 13), Color("#F3D7A6"))
	img.fill_rect(Rect2i(23, 102, 22, 3), Color("#FFF3DC"))
	img.fill_rect(Rect2i(23, 107, 22, 2 if ch else 1), Art.PINK)
	box(img, Rect2i(32, 97, 4, 5), Art.ROSE)
	_cloche(img)
	return ImageTexture.create_from_image(img)

## Outlined prop: outline grows outward to outline_px; halo/shadow/rim/cel per style.
static func box(img: Image, r: Rect2i, fill: Color) -> void:
	var g: int = Art.ow() - 1
	var outer: Rect2i = r.grow(g)
	if Art.flag("shadow"):
		_blend_rect(img, Rect2i(outer.position + Vector2i(1, 1), outer.size), Art.SHADOW)
	if Art.flag("halo"):
		_notched(img, outer.grow(1), Art.CREAM)
	_notched(img, outer, Art.OUTLINE)
	var inner: Rect2i = r.grow(-1)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	img.fill_rect(inner, fill)
	if Art.flag("cel") and inner.size.y >= 3:
		var h: int = maxi(1, roundi(inner.size.y * 0.3))
		img.fill_rect(Rect2i(inner.position.x, inner.end.y - h, inner.size.x, h), Art.cel_col(fill))
	if Art.flag("rim"):
		img.fill_rect(Rect2i(inner.position.x, inner.position.y, inner.size.x, 1), Art.rim_col(fill))
		img.fill_rect(Rect2i(inner.position.x, inner.position.y, 1, inner.size.y), Art.rim_col(fill))

static func _notched(img: Image, r: Rect2i, col: Color) -> void:
	if not Art.chunky() or r.size.x < 4 or r.size.y < 4:
		img.fill_rect(r, col)
		return
	img.fill_rect(Rect2i(r.position.x + 1, r.position.y, r.size.x - 2, r.size.y), col)
	img.fill_rect(Rect2i(r.position.x, r.position.y + 1, r.size.x, r.size.y - 2), col)

static func _blend_rect(img: Image, r: Rect2i, col: Color) -> void:
	var c: Rect2i = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	for y in range(c.position.y, c.end.y):
		for x in range(c.position.x, c.end.x):
			img.set_pixel(x, y, img.get_pixel(x, y).blend(col))

## Glass cloche: a thick dome outline traced from an ellipse mask.
static func _cloche(img: Image) -> void:
	var o: int = Art.ow()
	var inside := func(x: int, y: int) -> bool:
		if y < 86:
			return false
		var hw: int = 20
		if y < 114:
			hw = int(round(20.0 * sqrt(clampf(1.0 - pow((114.0 - float(y)) / 28.0, 2.0), 0.0, 1.0))))
		return absi(x - 34) <= hw
	var bx := Rect2i(8, 78, 54, 37)
	var dist: Dictionary = {}
	for y in range(bx.position.y, bx.end.y):
		for x in range(bx.position.x, bx.end.x):
			if not inside.call(x, y):
				continue
			# 4-neighbour distance to the outside, capped at o
			for d in range(1, o + 1):
				var edge: bool = false
				for v in [Vector2i(d, 0), Vector2i(-d, 0), Vector2i(0, d), Vector2i(0, -d)]:
					var q: Vector2i = Vector2i(x, y) + v
					if q.y < 114 and not inside.call(q.x, q.y):
						edge = true
				if edge:
					dist[Vector2i(x, y)] = d
					break
	if Art.flag("halo") or Art.flag("shadow"):
		for y in range(bx.position.y, bx.end.y):
			for x in range(bx.position.x, bx.end.x):
				if inside.call(x, y) or y >= 114:
					continue
				if Art.flag("halo") and (dist.has(Vector2i(x + 1, y)) or dist.has(Vector2i(x - 1, y)) or dist.has(Vector2i(x, y + 1)) or dist.has(Vector2i(x, y - 1))):
					img.set_pixel(x, y, Art.CREAM)
				elif Art.flag("shadow") and dist.has(Vector2i(x - 1, y - 1)):
					img.set_pixel(x, y, img.get_pixel(x, y).blend(Art.SHADOW))
	for p in dist:
		img.set_pixel(p.x, p.y, Art.OUTLINE)
	# knob
	img.fill_rect(Rect2i(30, 84 - (o - 1), 9, 2 + o), Art.OUTLINE)
	img.fill_rect(Rect2i(31, 85 - (o - 1), 7, o), Art.OAK_LIGHT)
	# glare
	var gw: int = 2 if Art.chunky() else 1
	img.fill_rect(Rect2i(18 + o, 92, gw, 10), Color(1, 1, 1, 0.8))
	img.fill_rect(Rect2i(20 + o, 89, gw, 3), Color(1, 1, 1, 0.8))
