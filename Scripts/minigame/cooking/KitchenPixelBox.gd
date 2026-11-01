extends StyleBox

## Station Kitchen pixel panel for art styles B-F (same definition as Counter Cats cc_pixel_box.gd): crisp stepped corners (no
## anti-aliasing), warm dark outline, optional inner colour band (the old oak
## border), rim light, cel shade, cream sticker halo and cocoa drop shadow.
## Style A never uses this (it keeps the original StyleBoxFlat panels).

const OUTLINE := Color("#4A3426")
const CREAM := Color("#FFF6EA")
const SHADOW := Color(0.169, 0.129, 0.161, 0.35)

var bg: Color = CREAM
var band: Color = Color(0, 0, 0, 0)
var band_w: int = 0
var outline_w: int = 3
var radius: int = 9
var step: int = 3
var rim: bool = false
var cel: bool = false
var halo: int = 0
var shadow: int = 0

func _draw(ci: RID, rect: Rect2) -> void:
	var r := Rect2(rect.position.round(), rect.size.round())
	if shadow > 0:
		_shape(ci, Rect2(r.position + Vector2(shadow, shadow), r.size), radius, SHADOW)
	if halo > 0:
		_shape(ci, r.grow(halo), radius + halo, CREAM)
	_shape(ci, r, radius, OUTLINE)
	var inner: Rect2 = r.grow(-outline_w)
	var rad: int = maxi(0, radius - outline_w)
	if band_w > 0 and band.a > 0.0:
		_shape(ci, inner, rad, band)
		inner = inner.grow(-band_w)
		rad = maxi(0, rad - band_w)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return
	if cel:
		_shape(ci, inner, rad, bg.darkened(0.08))
		var sh: float = clampf(roundf(inner.size.y * 0.2), 2.0, 6.0)
		_shape(ci, inner, rad, bg, 0.0, inner.size.y - sh)
	else:
		_shape(ci, inner, rad, bg)
	if rim:
		var rw: float = 2.0
		_shape(ci, inner, rad, bg.lightened(0.55), 0.0, rw)
		for band_r in _rows(inner, rad):
			var br: Rect2 = band_r
			if br.position.y >= inner.position.y + rw and br.end.y <= inner.end.y - rad:
				RenderingServer.canvas_item_add_rect(ci, Rect2(br.position.x, br.position.y, rw, br.size.y), bg.lightened(0.55))

## Row rectangles of a stepped rounded rect.
func _rows(r: Rect2, rad: int) -> Array:
	var out: Array = []
	var s: float = float(maxi(1, step))
	var n: int = int(ceil(float(rad) / s))
	n = mini(n, int(floor(r.size.y / (2.0 * s))))
	for i in range(n):
		var dy: float = float(rad) - (float(i) + 0.5) * s
		var inset: float = roundf(float(rad) - sqrt(maxf(0.0, float(rad * rad) - dy * dy)))
		inset = minf(inset, r.size.x * 0.5)
		out.append(Rect2(r.position.x + inset, r.position.y + i * s, r.size.x - inset * 2.0, s))
		out.append(Rect2(r.position.x + inset, r.end.y - (i + 1) * s, r.size.x - inset * 2.0, s))
	out.append(Rect2(r.position.x, r.position.y + n * s, r.size.x, r.size.y - 2.0 * n * s))
	return out

## Fill the shape, optionally clipped to local rows [y0, y1).
func _shape(ci: RID, r: Rect2, rad: int, col: Color, y0: float = 0.0, y1: float = INF) -> void:
	var top: float = r.position.y + y0
	var bot: float = r.position.y + minf(y1, r.size.y)
	for q in _rows(r, rad):
		var a: Rect2 = q
		var t: float = maxf(a.position.y, top)
		var b: float = minf(a.end.y, bot)
		if b > t and a.size.x > 0.0:
			RenderingServer.canvas_item_add_rect(ci, Rect2(a.position.x, t, a.size.x, b - t), col)
