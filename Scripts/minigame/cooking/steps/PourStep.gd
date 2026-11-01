extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## POUR verb: hold to pour, let go on the paw line (design 2.4, Docs/MINIGAMES.md "pour").
##   * Flow ramps flow_min -> flow_max (vessel fraction / sec) over ramp_sec while held, so a
##     long hold is fast but hard to land.
##   * Accuracy by |fill - target|: <= bands[0] 1.0, <= bands[1] 0.85, <= bands[2] 0.65, else 0.4
##     (bands x window_scale()).
##   * Filling past target + spill_over (x window_scale) is a cute spill, capped at spill_cap.
##     no_overflow: anything past the perfect band counts as overflow (same cap).
##   * Layered drinks: layer "B" + line_from_prev shifts the line by the previous pour's error
##     and starts the vessel with that layer ("calico" two-tone).
##   * Reaching the brim ends the pour automatically.
## Params (all optional): target_range, flow_min, flow_max, ramp_sec, bands, spill_over,
## spill_cap, vessel (mug|bowl|glass|pan|mold; aliases cup->mug, pitcher->glass, scoop->bowl,
## batter->pan), liquid (hex; alias color), source (pitcher|scoop|ladle), base_fill,
## base_liquid, layer, line_from_prev, no_overflow.
## extra: {fill, target, liquid, spilled, layer} (read by layered pours via params._prev).
## Sounds are out of scope: listen to `sfx(id)` ("pour_start", "pour_stop", "spill", "pop").

signal sfx(id: String)

const POP_SEC := 0.5
const EMPTY := Color("#E7D8C4")
const VESSEL_ALIASES: Dictionary = {"cup": "mug", "pitcher": "glass", "scoop": "bowl", "batter": "pan"}

var vessel: String = "mug"
var source: String = "pitcher"
var liquid: Color = PixelDraw.COFFEE
var base_liquid: Color = PixelDraw.SAGE
var base_fill: float = 0.0
var target: float = 0.7
var line_a: float = -1.0
var fill: float = 0.0
var pouring: bool = false
var hold_t: float = 0.0
var flow: float = 0.0
var spilled: bool = false
var accuracy: float = -1.0

var _flow_min: float = 0.15
var _flow_max: float = 0.6
var _ramp: float = 1.0
var _bands: Array = [0.03, 0.06, 0.10]
var _spill_over: float = 0.15
var _spill_cap: float = 0.65
var _no_overflow: bool = false
var _spill_t: float = -1.0
var _pop_t: float = -1.0


func _on_start() -> void:
	vessel = String(params.get("vessel", "mug"))
	vessel = String(VESSEL_ALIASES.get(vessel, vessel))
	var default_src: String = "pitcher"
	if vessel == "bowl":
		default_src = "scoop"
	elif vessel == "pan" or vessel == "mold":
		default_src = "ladle"
	source = String(params.get("source", default_src))
	liquid = _color(params.get("liquid", params.get("color", "#7A4E33")), PixelDraw.COFFEE)
	base_liquid = _color(params.get("base_liquid", "#8FBF9F"), PixelDraw.SAGE)
	base_fill = clampf(float(params.get("base_fill", 0.0)), 0.0, 0.9)
	_flow_min = float(params.get("flow_min", 0.15))
	_flow_max = float(params.get("flow_max", 0.6))
	_ramp = maxf(float(params.get("ramp_sec", 1.0)), 0.05)
	var b: Variant = params.get("bands", [0.03, 0.06, 0.10])
	_bands = b if b is Array and (b as Array).size() >= 3 else [0.03, 0.06, 0.10]
	_spill_over = float(params.get("spill_over", 0.15))
	_spill_cap = float(params.get("spill_cap", 0.65))
	_no_overflow = bool(params.get("no_overflow", false))
	var tr: Array = params.get("target_range", [0.55, 0.85])
	target = float(roll("target", (float(tr[0]) + float(tr[1])) * 0.5))
	if bool(params.get("line_from_prev", false)):
		var prev: Dictionary = _prev_pour()
		if not prev.is_empty():
			var pf: float = float(prev.get("fill", -1.0))
			var pt: float = float(prev.get("target", -1.0))
			if pf >= 0.0 and pt >= 0.0:
				# Forgiving re-target: line B moves with layer A's error.
				target += pf - pt
				line_a = pf
				base_fill = clampf(pf, 0.0, 0.9)
				if prev.has("liquid"):
					base_liquid = _color(prev["liquid"], base_liquid)
	target = clampf(target, base_fill + 0.08, 0.95)
	fill = base_fill
	extra = {"fill": fill, "target": target, "liquid": liquid.to_html(false), "spilled": false, "layer": String(params.get("layer", ""))}


static func _color(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	var s: String = String(v)
	return Color.from_string(s, fallback) if s != "" else fallback


func _prev_pour() -> Dictionary:
	var prev: Variant = params.get("_prev", [])
	if not (prev is Array):
		return {}
	var arr: Array = prev
	for i in range(arr.size() - 1, -1, -1):
		var r: Variant = arr[i]
		if r is Dictionary and String((r as Dictionary).get("type", "")) == "pour":
			var ex: Variant = (r as Dictionary).get("extra", {})
			return ex if ex is Dictionary else {}
	return {}


# --- Scoring (static so probes / balance tools can call it) ------------------------------

## Accuracy for a final fill. ws = window_scale(). Returns {accuracy, spilled}.
static func score_fill(p_fill: float, p_target: float, ws: float, bands: Array = [0.03, 0.06, 0.10], spill_over: float = 0.15, spill_cap: float = 0.65, no_overflow: bool = false) -> Dictionary:
	var d: float = absf(p_fill - p_target)
	var acc: float = 0.4
	if d <= float(bands[0]) * ws + 0.0001:
		acc = 1.0
	elif d <= float(bands[1]) * ws + 0.0001:
		acc = 0.85
	elif d <= float(bands[2]) * ws + 0.0001:
		acc = 0.65
	var limit: float = float(bands[0]) * ws if no_overflow else spill_over * ws
	var sp: bool = p_fill - p_target > limit
	if sp:
		acc = minf(acc, spill_cap)
	return {"accuracy": acc, "spilled": sp}


func spill_line() -> float:
	return target + (float(_bands[0]) if _no_overflow else _spill_over) * window_scale()


# --- Input -------------------------------------------------------------------------------

func _on_hold_begin(_pos: Vector2, _from_mouse: bool) -> void:
	if not is_running() or pouring:
		return
	pouring = true
	hold_t = 0.0
	sfx.emit("pour_start")
	get_viewport().set_input_as_handled()
	queue_redraw()


func _on_hold_end(_pos: Vector2) -> void:
	if not pouring:
		return
	_stop_pour()
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _stop_pour() -> void:
	pouring = false
	sfx.emit("pour_stop")
	var r: Dictionary = score_fill(fill, target, window_scale(), _bands, _spill_over, _spill_cap, _no_overflow)
	accuracy = float(r["accuracy"])
	spilled = bool(r["spilled"]) or spilled
	extra = {"fill": fill, "target": target, "liquid": liquid.to_html(false), "spilled": spilled, "layer": String(params.get("layer", ""))}
	_pop_t = 0.0
	sfx.emit("pop")
	queue_redraw()
	finish(accuracy)


func _process(delta: float) -> void:
	if _pop_t >= 0.0:
		_pop_t += delta
	if _spill_t >= 0.0:
		_spill_t += delta
	if is_running() and pouring:
		hold_t += delta
		flow = lerpf(_flow_min, _flow_max, clampf(hold_t / _ramp, 0.0, 1.0))
		fill = minf(fill + flow * delta, 1.0)
		if not spilled and fill > spill_line():
			spilled = true
			_spill_t = 0.0
			sfx.emit("spill")
		if fill >= 1.0:
			_stop_pour()
	elif not pouring:
		flow = 0.0
	queue_redraw()


# --- Layout ------------------------------------------------------------------------------

func _cx() -> float:
	return roundf(safe_rect().get_center().x)


## Interior rect of the vessel (the liquid area); bottom sits on the counter (y=124).
func vessel_inner() -> Rect2:
	var cx: float = _cx() - 24.0
	match vessel:
		"glass":
			return Rect2(cx - 16, 52, 32, 68)
		"bowl":
			return Rect2(cx - 30, 92, 60, 28)
		"pan":
			return Rect2(cx - 34, 104, 68, 14)
		"mold":
			return Rect2(cx - 30, 96, 60, 24)
	return Rect2(cx - 22, 62, 44, 58)


func _level_y(inner: Rect2, f: float) -> float:
	return roundf(inner.end.y - inner.size.y * clampf(f, 0.0, 1.0))


func _ruler_rect() -> Rect2:
	var inner: Rect2 = vessel_inner()
	if inner.size.y >= 40.0:
		# Same height as the liquid, so the ruler's paw lines up with the line in the vessel.
		return Rect2(inner.end.x + 22, inner.position.y - 1, 10, inner.size.y + 2)
	return Rect2(inner.end.x + (36 if vessel == "pan" else 22), 66, 10, 54)


func _ruler_y(f: float) -> float:
	var r: Rect2 = _ruler_rect()
	return roundf(r.end.y - 1 - (r.size.y - 2) * clampf(f, 0.0, 1.0))


# --- Drawing -----------------------------------------------------------------------------

func _draw() -> void:
	var inner: Rect2 = vessel_inner()
	_draw_vessel_back(inner)
	_draw_liquid(inner)
	_draw_line(inner)
	_draw_vessel_front(inner)
	_draw_source(inner)
	_draw_spill(inner)
	_draw_ruler()
	_draw_label()
	_draw_pop(inner)


func _draw_vessel_back(inner: Rect2) -> void:
	PixelDraw.shadow(self, Vector2(inner.get_center().x, 125), inner.size.x * 0.6 + 4, 2)
	match vessel:
		"pan":
			# Handle + skillet body (side view, shallow).
			PixelDraw.outlined_rect(self, Rect2(inner.end.x + 2, inner.position.y + 2, 26, 5), PixelDraw.COCOA)
			PixelDraw.rounded_rect(self, Rect2(inner.position.x - 3, inner.position.y - 2, inner.size.x + 6, inner.size.y + 5), 3, Color("#5B4A44"))
		"mold":
			PixelDraw.rounded_rect(self, Rect2(inner.position.x - 4, inner.position.y - 3, inner.size.x + 8, inner.size.y + 6), 2, Color("#6B5A52"))
		"bowl":
			PixelDraw.rounded_rect(self, Rect2(inner.position.x - 3, inner.position.y - 2, inner.size.x + 6, inner.size.y + 5), 6, PixelDraw.BLUSH)
		"glass":
			PixelDraw.outlined_rect(self, Rect2(inner.position.x - 2, inner.position.y - 4, inner.size.x + 4, inner.size.y + 6), PixelDraw.CREAM)
		_:
			var hr := Rect2(inner.end.x + 1, inner.position.y + 8, 10, 22)
			PixelDraw.rounded_rect(self, hr, 3, PixelDraw.SAGE)
			draw_rect(Rect2(hr.position.x, hr.position.y + 3, 6, hr.size.y - 6), PixelDraw.WALL, true)
			PixelDraw.px(self, Rect2(hr.position.x + 5, hr.position.y + 3, 1, hr.size.y - 6), PixelDraw.OUTLINE)
			PixelDraw.rounded_rect(self, Rect2(inner.position.x - 3, inner.position.y - 1, inner.size.x + 6, inner.size.y + 4), 3, PixelDraw.SAGE)
	draw_rect(inner, EMPTY, true)
	if vessel == "mold":
		# Fish-shaped cavity hint: scales stamped into the empty mold.
		for i in range(4):
			PixelDraw.ring(self, Vector2(inner.position.x + 14 + i * 10, inner.get_center().y), 3, 1, Color(PixelDraw.OUTLINE, 0.25), PI * 0.2, PI * 0.8)


func _draw_liquid(inner: Rect2) -> void:
	var wobble: bool = pouring and not reduced_motion()
	if base_fill > 0.0:
		var by: float = _level_y(inner, base_fill)
		draw_rect(Rect2(inner.position.x, by, inner.size.x, inner.end.y - by), base_liquid, true)
	if fill > base_fill + 0.001:
		var ty: float = _level_y(inner, fill)
		var by2: float = _level_y(inner, base_fill)
		if by2 - ty > 0.0:
			draw_rect(Rect2(inner.position.x, ty, inner.size.x, by2 - ty), liquid, true)
			PixelDraw.hl(self, Rect2(inner.position.x, ty, 1, by2 - ty), liquid.darkened(0.12))
			PixelDraw.hl(self, Rect2(inner.end.x - 1, ty, 1, by2 - ty), liquid.darkened(0.12))
		if base_fill > 0.0:
			# Calico swirl: soft scalloped boundary between the two layers.
			for x in range(int(inner.position.x), int(inner.end.x), 4):
				PixelDraw.px(self, Rect2(x, by2 - 1, 2, 1), base_liquid)
		# Surface: darker rim + ripple while pouring.
		var surf: Color = liquid.darkened(0.22)
		for x in range(int(inner.position.x), int(inner.end.x)):
			var dy: float = 0.0
			if wobble:
				dy = roundf(sin(float(x) * 0.7 + elapsed * 14.0) * 0.6)
			PixelDraw.px(self, Rect2(x, ty + dy, 1, 1), surf)
		PixelDraw.hl(self, Rect2(inner.position.x + 2, ty + 2, 3, 1), liquid.lightened(0.35))
	elif base_fill > 0.0:
		PixelDraw.px(self, Rect2(inner.position.x, _level_y(inner, base_fill), inner.size.x, 1), base_liquid.darkened(0.2))


func _draw_line(inner: Rect2) -> void:
	var y: float = _level_y(inner, target)
	var hit: bool = _pop_t >= 0.0 and accuracy >= 1.0
	var col: Color = PixelDraw.SAGE_DARK if hit else PixelDraw.OUTLINE
	# Two-tone dashes read on light and dark liquids alike.
	var x: float = inner.position.x
	while x < inner.end.x:
		PixelDraw.px(self, Rect2(x, y - 1, minf(3.0, inner.end.x - x), 1), PixelDraw.CREAM)
		PixelDraw.px(self, Rect2(x, y, minf(3.0, inner.end.x - x), 1), col)
		x += 5.0
	# Paw-shaped line ends: a paw on the left wall pointing at the line.
	paw_px(self, Vector2(inner.position.x - 11, y), col)
	if line_a >= 0.0:
		var ya: float = _level_y(inner, line_a)
		PixelDraw.px(self, Rect2(inner.position.x - 5, ya, 3, 1), Color(PixelDraw.OUTLINE, 0.5))


func _draw_vessel_front(inner: Rect2) -> void:
	match vessel:
		"glass":
			PixelDraw.hl(self, Rect2(inner.position.x + 2, inner.position.y + 3, 1, inner.size.y - 10), Color(1, 1, 1, 0.55))
			draw_rect(Rect2(inner.position.x - 2, inner.end.y, inner.size.x + 4, 2), PixelDraw.OUTLINE, true)
		"bowl":
			PixelDraw.hl(self, Rect2(inner.position.x + 6, inner.end.y + 1, inner.size.x - 12, 1), Color(1, 1, 1, 0.4))
		"mug":
			PixelDraw.px(self, Rect2(inner.position.x - 3, inner.end.y + 1, inner.size.x + 6, 1), PixelDraw.SAGE_DARK)


func _src_spout(inner: Rect2) -> Vector2:
	return Vector2(roundf(inner.get_center().x - 2), roundf(minf(inner.position.y, 70.0) - 16))


func _draw_source(inner: Rect2) -> void:
	var spout: Vector2 = _src_spout(inner)
	var tilt: float = 0.0
	if pouring:
		tilt = 0.45 + 0.25 * clampf(hold_t / _ramp, 0.0, 1.0)
	if reduced_motion() and pouring:
		tilt = 0.6
	# Stream / dollops from spout to the surface.
	var surf_y: float = _level_y(inner, fill)
	if pouring:
		var w: float = 1.0 + roundf(2.0 * clampf((flow - _flow_min) / maxf(_flow_max - _flow_min, 0.01), 0.0, 1.0))
		if source == "scoop":
			var n: int = 3
			for k in range(n):
				var ph: float = fposmod(elapsed * 2.5 + float(k) / float(n), 1.0)
				var py: float = lerpf(spout.y + 4, surf_y - 2, ph)
				PixelDraw.circle(self, Vector2(spout.x, py), 3, liquid)
		else:
			var sw: float = w + (1.0 if source == "ladle" else 0.0)
			if PixelDraw.legacy():
				draw_rect(Rect2(spout.x - floorf(sw * 0.5), spout.y + 2, sw, surf_y - spout.y - 2), liquid, true)
				PixelDraw.px(self, Rect2(spout.x - floorf(sw * 0.5) - 1, spout.y + 2, 1, surf_y - spout.y - 2), Color(PixelDraw.OUTLINE, 0.55))
			else:
				# B..F: the stream is a solid object too: ow() ink on both sides (2px min core).
				var cw: float = maxf(sw, 2.0)
				var sr := Rect2(spout.x - floorf(cw * 0.5), spout.y + 2, cw, surf_y - spout.y - 2)
				draw_rect(Rect2(sr.position.x - PixelDraw.ow(), sr.position.y, sr.size.x + 2 * PixelDraw.ow(), sr.size.y), PixelDraw.OUTLINE, true)
				draw_rect(sr, liquid, true)
			if not reduced_motion():
				for k in range(2):
					var sx: float = spout.x + (-3.0 if k == 0 else 3.0)
					var ph2: float = fposmod(elapsed * 6.0 + k * 0.5, 1.0)
					PixelDraw.px(self, Rect2(sx + (ph2 * 2.0 * (-1.0 if k == 0 else 1.0)), surf_y - 1 - roundf(ph2 * 3.0), 1, 1), liquid.lightened(0.2))
	# The source object, rotated around its spout.
	draw_set_transform(spout, -tilt, Vector2.ONE)
	match source:
		"scoop":
			PixelDraw.outlined_rect(self, Rect2(-26, -6, 18, 3), PixelDraw.OAK)
			PixelDraw.circle(self, Vector2(-4, -4), 6, PixelDraw.CREAM_DARK)
			PixelDraw.disc(self, Vector2(-4, -6), 4, liquid)
		"ladle":
			PixelDraw.outlined_rect(self, Rect2(-28, -14, 16, 3), PixelDraw.OAK)
			PixelDraw.rounded_rect(self, Rect2(-14, -16, 16, 14), 4, PixelDraw.CREAM)
			draw_rect(Rect2(-12, -9, 12, 5), liquid, true)
		_:
			# Pitcher: body up-left of the spout, handle on the left.
			PixelDraw.rounded_rect(self, Rect2(-30, -12, 8, 12), 3, PixelDraw.CREAM)
			draw_rect(Rect2(-28, -9, 4, 6), PixelDraw.WALL, true)
			PixelDraw.rounded_rect(self, Rect2(-24, -20, 22, 22), 3, PixelDraw.CREAM)
			draw_rect(Rect2(-22, -10, 18, 10), liquid, true)
			PixelDraw.px(self, Rect2(-22, -10, 18, 1), liquid.darkened(0.2))
			PixelDraw.outlined_rect(self, Rect2(-4, -20, 5, 4), PixelDraw.CREAM)
			paw_px(self, Vector2(-13, -12), PixelDraw.BLUSH)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_spill(inner: Rect2) -> void:
	if not spilled:
		return
	var t: float = maxf(_spill_t, 0.0)
	var ground: float = 123.0
	# Puddle: liquid with an orange rim + a star notch (orange is never the only signal).
	var grow: float = 1.0 if reduced_motion() else clampf(t / 0.4, 0.3, 1.0)
	var px: float = inner.end.x + 6
	var pw: float = roundf(14.0 * grow)
	PixelDraw.rounded_rect(self, Rect2(px - pw, ground - 3, pw * 2, 4), 1, liquid, PixelDraw.ALERT)
	PixelDraw.star(self, Vector2(px + pw + 4, ground - 3), 3, PixelDraw.ALERT)
	# Drips running down the outside wall.
	var top: float = _level_y(inner, minf(fill, 1.0))
	draw_rect(Rect2(inner.end.x + 1, top, 2, ground - top), liquid, true)
	PixelDraw.px(self, Rect2(inner.end.x + 3, top, 1, ground - top), PixelDraw.ALERT)
	if not reduced_motion() and is_running():
		for k in range(3):
			var ph: float = fposmod(t * 2.2 + float(k) / 3.0, 1.0)
			var dx: float = (8.0 + k * 5.0) * ph
			var dy: float = -6.0 * sin(ph * PI) + ph * 10.0
			PixelDraw.circle(self, Vector2(inner.end.x + 2 + dx, top + dy), 2, liquid, PixelDraw.ALERT)


func _draw_ruler() -> void:
	var r: Rect2 = _ruler_rect()
	PixelDraw.outlined_rect(self, r, PixelDraw.CREAM)
	var inn: Rect2 = r.grow(-1)
	var ws: float = window_scale()
	PixelDraw.meter_band(self, inn, target - float(_bands[2]) * ws, target + float(_bands[2]) * ws, PixelDraw.HONEY_LIGHT, true)
	PixelDraw.meter_band(self, inn, target - float(_bands[1]) * ws, target + float(_bands[1]) * ws, PixelDraw.HONEY, true)
	PixelDraw.meter_band(self, inn, target - float(_bands[0]) * ws, target + float(_bands[0]) * ws, PixelDraw.SAGE, true)
	# Paw at the line on the right; orange star notch where the spill starts.
	paw_px(self, Vector2(r.end.x + 8, _ruler_y(target)), PixelDraw.OUTLINE)
	var sl: float = spill_line()
	if sl < 1.0:
		var sy: float = _ruler_y(sl)
		PixelDraw.px(self, Rect2(r.position.x - 2, sy, r.size.x + 4, 1), PixelDraw.ALERT)
		PixelDraw.star(self, Vector2(r.end.x + 5, sy - 1), 2, PixelDraw.ALERT)
	if line_a >= 0.0:
		var ay: float = _ruler_y(line_a)
		PixelDraw.px(self, Rect2(r.position.x - 2, ay, 3, 1), PixelDraw.OUTLINE)
	# Current level pointer (triangle on the left).
	var y: float = _ruler_y(fill)
	PixelDraw.px(self, Rect2(r.position.x - 1, y, r.size.x + 2, 1), PixelDraw.OUTLINE)
	for i in range(4):
		PixelDraw.px(self, Rect2(r.position.x - 6 + i, y - (3 - i), 1, (3 - i) * 2 + 1), PixelDraw.OUTLINE)


func _draw_label() -> void:
	var cx: float = _cx()
	var msg: String
	if is_finished():
		msg = "Spilled a little!" if spilled else ("Right on the line!" if accuracy >= 1.0 else "Poured!")
	elif pouring:
		msg = "Tap to stop on the line" if hold_to_toggle else "Let go on the paw line!"
	else:
		msg = "Tap Space/LMB to pour" if hold_to_toggle else "Hold Space / LMB to pour"
	var bw: float = 124.0
	if not PixelDraw.legacy():
		bw = maxf(bw, 2.0 * ceilf((PixelDraw.text_width(msg) + 12.0) * 0.5))
	var box := Rect2(cx - bw * 0.5, 140, bw, 14)
	PixelDraw.rounded_rect(self, box, 3, PixelDraw.CREAM)
	PixelDraw.text(self, box.position + Vector2(0, 10), msg, PixelDraw.OUTLINE, 8, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	# Flow drops beside the label: light up as the pour speeds up.
	var fr: float = clampf((flow - _flow_min) / maxf(_flow_max - _flow_min, 0.01), 0.0, 1.0) if pouring else 0.0
	for k in range(3):
		var on: bool = pouring and fr >= float(k) * 0.45
		var dp := Vector2(box.end.x + 8 + k * 7, box.get_center().y + 1)
		PixelDraw.circle(self, dp, 3, PixelDraw.HONEY if on else PixelDraw.CREAM_DARK)
		PixelDraw.px(self, Rect2(dp.x, dp.y - 5, 1, 2), PixelDraw.HONEY if on else PixelDraw.CREAM_DARK)


func _draw_pop(inner: Rect2) -> void:
	if _pop_t < 0.0 or _pop_t > POP_SEC + 0.3:
		return
	var t: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
	var c := Vector2(inner.get_center().x, _level_y(inner, fill))
	var n: int = 8 if accuracy >= 1.0 else (5 if accuracy >= 0.85 else 3)
	var col: Color = PixelDraw.HONEY if accuracy >= 0.85 else PixelDraw.HONEY_LIGHT
	for k in range(n):
		var ang: float = -PI + float(k) * PI / float(maxi(n - 1, 1))
		var rr: float = 10.0 + (0.0 if reduced_motion() else t * 14.0)
		PixelDraw.sparkle(self, c + Vector2(cos(ang) * rr * 1.4, sin(ang) * rr), 1 if k % 2 == 0 else 2, col)
	if accuracy >= 1.0:
		var lift: float = 0.0 if reduced_motion() else roundf(t * 6.0)
		PixelDraw.star(self, Vector2(_ruler_rect().end.x + 7, _ruler_y(target) - 9 - lift), 4, PixelDraw.HONEY)


## Crisp 9x8 pixel paw (four toes + pad); readable at 1x where PixelDraw.paw blurs together.
const PAW_PX: Array[String] = ["..XX.XX..", "..XX.XX..", "XX.....XX", "XX.XXX.XX", "..XXXXX..", ".XXXXXXX.", ".XXXXXXX.", "..XXXXX.."]


static func paw_px(ci: CanvasItem, center: Vector2, color: Color) -> void:
	var o: Vector2 = PixelDraw.snap(center) - Vector2(4, 4)
	for row in range(PAW_PX.size()):
		var line: String = PAW_PX[row]
		for col in range(line.length()):
			if line[col] == "X":
				ci.draw_rect(Rect2(o.x + col, o.y + row, 1, 1), color, true)
