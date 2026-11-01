extends RefCounted

## TRACE path pool for the cooking minigame (no class_name; preload by path).
##   const TracePaths = preload("res://Scripts/minigame/cooking/TracePaths.gd")
##   var path: Dictionary = TracePaths.build("cat_face", Vector2(136, 100), 36.0)
##
## Each shape is ONE continuous stroke described by control points in unit space (-1..1, y down).
## Control points are either smooth (Catmull-Rom handles) or sharp corners (no handles), turned
## into a Curve2D and baked at ~1 art px. build() returns:
##   {name, curve: Curve2D, points: PackedVector2Array (baked, art px), cum: PackedFloat32Array
##    (arc length at each point), length: float, closed: bool, split: float (0..1 arc fraction
##    where a two-tone path switches from ink to ink2; 1.0 = single tone)}
##
## Pool ids: cat_face, paw, fish, loaf, heart, bow_tie, bow_tie_two_tone, spiral, swirl, circle,
## zigzag. "heart" and "bow_tie_two_tone" are not in RecipeDefinition.schema.json's path_pool
## enum yet (bow_tie + params.ink2 gives the same two-tone bow tie today).

const SHAPES: Array[String] = [
	"cat_face", "paw", "fish", "loaf", "heart", "bow_tie", "bow_tie_two_tone",
	"spiral", "swirl", "circle", "zigzag",
]

const S := true   # sharp corner marker
const C := false  # smooth point marker


static func has_shape(shape: String) -> bool:
	return SHAPES.has(shape)


## Control points as [[Vector2, sharp], ...] plus closed flag and two-tone split.
static func control_points(shape: String) -> Dictionary:
	match shape:
		"circle":
			var pts: Array = []
			for i in range(12):
				var a: float = -PI * 0.5 + float(i) * TAU / 12.0
				pts.append([Vector2(cos(a), sin(a)) * 0.92, C])
			return {"pts": pts, "closed": true}
		"heart":
			return {"closed": true, "pts": [
				[Vector2(0.0, 0.9), S], [Vector2(-0.5, 0.42), C], [Vector2(-0.88, -0.08), C],
				[Vector2(-0.78, -0.6), C], [Vector2(-0.36, -0.74), C], [Vector2(0.0, -0.38), S],
				[Vector2(0.36, -0.74), C], [Vector2(0.78, -0.6), C], [Vector2(0.88, -0.08), C],
				[Vector2(0.5, 0.42), C],
			]}
		"cat_face":
			return {"closed": true, "pts": [
				[Vector2(0.0, 0.86), C], [Vector2(-0.56, 0.74), C], [Vector2(-0.88, 0.32), C],
				[Vector2(-0.86, -0.16), C], [Vector2(-0.72, -0.42), S], [Vector2(-0.62, -0.96), S],
				[Vector2(-0.24, -0.6), S], [Vector2(0.0, -0.64), C], [Vector2(0.24, -0.6), S],
				[Vector2(0.62, -0.96), S], [Vector2(0.72, -0.42), S], [Vector2(0.86, -0.16), C],
				[Vector2(0.88, 0.32), C], [Vector2(0.56, 0.74), C],
			]}
		"paw":
			return {"closed": true, "pts": [
				[Vector2(0.0, 0.9), C], [Vector2(-0.52, 0.8), C], [Vector2(-0.74, 0.44), C],
				[Vector2(-0.56, 0.16), S], [Vector2(-0.94, -0.02), C], [Vector2(-0.86, -0.4), C],
				[Vector2(-0.48, -0.36), S], [Vector2(-0.54, -0.76), C], [Vector2(-0.2, -0.92), C],
				[Vector2(0.0, -0.52), S], [Vector2(0.2, -0.92), C], [Vector2(0.54, -0.76), C],
				[Vector2(0.48, -0.36), S], [Vector2(0.86, -0.4), C], [Vector2(0.94, -0.02), C],
				[Vector2(0.56, 0.16), S], [Vector2(0.74, 0.44), C], [Vector2(0.52, 0.8), C],
			]}
		"loaf":
			return {"closed": true, "pts": [
				[Vector2(-0.9, 0.66), S], [Vector2(0.0, 0.7), C], [Vector2(0.9, 0.66), S],
				[Vector2(0.96, 0.12), C], [Vector2(0.78, -0.3), C], [Vector2(0.58, -0.42), S],
				[Vector2(0.48, -0.86), S], [Vector2(0.24, -0.52), S], [Vector2(0.0, -0.56), C],
				[Vector2(-0.24, -0.52), S], [Vector2(-0.48, -0.86), S], [Vector2(-0.58, -0.42), S],
				[Vector2(-0.78, -0.3), C], [Vector2(-0.96, 0.12), C],
			]}
		"fish":
			return {"closed": true, "pts": [
				[Vector2(-0.96, 0.0), C], [Vector2(-0.56, -0.48), C], [Vector2(0.02, -0.54), C],
				[Vector2(0.46, -0.16), S], [Vector2(0.94, -0.58), S], [Vector2(0.78, 0.0), S],
				[Vector2(0.94, 0.58), S], [Vector2(0.46, 0.16), S], [Vector2(0.02, 0.54), C],
				[Vector2(-0.56, 0.48), C],
			]}
		"bow_tie", "bow_tie_two_tone":
			# Figure-8 from the knot: left wing, back through the knot, right wing.
			return {"closed": true, "split": 0.5, "pts": [
				[Vector2(0.0, 0.0), S], [Vector2(-0.34, -0.2), C], [Vector2(-0.92, -0.56), S],
				[Vector2(-0.98, 0.0), C], [Vector2(-0.92, 0.56), S], [Vector2(-0.34, 0.2), C],
				[Vector2(0.0, 0.0), S], [Vector2(0.34, -0.2), C], [Vector2(0.92, -0.56), S],
				[Vector2(0.98, 0.0), C], [Vector2(0.92, 0.56), S], [Vector2(0.34, 0.2), C],
			]}
		"spiral":
			# Honey spiral: from the centre outwards, 2.25 turns.
			var sp: Array = []
			var n: int = 28
			for i in range(n):
				var t: float = float(i) / float(n - 1)
				var a: float = -PI * 0.5 + t * TAU * 2.25
				sp.append([Vector2(cos(a), sin(a)) * lerpf(0.1, 0.94, t), C])
			return {"pts": sp, "closed": false}
		"swirl":
			# Cream swirl: from the rim inwards, 1.6 turns, ending in a little curl.
			var sw: Array = []
			var m: int = 22
			for i in range(m):
				var t2: float = float(i) / float(m - 1)
				var a2: float = PI + t2 * TAU * 1.6
				sw.append([Vector2(cos(a2), sin(a2)) * lerpf(0.94, 0.24, t2), C])
			return {"pts": sw, "closed": false}
		"zigzag":
			# Syrup drizzle: soft zigzag left to right.
			var zz: Array = []
			var peaks: int = 7
			for i in range(peaks):
				var x: float = lerpf(-0.94, 0.94, float(i) / float(peaks - 1))
				zz.append([Vector2(x, -0.5 if i % 2 == 0 else 0.5), C])
			return {"pts": zz, "closed": false}
	return {}


## Builds the baked path for `shape` centred on `center` with half-extent `half` art px.
## Unknown shapes fall back to "paw".
static func build(shape: String, center: Vector2, half: float) -> Dictionary:
	var name: String = shape if has_shape(shape) else "paw"
	var cp: Dictionary = control_points(name)
	var pts: Array = cp.get("pts", [])
	var closed: bool = bool(cp.get("closed", false))
	var curve := Curve2D.new()
	curve.bake_interval = 1.0
	var n: int = pts.size()
	for i in range(n):
		var p: Vector2 = center + (pts[i][0] as Vector2) * half
		var sharp: bool = bool(pts[i][1])
		var h := Vector2.ZERO
		if not sharp:
			var has_prev: bool = closed or i > 0
			var has_next: bool = closed or i < n - 1
			var prev: Vector2 = center + (pts[(i - 1 + n) % n][0] as Vector2) * half if has_prev else p
			var nxt: Vector2 = center + (pts[(i + 1) % n][0] as Vector2) * half if has_next else p
			h = (nxt - prev) / 6.0
		curve.add_point(p, -h, h)
	if closed and n > 0:
		curve.add_point(center + (pts[0][0] as Vector2) * half, Vector2.ZERO, Vector2.ZERO)
		# Smooth closing point: reuse the first point's handles.
		if not bool(pts[0][1]):
			var h0: Vector2 = curve.get_point_out(0)
			curve.set_point_in(n, -h0)
	var baked: PackedVector2Array = curve.get_baked_points()
	var cum := PackedFloat32Array()
	cum.resize(baked.size())
	var total: float = 0.0
	for i in range(baked.size()):
		if i > 0:
			total += baked[i].distance_to(baked[i - 1])
		cum[i] = total
	return {
		"name": name,
		"curve": curve,
		"points": baked,
		"cum": cum,
		"length": total,
		"closed": closed,
		"split": float(cp.get("split", 1.0)) if name.begins_with("bow_tie") else 1.0,
	}


## Point on the baked path at arc length `s` (clamped).
static func point_at(path: Dictionary, s: float) -> Vector2:
	var pts: PackedVector2Array = path["points"]
	var cum: PackedFloat32Array = path["cum"]
	if pts.is_empty():
		return Vector2.ZERO
	if s <= 0.0:
		return pts[0]
	var total: float = float(path["length"])
	if s >= total:
		return pts[pts.size() - 1]
	var lo: int = 0
	var hi: int = cum.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg: float = cum[hi] - cum[lo]
	if seg <= 0.0001:
		return pts[lo]
	return pts[lo].lerp(pts[hi], (s - cum[lo]) / seg)


## Unit tangent of the path at arc length `s`.
static func tangent_at(path: Dictionary, s: float) -> Vector2:
	var a: Vector2 = point_at(path, s - 1.5)
	var b: Vector2 = point_at(path, s + 1.5)
	var d: Vector2 = b - a
	return d.normalized() if d.length() > 0.0001 else Vector2.RIGHT


## Nearest point on the path to `p`: {point, dist, s (arc length), index (segment start)}.
static func nearest(path: Dictionary, p: Vector2) -> Dictionary:
	var pts: PackedVector2Array = path["points"]
	var cum: PackedFloat32Array = path["cum"]
	var best_d: float = INF
	var best_p: Vector2 = p
	var best_s: float = 0.0
	var best_i: int = 0
	if pts.size() == 1:
		return {"point": pts[0], "dist": p.distance_to(pts[0]), "s": 0.0, "index": 0}
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab: Vector2 = b - a
		var l2: float = ab.length_squared()
		var t: float = 0.0 if l2 <= 0.000001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q: Vector2 = a + ab * t
		var d: float = p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_p = q
			best_s = cum[i] + (cum[i + 1] - cum[i]) * t
			best_i = i
	return {"point": best_p, "dist": sqrt(best_d), "s": best_s, "index": best_i}
