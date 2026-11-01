extends Control

## Procedural pixel grade stamp (S/A/B/C) for the result card. Drawn as a grid of
## chunky "pixels" so it matches the 320x180 play area at 3x.

const Art := preload("res://Scripts/minigame_demos/counter_cats/cc_art.gd")

var grade: String = "A"
var cell: float = 4.5
var pop: float = 1.0

func set_grade(g: String) -> void:
	grade = g if Art.GLYPHS.has(g) else "C"
	queue_redraw()

func _get_minimum_size() -> Vector2:
	return Vector2(26, 26) * cell

func _draw() -> void:
	if not Art.is_a():
		_draw_styled()
		return
	var n: int = 26
	var col: Color = Art.GRADE_COLORS.get(grade, Art.MUTED)
	var c: Vector2 = Vector2(n, n) * 0.5
	var origin: Vector2 = (size - Vector2(n, n) * cell) * 0.5
	draw_set_transform(size * 0.5, -0.12, Vector2.ONE * pop)
	var o: Vector2 = origin - size * 0.5
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c)
			var fill: Color = Color(0, 0, 0, 0)
			if d <= 12.6:
				fill = Art.OUTLINE
			if d <= 11.6:
				fill = col
			if d <= 9.6:
				fill = Art.CREAM
			if d <= 8.6 and d > 7.8:
				fill = col.lightened(0.35)
			if fill.a > 0.0:
				draw_rect(Rect2(o + Vector2(x, y) * cell, Vector2(cell, cell)), fill)
	# glyph 5x7 at 2 cells per glyph pixel, centered
	var rows: Array = Art.GLYPHS.get(grade, Art.GLYPHS["C"])
	var gs: float = 2.0
	var gx0: float = c.x - 5.0 * gs * 0.5
	var gy0: float = c.y - 7.0 * gs * 0.5
	for gy in range(7):
		var row: String = rows[gy]
		for gx in range(5):
			if row[gx] == "X":
				var r := Rect2(o + Vector2(gx0 + gx * gs, gy0 + gy * gs) * cell, Vector2(gs, gs) * cell)
				draw_rect(r.grow(cell * 0.5), Art.OUTLINE)
	for gy in range(7):
		var row2: String = rows[gy]
		for gx in range(5):
			if row2[gx] == "X":
				draw_rect(Rect2(o + Vector2(gx0 + gx * gs, gy0 + gy * gs) * cell, Vector2(gs, gs) * cell), col)
	# paw-print pips around the rim
	for k in range(4):
		var a: float = -PI * 0.5 + TAU * float(k) / 4.0 + PI / 4.0
		var p: Vector2 = c + Vector2(cos(a), sin(a)) * 10.6
		draw_rect(Rect2(o + (p - Vector2(0.5, 0.5)) * cell, Vector2(cell, cell)), Art.CREAM)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Styles B-F: same 26-cell stamp, outline outline_px cells thick, crisp glyph
## outline (whole cells), optional halo / drop shadow / rim light / cel shade.
## Chunky styles drop the thin inner ring and use bigger rim pips.
func _draw_styled() -> void:
	var n: int = 26
	var o: int = Art.ow()
	var col: Color = Art.GRADE_COLORS.get(grade, Art.MUTED)
	var c: Vector2 = Vector2(n, n) * 0.5
	var origin: Vector2 = (size - Vector2(n, n) * cell) * 0.5
	draw_set_transform(size * 0.5, -0.12, Vector2.ONE * pop)
	var o2: Vector2 = origin - size * 0.5
	var r_out: float = 12.6
	var halo: float = 1.0 if Art.flag("halo") else 0.0
	var r_line: float = r_out - halo
	var r_band: float = r_line - float(o)
	var r_cream: float = r_band - 2.0
	if Art.flag("shadow"):
		for y in range(n):
			for x in range(n):
				if Vector2(x + 0.5 - 1.0, y + 0.5 - 1.0).distance_to(c) <= r_out:
					draw_rect(Rect2(o2 + Vector2(x, y) * cell, Vector2(cell, cell)), Art.SHADOW)
	for y in range(n):
		for x in range(n):
			var p := Vector2(x + 0.5, y + 0.5)
			var d: float = p.distance_to(c)
			var fill: Color = Color(0, 0, 0, 0)
			if d <= r_out and halo > 0.0:
				fill = Art.CREAM
			if d <= r_line:
				fill = Art.OUTLINE
			if d <= r_band:
				fill = col
				if Art.flag("rim") and (p - c).dot(Vector2(-1, -1).normalized()) > d * 0.55:
					fill = Art.rim_col(col)
				elif Art.flag("cel") and (p - c).dot(Vector2(1, 1).normalized()) > d * 0.55:
					fill = Art.cel_col(col)
			if d <= r_cream:
				fill = Art.CREAM
				if Art.flag("cel") and (p - c).dot(Vector2(1, 1).normalized()) > r_cream - 2.5:
					fill = Art.CREAM.darkened(0.07)
			if not Art.chunky() and d <= r_cream - 1.0 and d > r_cream - 1.8:
				fill = col.lightened(0.35)
			if fill.a > 0.0:
				draw_rect(Rect2(o2 + Vector2(x, y) * cell, Vector2(cell, cell)), fill)
	var rows: Array = Art.GLYPHS.get(grade, Art.GLYPHS["C"])
	var gs: float = 2.0
	var gx0: float = roundf(c.x - 5.0 * gs * 0.5)
	var gy0: float = roundf(c.y - 7.0 * gs * 0.5)
	var grow_cells: float = 1.0
	for gy in range(7):
		var row: String = rows[gy]
		for gx in range(5):
			if row[gx] == "X":
				var r := Rect2(o2 + Vector2(gx0 + gx * gs, gy0 + gy * gs) * cell, Vector2(gs, gs) * cell)
				draw_rect(r.grow(cell * grow_cells), Art.OUTLINE)
	for gy in range(7):
		var row2: String = rows[gy]
		for gx in range(5):
			if row2[gx] == "X":
				draw_rect(Rect2(o2 + Vector2(gx0 + gx * gs, gy0 + gy * gs) * cell, Vector2(gs, gs) * cell), col)
	# paw-print pips on the band (chunky: 2x2 cells)
	var pip: float = 2.0 if Art.chunky() else 1.0
	for k in range(4):
		var a: float = -PI * 0.5 + TAU * float(k) / 4.0 + PI / 4.0
		var pp: Vector2 = (c + Vector2(cos(a), sin(a)) * (r_band - 1.0 - (0.5 if Art.chunky() else 0.0))).floor()
		draw_rect(Rect2(o2 + (pp - Vector2(pip - 1.0, pip - 1.0) * 0.5).floor() * cell, Vector2(pip, pip) * cell), Art.CREAM)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
