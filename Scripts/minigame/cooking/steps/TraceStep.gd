extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## TRACE verb: hold and drag along a dotted Curve2D path (latte art, drizzle, cream swirl).
## Contract + params: Docs/MINIGAMES.md ("trace"). Shapes: Scripts/minigame/cooking/TracePaths.gd.
##
## Scoring (design 2.4): accuracy = 1 - mean(screen-space distance) / tolerance, where
##   screen px = art px x _play_scale and tolerance = tolerance_px (14) x window_scale().
##   Distance samples are taken every ~1 art px of pen travel while the pen is down, so a pen
##   held still does not weigh more than a moving one. Coverage = fraction of the baked path
##   that the pen passed within cover radius; coverage < min_coverage caps at coverage_cap.
##   Floor ACC_FLOOR (the dish is never ruined).
## Timing: the time_sec x time_scale() budget starts at the first pen-down (or after an idle
##   grace). The trace ends on: time out, coverage >= COMPLETE_COVERAGE, or lifting the pen
##   with coverage >= LIFT_FINISH_COVERAGE.
## Mouse: LMB hold + drag (hold_to_toggle: tap to start / tap to stop). Magnet assist (option
##   params.magnet, or context.settings.trace_magnet / magnet on the owning game): pen points
##   within MAGNET_SCREEN_PX of the path snap onto it.
## Keyboard: hold Space -> an auto-pen runs along the path while a gentle drift pushes it off;
##   steer back with arrows/WASD (the component across the path is used). Magnet always on.
## The player's line is drawn in the recipe ink (two-tone: ink then ink2 at the path split) on
##   the canvas colour; extra.art carries the normalized strokes so the serve dish can show it.

signal sfx(id: String) ## Sound hooks: "pen_down", "pen_up", "complete", "pop".

const TracePaths = preload("res://Scripts/minigame/cooking/TracePaths.gd")

const MAGNET_SCREEN_PX := 10.0
const KB_STEER_SPEED := 34.0      ## art px / s across the path
const KB_DRIFT_SPEED := 9.0       ## art px / s (divided by time_scale)
const KB_MAX_OFF := 12.0          ## art px
const KB_RUN_FRACTION := 0.72     ## auto-pen finishes the path in this share of the time budget
const IDLE_GRACE_SEC := 3.0
const COMPLETE_COVERAGE := 0.985
const LIFT_FINISH_COVERAGE := 0.9
const ACC_FLOOR := 0.25
const POP_SEC := 0.5
const PATH_HALF := 36.0
const CUP_R := 48.0

var shape: String = "paw"
var path: Dictionary = {}
var magnet: bool = false
var tolerance_screen: float = 14.0
var cover_r: float = 4.0
var time_limit: float = 4.5
var min_coverage: float = 0.8
var coverage_cap: float = 0.6

var ink: Color = PixelDraw.MILK
var ink2: Color = PixelDraw.MILK
var canvas: Color = PixelDraw.COFFEE
var two_tone: bool = false

var center: Vector2 = Vector2(136, 102)
var covered: PackedByteArray = PackedByteArray()
var covered_count: int = 0
var strokes: Array = []          ## finished strokes: [{pts: PackedVector2Array, cols: PackedColorArray}]
var cur_pts: PackedVector2Array = PackedVector2Array()   ## stroke being drawn
var cur_cols: PackedColorArray = PackedColorArray()
var pen: Vector2 = Vector2.ZERO
var pen_down: bool = false
var pen_mode: String = ""        ## "mouse" | "kb"
var used_keyboard: bool = false
var draw_started: bool = false
var draw_t: float = 0.0
var dist_sum: float = 0.0        ## screen px x art-px weight
var dist_w: float = 0.0
var result_acc: float = -1.0

var kb_s: float = 0.0
var kb_off: float = 0.0
var _kb_drift: float = 0.0
var _kb_drift_t: float = 0.0
var _pop_t: float = -1.0
var _anim_t: float = 0.0
var _last_raw: Vector2 = Vector2.ZERO
var _has_last: bool = false


func _on_start() -> void:
	var sr: Rect2 = safe_rect()
	center = Vector2(roundf(sr.get_center().x), 102.0)
	shape = String(roll("shape", _first_pool_shape()))
	if String(params.get("shape", "")) != "":
		shape = String(params["shape"])
	if shape == "bow_tie_two_tone":
		two_tone = true
	path = TracePaths.build(shape, center, PATH_HALF)
	shape = String(path["name"])
	var n: int = (path["points"] as PackedVector2Array).size()
	covered = PackedByteArray()
	covered.resize(n)
	covered.fill(0)
	covered_count = 0
	ink = _color_param("ink", PixelDraw.MILK)
	canvas = _color_param("canvas", PixelDraw.COFFEE)
	if params.has("ink2"):
		ink2 = _color_param("ink2", ink)
		two_tone = true
	elif two_tone:
		ink2 = PixelDraw.OUTLINE
	else:
		ink2 = ink
	tolerance_screen = maxf(float(params.get("tolerance_px", 14.0)) * window_scale(), 1.0)
	cover_r = maxf(tolerance_screen / float(maxi(play_scale(), 1)), 3.0)
	time_limit = maxf(float(params.get("time_sec", 4.5)) * time_scale(), 0.5)
	min_coverage = float(params.get("min_coverage", 0.8))
	coverage_cap = float(params.get("coverage_cap", 0.6))
	magnet = _resolve_magnet()
	_kb_drift_t = 0.0
	pen = TracePaths.point_at(path, 0.0)
	extra = {"shape": shape}


func _first_pool_shape() -> String:
	var pool: Variant = params.get("path_pool", ["paw"])
	if pool is Array and not (pool as Array).is_empty():
		return String((pool as Array)[0])
	return "paw"


func _color_param(key: String, fallback: Color) -> Color:
	var v: Variant = params.get(key, null)
	if v is Color:
		return v
	if v is String and Color.html_is_valid(String(v)):
		return Color.html(String(v))
	return fallback


## Magnet option: params.magnet, else the owning game's context.settings (trace_magnet/magnet).
func _resolve_magnet() -> bool:
	if params.has("magnet"):
		return bool(params["magnet"])
	var n: Node = get_parent()
	while n != null:
		var c: Variant = n.get("context")
		if c is Dictionary:
			var st: Variant = (c as Dictionary).get("settings", {})
			if st is Dictionary:
				var sd: Dictionary = st
				return bool(sd.get("trace_magnet", sd.get("magnet", false)))
			return false
		n = n.get_parent()
	return false


# --- Public read-outs (probe / HUD) ---------------------------------------------------------

func coverage() -> float:
	var n: int = covered.size()
	return float(covered_count) / float(n) if n > 0 else 0.0


func mean_screen_distance() -> float:
	return dist_sum / dist_w if dist_w > 0.0 else tolerance_screen


func time_left() -> float:
	return maxf(time_limit - draw_t, 0.0)


## The accuracy the trace would score if it ended now.
func current_accuracy() -> float:
	if dist_w <= 0.0:
		return ACC_FLOOR
	var acc: float = clampf(1.0 - mean_screen_distance() / tolerance_screen, 0.0, 1.0)
	if coverage() < min_coverage:
		acc = minf(acc, coverage_cap)
	return maxf(acc, ACC_FLOOR)


## Where the keyboard auto-pen wants to be (on the path).
func kb_target() -> Vector2:
	return TracePaths.point_at(path, kb_s)


func kb_normal() -> Vector2:
	return TracePaths.tangent_at(path, kb_s).orthogonal()


# --- Input ----------------------------------------------------------------------------------

func _on_hold_begin(play_pos: Vector2, from_mouse: bool) -> void:
	if not is_running():
		return
	draw_started = true
	pen_down = true
	_has_last = false
	_end_stroke()
	if from_mouse:
		pen_mode = "mouse"
		_add_pen_point(_local(play_pos))
	else:
		pen_mode = "kb"
		used_keyboard = true
		kb_s = _first_uncovered_s()
		_add_pen_point(kb_target() + kb_normal() * kb_off)
	sfx.emit("pen_down")
	get_viewport().set_input_as_handled()
	queue_redraw()


func _on_hold_end(_play_pos: Vector2) -> void:
	if not pen_down:
		return
	pen_down = false
	_has_last = false
	_end_stroke()
	sfx.emit("pen_up")
	if is_running() and coverage() >= LIFT_FINISH_COVERAGE:
		_complete()
	queue_redraw()


func _on_pointer_moved(play_pos: Vector2) -> void:
	if not is_running():
		return
	var lp: Vector2 = _local(play_pos)
	if pen_down and pen_mode == "mouse":
		_add_pen_point(lp)
		get_viewport().set_input_as_handled()
		if coverage() >= COMPLETE_COVERAGE:
			_complete()
	elif not pen_down:
		pen = lp
	queue_redraw()


func _local(play_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * play_pos


func _first_uncovered_s() -> float:
	var cum: PackedFloat32Array = path["cum"]
	for i in range(covered.size()):
		if covered[i] == 0:
			return maxf(cum[i] - 2.0, 0.0)
	return float(path["length"])


# --- Pen sampling ---------------------------------------------------------------------------

## Adds a pen point (art px, local): magnet snap, ~1 px sub-samples for distance + coverage,
## and the drawn ink.
func _add_pen_point(raw: Vector2) -> void:
	var ps: float = float(maxi(play_scale(), 1))
	var use_magnet: bool = magnet or pen_mode == "kb"
	var p: Vector2 = raw
	if use_magnet:
		var nm: Dictionary = TracePaths.nearest(path, raw)
		if float(nm["dist"]) * ps <= MAGNET_SCREEN_PX:
			p = nm["point"]
	if not _has_last:
		_has_last = true
		_last_raw = p
		_sample(p, 0.0)
		pen = p
		return
	var seg: float = _last_raw.distance_to(p)
	if seg < 0.25:
		return
	var steps: int = maxi(1, int(ceilf(seg)))
	var step_len: float = seg / float(steps)
	for k in range(1, steps + 1):
		var q: Vector2 = _last_raw.lerp(p, float(k) / float(steps))
		if use_magnet:
			var nq: Dictionary = TracePaths.nearest(path, q)
			if float(nq["dist"]) * ps <= MAGNET_SCREEN_PX:
				q = nq["point"]
		_sample(q, step_len)
	_last_raw = p
	pen = p


func _sample(q: Vector2, weight: float) -> void:
	var near: Dictionary = TracePaths.nearest(path, q)
	var d_art: float = float(near["dist"])
	if weight > 0.0:
		dist_sum += d_art * float(maxi(play_scale(), 1)) * weight
		dist_w += weight
	# Coverage: every baked point within cover_r of the pen.
	var pts: PackedVector2Array = path["points"]
	var r2: float = cover_r * cover_r
	for i in range(pts.size()):
		if covered[i] == 0 and pts[i].distance_squared_to(q) <= r2:
			covered[i] = 1
			covered_count += 1
	# Ink.
	var col: Color = ink
	if two_tone:
		var frac: float = float(near["s"]) / maxf(float(path["length"]), 0.001)
		col = ink if frac < float(path["split"]) else ink2
	cur_pts.append(q)
	cur_cols.append(col)


## Moves the stroke being drawn into `strokes`.
func _end_stroke() -> void:
	if not cur_pts.is_empty():
		strokes.append({"pts": cur_pts, "cols": cur_cols})
	cur_pts = PackedVector2Array()
	cur_cols = PackedColorArray()


# --- Frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_anim_t += delta
	if _pop_t >= 0.0:
		_pop_t += delta
		queue_redraw()
	if not is_running():
		return
	if not draw_started and elapsed >= IDLE_GRACE_SEC * time_scale():
		draw_started = true
	if draw_started:
		draw_t += delta
	if pen_down and pen_mode == "kb":
		_kb_tick(delta)
	if is_running() and draw_started and draw_t >= time_limit:
		_complete()
	queue_redraw()


func _kb_tick(delta: float) -> void:
	_kb_drift_t -= delta
	if _kb_drift_t <= 0.0:
		var sgn: float = -1.0 if rng.randf() < 0.5 else 1.0
		_kb_drift = sgn * rng.randf_range(0.6, 1.0) * KB_DRIFT_SPEED / time_scale()
		_kb_drift_t = rng.randf_range(0.5, 1.1)
	var total: float = float(path["length"])
	var speed: float = total / maxf(time_limit * KB_RUN_FRACTION, 0.1)
	kb_s = minf(kb_s + speed * delta, total)
	var nrm: Vector2 = kb_normal()
	var steer: float = steer_input().dot(nrm)
	kb_off = clampf(kb_off + (_kb_drift + steer * KB_STEER_SPEED) * delta, -KB_MAX_OFF, KB_MAX_OFF)
	_add_pen_point(kb_target() + nrm * kb_off)
	if kb_s >= total - 0.01 or coverage() >= COMPLETE_COVERAGE:
		_complete()


## Keyboard steering direction (arrows / WASD). Separate so tests can see what is read.
func steer_input() -> Vector2:
	return nudge_vector()


func _complete() -> void:
	if not is_running():
		return
	pen_down = false
	_end_stroke()
	result_acc = current_accuracy()
	extra = {
		"shape": shape,
		"coverage": snappedf(coverage(), 0.001),
		"mean_px": snappedf(mean_screen_distance(), 0.01),
		"magnet": magnet,
		"keyboard": used_keyboard,
		"ink": ink.to_html(false),
		"ink2": ink2.to_html(false),
		"canvas": canvas.to_html(false),
		"art": _normalized_art(),
	}
	_pop_t = 0.0 if not reduced_motion() else -1.0
	sfx.emit("complete")
	sfx.emit("pop")
	finish(result_acc)
	queue_redraw()


## Strokes downsampled and normalized to the shape box (-1..1) so another renderer can redraw
## the player's art at any size: [{pts: PackedVector2Array, ink2: bool}].
func _normalized_art() -> Array:
	var out: Array = []
	for st in strokes:
		var pts: PackedVector2Array = st["pts"]
		var cols: PackedColorArray = st["cols"]
		if pts.size() < 2:
			continue
		var np := PackedVector2Array()
		var i: int = 0
		var tone2: bool = false
		while i < pts.size():
			np.append(((pts[i] - center) / PATH_HALF).snapped(Vector2(0.01, 0.01)))
			tone2 = tone2 or (two_tone and cols[i] == ink2 and ink2 != ink)
			i += 3
		out.append({"pts": np, "ink2": tone2})
	return out


# --- Drawing --------------------------------------------------------------------------------

func _draw() -> void:
	if path.is_empty():
		return
	_draw_side_panels()
	_draw_cup()
	_draw_guide()
	_draw_ink()
	if is_running():
		_draw_markers()
		_draw_pen()
	else:
		_draw_finish_touches()
	_draw_timer_ring()
	_draw_coverage_bar()
	if _pop_t >= 0.0 and _pop_t <= POP_SEC:
		_draw_pop()


func _draw_cup() -> void:
	PixelDraw.shadow(self, center + Vector2(0, CUP_R + 8), CUP_R + 4, 3)
	PixelDraw.circle(self, center, CUP_R + 8, PixelDraw.CREAM)            # saucer
	PixelDraw.disc(self, center + Vector2(0, 2), CUP_R + 3, PixelDraw.CREAM_DARK)
	PixelDraw.circle(self, center, CUP_R + 2, PixelDraw.OAK)               # cup rim
	PixelDraw.circle(self, center, CUP_R - 1, canvas)                      # foam / plate
	# a soft highlight crescent on the canvas
	PixelDraw.ring(self, center, CUP_R - 4, 1.0, Color(PixelDraw.CREAM, 0.18), PI * 1.1, PI * 1.45)


func _guide_color() -> Color:
	return Color(PixelDraw.CREAM, 0.85) if canvas.get_luminance() < 0.5 else Color(PixelDraw.OUTLINE, 0.55)


func _draw_guide() -> void:
	var pts: PackedVector2Array = path["points"]
	var cum: PackedFloat32Array = path["cum"]
	var col: Color = _guide_color()
	var next_s: float = 0.0
	for i in range(pts.size()):
		if cum[i] < next_s:
			continue
		next_s = cum[i] + 5.0
		if covered[i] != 0:
			continue
		var p: Vector2 = PixelDraw.snap(pts[i])
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), col, true)


func _draw_ink() -> void:
	var all: Array = strokes.duplicate()
	if not cur_pts.is_empty():
		all.append({"pts": cur_pts, "cols": cur_cols})
	for st in all:
		var pts: PackedVector2Array = st["pts"]
		var cols: PackedColorArray = st["cols"]
		# Pixel brush: a 2x2 dab per ~1 px sample (crisp; no polyline joint spikes).
		var last := Vector2(-999, -999)
		for i in range(pts.size()):
			var q: Vector2 = PixelDraw.snap(pts[i])
			if q == last:
				continue
			last = q
			draw_rect(Rect2(q - Vector2(1, 1), Vector2(2, 2)), cols[i], true)


func _draw_markers() -> void:
	var start: Vector2 = TracePaths.point_at(path, 0.0)
	var dir: Vector2 = TracePaths.tangent_at(path, 4.0)
	var pulse: float = 0.0 if reduced_motion() else roundf(sin(_anim_t * 6.0) * 1.0 + 1.0)
	if covered_count == 0:
		PixelDraw.ring(self, start, 5.0 + pulse, 1.0, PixelDraw.HONEY)
	PixelDraw.circle(self, start, 3, PixelDraw.SAGE)
	# Direction chevron a few px along the path.
	var tip: Vector2 = TracePaths.point_at(path, 11.0)
	var nrm: Vector2 = dir.orthogonal()
	var a: Vector2 = tip - dir * 3.0 + nrm * 3.0
	var b: Vector2 = tip - dir * 3.0 - nrm * 3.0
	draw_colored_polygon(PackedVector2Array([PixelDraw.snap(tip + dir * 2.0), PixelDraw.snap(a), PixelDraw.snap(b)]), PixelDraw.HONEY)
	if not bool(path["closed"]):
		var endp: Vector2 = TracePaths.point_at(path, float(path["length"]))
		PixelDraw.star(self, endp, 4, PixelDraw.HONEY_LIGHT)


func _draw_pen() -> void:
	if pen_mode == "kb" and pen_down:
		PixelDraw.ring(self, kb_target(), 4.0, 1.0, PixelDraw.SAGE)
	if pen_down or pen_mode == "kb":
		# Little milk-jug nib: honey ring with a dark centre pixel.
		PixelDraw.ring(self, pen, 3.0, 1.0, PixelDraw.HONEY)
		PixelDraw.px(self, Rect2(PixelDraw.snap(pen), Vector2(1, 1)), PixelDraw.OUTLINE)


func _draw_finish_touches() -> void:
	if result_acc < 0.6:
		return
	var c: Color = ink2 if two_tone else ink
	match shape:
		"cat_face":
			PixelDraw.disc(self, center + Vector2(-13, -2), 2.5, c)
			PixelDraw.disc(self, center + Vector2(13, -2), 2.5, c)
			draw_colored_polygon(PackedVector2Array([center + Vector2(-3, 7), center + Vector2(3, 7), center + Vector2(0, 10)]), c)
		"loaf":
			PixelDraw.line(self, center + Vector2(-14, -2), center + Vector2(-10, -4), c)
			PixelDraw.line(self, center + Vector2(-10, -4), center + Vector2(-6, -2), c)
			PixelDraw.line(self, center + Vector2(6, -2), center + Vector2(10, -4), c)
			PixelDraw.line(self, center + Vector2(10, -4), center + Vector2(14, -2), c)
		"fish":
			PixelDraw.disc(self, center + Vector2(-20, -4), 2.0, c)
		"bow_tie", "bow_tie_two_tone":
			PixelDraw.circle(self, center, 4, ink2 if two_tone else ink)


func _draw_timer_ring() -> void:
	# Pastry-clock ring around the saucer: sage while plenty of time, honey near the end.
	var frac: float = 1.0 - clampf(draw_t / time_limit, 0.0, 1.0) if draw_started else 1.0
	var col: Color = PixelDraw.SAGE if frac > 0.3 else PixelDraw.HONEY
	PixelDraw.ring(self, center, CUP_R + 11, 3.0, PixelDraw.CREAM_DARK)
	if frac > 0.0:
		PixelDraw.ring(self, center, CUP_R + 11, 3.0, col, -PI * 0.5, -PI * 0.5 + TAU * frac)


func _draw_coverage_bar() -> void:
	var sr: Rect2 = safe_rect()
	var x: float = center.x + CUP_R + 20
	var avail: float = sr.end.x - x
	var bar := Rect2(x + avail * 0.5 - 5, 70, 10, 74)
	if avail < 16:
		return
	var inner: Rect2 = PixelDraw.meter(self, bar, coverage(), PixelDraw.SAGE, PixelDraw.CREAM_DARK, PixelDraw.OUTLINE, true)
	# min_coverage notch: a star notch, not just colour.
	var ny: float = roundf(inner.end.y - inner.size.y * min_coverage)
	PixelDraw.px(self, Rect2(inner.position.x - 2, ny, inner.size.x + 4, 1), PixelDraw.OUTLINE)
	PixelDraw.star(self, Vector2(bar.end.x + 5, ny), 3, PixelDraw.HONEY_LIGHT if coverage() >= min_coverage else PixelDraw.CREAM)
	PixelDraw.paw(self, Vector2(bar.get_center().x, bar.end.y + 7), 4, PixelDraw.OAK_DARK)
	var pct: String = "%d%%" % int(roundf(coverage() * 100.0))
	PixelDraw.text(self, Vector2(bar.get_center().x - PixelDraw.text_width("art") * 0.5, bar.position.y - 13), "art", PixelDraw.OUTLINE, 8)
	PixelDraw.text(self, Vector2(bar.get_center().x - PixelDraw.text_width(pct) * 0.5, bar.position.y - 3), pct, PixelDraw.OUTLINE, 8)


func _draw_side_panels() -> void:
	var sr: Rect2 = safe_rect()
	var left_w: float = center.x - CUP_R - 14 - sr.position.x
	if left_w < 40:
		return
	var px: float = sr.position.x + 2
	var col: Color = PixelDraw.OUTLINE
	var card := Rect2(px, 62, minf(left_w - 4, 64 if PixelDraw.legacy() else 78), 78)
	PixelDraw.rounded_rect(self, card, 3, PixelDraw.CREAM)
	PixelDraw.text(self, card.position + Vector2(4, 11), _shape_label(), col, 8)
	PixelDraw.px(self, Rect2(card.position.x + 3, card.position.y + 15, card.size.x - 6, 1), PixelDraw.CREAM_DARK)
	# mouse glyph
	var m := Rect2(card.position.x + 5, card.position.y + 20, 7, 10)
	PixelDraw.rounded_rect(self, m, 2, PixelDraw.CREAM_DARK)
	draw_rect(Rect2(m.position.x + 1, m.position.y + 1, 2, 3), PixelDraw.HONEY, true)
	PixelDraw.text(self, card.position + Vector2(15, 29), "hold+drag", col, 8)
	# space glyph
	var sp := Rect2(card.position.x + 4, card.position.y + 37, 14, 7)
	PixelDraw.rounded_rect(self, sp, 1, PixelDraw.CREAM_DARK)
	PixelDraw.text(self, card.position + Vector2(21, 44), "auto-pen", col, 8)
	# Arrow-key glyphs (pixel arrows, not ASCII) + "steer".
	var ay: float = card.position.y + 50
	var ax: float = card.position.x + 4
	_arrow_icon(Vector2(ax, ay + 3), Vector2.LEFT, col)
	_arrow_icon(Vector2(ax + 6, ay), Vector2.UP, col)
	_arrow_icon(Vector2(ax + 6, ay + 6), Vector2.DOWN, col)
	_arrow_icon(Vector2(ax + 12, ay + 3), Vector2.RIGHT, col)
	PixelDraw.text(self, card.position + Vector2(24, 58), "steer", col, 8)
	if magnet:
		PixelDraw.text(self, card.position + Vector2(4, 72), "magnet on", PixelDraw.SAGE_DARK.darkened(0.3), 8)
	else:
		PixelDraw.text(self, card.position + Vector2(4, 72), "%.1fs left" % time_left(), col, 8)


## 5x5 pixel arrow (top-left at p) pointing along dir.
func _arrow_icon(p: Vector2, dir: Vector2, col: Color) -> void:
	var o: Vector2 = PixelDraw.snap(p)
	for i in range(3):
		var w: float = float(1 + i * 2)
		if dir == Vector2.UP:
			draw_rect(Rect2(o.x + 2 - i, o.y + i, w, 1), col, true)
		elif dir == Vector2.DOWN:
			draw_rect(Rect2(o.x + 2 - i, o.y + 4 - i, w, 1), col, true)
		elif dir == Vector2.LEFT:
			draw_rect(Rect2(o.x + i, o.y + 2 - i, 1, w), col, true)
		else:
			draw_rect(Rect2(o.x + 4 - i, o.y + 2 - i, 1, w), col, true)


func _shape_label() -> String:
	match shape:
		"cat_face":
			return "Cat face"
		"bow_tie", "bow_tie_two_tone":
			return "Bow tie"
	return shape.capitalize()


func _draw_pop() -> void:
	# Sparkles twinkle along the finished line for 0.5 s (skipped under reduced motion).
	var t: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
	var total: float = float(path["length"])
	var count: int = 10
	for k in range(count):
		var s: float = total * (float(k) + 0.5) / float(count)
		var p: Vector2 = TracePaths.point_at(path, s)
		var phase: float = fmod(t * 2.0 + float(k) * 0.37, 1.0)
		var size: int = 2 if phase < 0.5 else 1
		var out: Vector2 = (p - center).normalized() * (t * 6.0)
		if k % 3 == 0:
			PixelDraw.star(self, p + out, 3.0 + (1.0 - t) * 2.0, PixelDraw.HONEY_LIGHT)
		else:
			PixelDraw.sparkle(self, p + out, size, PixelDraw.HONEY_LIGHT if k % 2 == 0 else PixelDraw.CREAM)
