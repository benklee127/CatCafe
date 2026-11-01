extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## KEEP_ZONE verb: hold to raise the needle, let go and it falls (Stardew-fishing feel with mild
## inertia). Keep it in the paw zone (zone_size, 18% of the gauge x window_scale()) until
## need_sec (2.0 s) of in-zone time is filled, within window_sec (6.0 s x time_scale()).
##   accuracy = in-zone time / active time, where the active clock starts the first time the
##   needle reaches the zone (the climb up is free). If the window runs out first, the missing
##   in-zone time counts as out-of-zone. Floored at 0.4 ("still tasty").
## Params: zone_center (via _roll.zone_center), zone_size, need_sec, window_sec, rise_speed,
## fall_speed (gauge units / s, terminal speeds), drift (wobble amplitude), gauge
## (milk|kettle|whisk|shaker|teapot; aliases steam->milk, tea->teapot, matcha->whisk, shake->shaker).
## extra: {in_zone, active, timed_out}.
## Sounds are out of scope: listen to `sfx(id)` ("rise", "fall", "zone_in", "zone_out", "pop").

signal sfx(id: String)

const POP_SEC := 0.5
const INERTIA_TAU := 0.15
const FLOOR := 0.4
const GAUGE_ALIASES: Dictionary = {"steam": "milk", "tea": "teapot", "matcha": "whisk", "shake": "shaker"}

var gauge: String = "milk"
var needle: float = 0.0
var velocity: float = 0.0
var zone_center: float = 0.6
var zone_size: float = 0.18
var need_sec: float = 2.0
var window_sec: float = 6.0
var in_zone_time: float = 0.0
var active_time: float = 0.0
var entered: bool = false
var in_zone: bool = false
var timed_out: bool = false
var accuracy: float = -1.0

var _rise: float = 0.55
var _fall: float = 0.45
var _drift: float = 0.0
var _pop_t: float = -1.0


func _on_start() -> void:
	gauge = String(params.get("gauge", "milk"))
	gauge = String(GAUGE_ALIASES.get(gauge, gauge))
	zone_center = clampf(float(roll("zone_center", params.get("zone_center", 0.6))), 0.1, 0.9)
	zone_size = clampf(float(params.get("zone_size", 0.18)) * window_scale(), 0.05, 0.6)
	need_sec = maxf(float(params.get("need_sec", 2.0)), 0.1)
	window_sec = maxf(float(params.get("window_sec", 6.0)) * time_scale(), need_sec + 0.5)
	_rise = float(params.get("rise_speed", 0.55))
	_fall = float(params.get("fall_speed", 0.45))
	_drift = float(params.get("drift", 0.0))
	needle = 0.0
	velocity = 0.0
	extra = {"in_zone": 0.0, "active": 0.0, "timed_out": false}


func zone_lo() -> float:
	return clampf(zone_center - zone_size * 0.5, 0.0, 1.0)


func zone_hi() -> float:
	return clampf(zone_center + zone_size * 0.5, 0.0, 1.0)


func time_left() -> float:
	return maxf(window_sec - elapsed, 0.0)


## Accuracy for given totals (static for probes). Unfilled time counts as out-of-zone.
static func score_zone(p_in: float, p_active: float, p_need: float) -> float:
	var missing: float = maxf(p_need - p_in, 0.0)
	var denom: float = maxf(p_active + missing, 0.001)
	return clampf(maxf(p_in / denom, FLOOR), 0.0, 1.0)


func _on_hold_begin(_pos: Vector2, _from_mouse: bool) -> void:
	if is_running():
		sfx.emit("rise")
		get_viewport().set_input_as_handled()


func _on_hold_end(_pos: Vector2) -> void:
	if is_running():
		sfx.emit("fall")


func _process(delta: float) -> void:
	if _pop_t >= 0.0:
		_pop_t += delta
	if is_running():
		_step_physics(delta)
	queue_redraw()


func _step_physics(delta: float) -> void:
	var want: float = _rise if is_primary_held() else -_fall
	velocity += (want - velocity) * (1.0 - exp(-delta / INERTIA_TAU))
	var v: float = velocity
	if _drift > 0.0:
		v += _drift * 3.0 * sin(elapsed * 3.1) + _drift * 1.5 * sin(elapsed * 7.3 + 1.0)
	needle += v * delta
	if needle <= 0.0:
		needle = 0.0
		velocity = maxf(velocity, 0.0)
	elif needle >= 1.0:
		needle = 1.0
		velocity = minf(velocity, 0.0) * 0.3
	var now_in: bool = needle >= zone_lo() and needle <= zone_hi()
	if now_in != in_zone:
		sfx.emit("zone_in" if now_in else "zone_out")
	in_zone = now_in
	if now_in:
		entered = true
	if entered:
		active_time += delta
		if now_in:
			in_zone_time += delta
	if in_zone_time >= need_sec:
		_finish_now(false)
	elif elapsed >= window_sec:
		_finish_now(true)


func _finish_now(p_timed_out: bool) -> void:
	timed_out = p_timed_out
	accuracy = score_zone(in_zone_time, active_time, need_sec)
	extra = {"in_zone": in_zone_time, "active": active_time, "timed_out": timed_out}
	_pop_t = 0.0
	sfx.emit("pop")
	finish(accuracy)


# --- Layout ------------------------------------------------------------------------------

func _cx() -> float:
	return roundf(safe_rect().get_center().x)


func gauge_rect() -> Rect2:
	return Rect2(_cx() + 30, 40, 16, 82)


func _gy(v: float) -> float:
	var g: Rect2 = gauge_rect().grow(-1)
	return roundf(g.end.y - g.size.y * clampf(v, 0.0, 1.0))


func _obj_pos() -> Vector2:
	return Vector2(_cx() - 34, 123)


# --- Drawing -----------------------------------------------------------------------------

func _draw() -> void:
	_draw_object()
	_draw_steam()
	_draw_gauge()
	_draw_progress()
	_draw_pop()


func _heat() -> float:
	# 0 = cold, ~0.5 = in zone, 1 = too hot. Drives steam / froth / shake.
	return clampf(needle, 0.0, 1.0)


func _shake_offset() -> Vector2:
	if reduced_motion() or not is_running():
		return Vector2.ZERO
	var amp: float = 0.0
	if gauge == "shaker" or gauge == "whisk":
		amp = 1.0 + roundf(_heat() * 2.0)
	elif needle > zone_hi():
		amp = 1.0
	if amp <= 0.0:
		return Vector2.ZERO
	return Vector2(roundf(sin(elapsed * 40.0) * amp), roundf(cos(elapsed * 33.0) * amp * 0.5))


func _draw_object() -> void:
	var b: Vector2 = _obj_pos()
	PixelDraw.shadow(self, b + Vector2(0, 1), 22, 2)
	var o: Vector2 = b + _shake_offset()
	var foam: float = clampf(in_zone_time / need_sec, 0.0, 1.0)
	match gauge:
		"kettle":
			PixelDraw.rounded_rect(self, Rect2(o.x - 20, o.y - 30, 40, 30), 8, PixelDraw.SAGE)
			PixelDraw.outlined_rect(self, Rect2(o.x + 18, o.y - 22, 12, 4), PixelDraw.SAGE)
			PixelDraw.ring(self, o + Vector2(0, -30), 10, 2, PixelDraw.OUTLINE, PI, TAU)
			PixelDraw.circle(self, o + Vector2(0, -32), 3, PixelDraw.HONEY)
			paw_px(self, o + Vector2(0, -14), PixelDraw.CREAM)
		"teapot":
			PixelDraw.circle(self, o + Vector2(0, -14), 15, PixelDraw.BLUSH)
			PixelDraw.outlined_rect(self, Rect2(o.x + 13, o.y - 20, 12, 4), PixelDraw.BLUSH)
			PixelDraw.ring(self, o + Vector2(-16, -14), 6, 2, PixelDraw.BLUSH, PI * 0.5, PI * 1.5)
			PixelDraw.rounded_rect(self, Rect2(o.x - 8, o.y - 31, 16, 5), 2, PixelDraw.CREAM)
			PixelDraw.circle(self, o + Vector2(0, -33), 2, PixelDraw.HONEY)
			# Tea tag on a string.
			PixelDraw.px(self, Rect2(o.x - 15, o.y - 24, 1, 10), PixelDraw.OUTLINE)
			PixelDraw.outlined_rect(self, Rect2(o.x - 18, o.y - 14, 7, 7), PixelDraw.HONEY_LIGHT)
		"whisk":
			# Bowl of matcha with a bobbing chasen whisk; froth grows with progress.
			PixelDraw.rounded_rect(self, Rect2(b.x - 22, b.y - 18, 44, 18), 7, PixelDraw.CREAM)
			draw_rect(Rect2(b.x - 19, b.y - 16, 38, 4), PixelDraw.SAGE, true)
			for k in range(int(foam * 7.0)):
				PixelDraw.disc(self, Vector2(b.x - 15 + k * 5, b.y - 16), 2, Color("#CFE5D5"))
			var wo: Vector2 = Vector2(o.x - b.x, 0) * 2.0
			PixelDraw.outlined_rect(self, Rect2(b.x - 3 + wo.x, b.y - 44, 6, 14), PixelDraw.OAK)
			for k in range(4):
				PixelDraw.px(self, Rect2(b.x - 5 + k * 3 + wo.x, b.y - 30, 1, 14), PixelDraw.OAK_DARK)
		"shaker":
			PixelDraw.rounded_rect(self, Rect2(o.x - 11, o.y - 44, 22, 44), 4, PixelDraw.CREAM_DARK)
			draw_rect(Rect2(o.x - 9, o.y - 30, 18, 28), PixelDraw.OAK, true)
			for k in range(3):
				PixelDraw.circle(self, Vector2(o.x - 5 + k * 5, o.y - 10 - (k % 2) * 6), 2, PixelDraw.HONEY_LIGHT)
			PixelDraw.rounded_rect(self, Rect2(o.x - 9, o.y - 52, 18, 9), 3, PixelDraw.SAGE)
			PixelDraw.hl(self, Rect2(o.x - 7, o.y - 40, 1, 30), Color(1, 1, 1, 0.5))
		_:
			# Milk pitcher under an espresso-machine steam wand; foam rises with progress.
			PixelDraw.outlined_rect(self, Rect2(b.x - 30, 40, 30, 8), PixelDraw.OAK_DARK)
			PixelDraw.outlined_rect(self, Rect2(b.x + 2, 44, 4, 36), PixelDraw.CREAM_DARK)
			PixelDraw.outlined_rect(self, Rect2(b.x - 8, 44, 14, 4), PixelDraw.CREAM_DARK)
			var steel := Color("#CFC7BC")
			PixelDraw.rounded_rect(self, Rect2(o.x + 16, o.y - 32, 10, 18), 3, steel)
			draw_rect(Rect2(o.x + 18, o.y - 29, 5, 12), PixelDraw.WALL, true)
			PixelDraw.rounded_rect(self, Rect2(o.x - 18, o.y - 42, 36, 42), 3, steel)
			PixelDraw.hl(self, Rect2(o.x - 15, o.y - 39, 1, 34), Color(1, 1, 1, 0.6))
			var top: float = o.y - 22 - roundf(foam * 14.0)
			draw_rect(Rect2(o.x - 16, top, 32, o.y - 2 - top), PixelDraw.MILK, true)
			PixelDraw.px(self, Rect2(o.x - 16, top, 32, 1), PixelDraw.CREAM_DARK)
			for k in range(int(foam * 6.0)):
				draw_rect(Rect2(o.x - 14 + k * 5, top + 2 + (k % 2), 2, 2), PixelDraw.CREAM_DARK, true)
			PixelDraw.outlined_rect(self, Rect2(o.x - 21, o.y - 44, 7, 4), steel)
			paw_px(self, o + Vector2(0, -9), PixelDraw.BLUSH)
			draw_rect(Rect2(b.x + 3, 79, 2, top - 79 + 4), PixelDraw.OUTLINE, true)


func _draw_steam() -> void:
	if reduced_motion():
		return
	var b: Vector2 = _obj_pos()
	var src: Vector2 = b + Vector2(-4, -44)
	if gauge == "shaker":
		# Motion lines instead of steam.
		if is_running() and is_primary_held():
			for k in range(3):
				var y: float = b.y - 40 + k * 12
				PixelDraw.px(self, Rect2(b.x - 22 - (k % 2) * 3, y, 5, 1), PixelDraw.OUTLINE)
				PixelDraw.px(self, Rect2(b.x + 18 + (k % 2) * 3, y + 4, 5, 1), PixelDraw.OUTLINE)
		return
	if gauge == "kettle":
		src = b + Vector2(28, -24)
	elif gauge == "teapot":
		src = b + Vector2(24, -22)
	elif gauge == "whisk":
		src = b + Vector2(0, -20)
	var h: float = _heat()
	var n: int = 2 + int(h * 6.0)
	var too_hot: bool = needle > zone_hi()
	var col: Color = Color("#FFFDF8")
	for k in range(n):
		var ph: float = fposmod(elapsed * (0.9 + h) + float(k) / float(n), 1.0)
		var sway: float = sin(ph * 6.0 + float(k) * 1.7) * (3.0 + h * 3.0)
		var p: Vector2 = src + Vector2(sway + float(k % 3 - 1) * 3.0, -ph * (22.0 + h * 14.0))
		var r: float = 1.5 + ph * (2.5 + (2.5 if too_hot else 0.0))
		var c: Color = col
		c.a = 0.85 * (1.0 - ph)
		PixelDraw.disc(self, p, r, c)


func _draw_gauge() -> void:
	var g: Rect2 = gauge_rect()
	PixelDraw.rounded_rect(self, g.grow(2), 3, PixelDraw.OAK)
	PixelDraw.outlined_rect(self, g, PixelDraw.CREAM_DARK)
	var inn: Rect2 = g.grow(-1)
	# Cold -> hot tint along the gauge (subtle), then the sage sweet zone.
	PixelDraw.meter_band(self, inn, 0.0, 0.25, Color("#E4EEF0"), true)
	PixelDraw.meter_band(self, inn, 0.75, 1.0, Color("#F4DCCB"), true)
	var lit: bool = in_zone and is_running()
	PixelDraw.meter_band(self, inn, zone_lo(), zone_hi(), PixelDraw.SAGE if not lit else Color("#A8D4B5"), true)
	var y0: float = _gy(zone_hi())
	var y1: float = _gy(zone_lo())
	# Paw-bracket notches: [ ] brackets outside the gauge with toe-bean dots.
	for side: int in [-1, 1]:
		var x: float = g.position.x - 5.0 if side == -1 else g.end.x + 2.0
		var xin: float = x + (3.0 if side == -1 else 0.0)
		PixelDraw.px(self, Rect2(xin if side == -1 else x, y0, 1, y1 - y0 + 1), PixelDraw.OUTLINE)
		PixelDraw.px(self, Rect2(x, y0, 4, 1), PixelDraw.OUTLINE)
		PixelDraw.px(self, Rect2(x, y1, 4, 1), PixelDraw.OUTLINE)
		var bx: float = x + (-3.0 if side == -1 else 5.0)
		if side == 1:
			paw_px(self, Vector2(bx + 4.0, (y0 + y1) * 0.5), PixelDraw.SAGE_DARK)
	# Needle: bar across the gauge + honey pointer on the left.
	var ny: float = _gy(needle)
	var px: float = g.position.x - 14
	if not PixelDraw.legacy():
		# B..F: the pointer arrow + its tail get the ow() outer outline (grown ink silhouette).
		var gw: float = float(PixelDraw.ow() - 1)
		for i in range(5):
			draw_rect(Rect2(px + i, ny - (4 - i), 1, (4 - i) * 2 + 1).grow(gw), PixelDraw.OUTLINE, true)
		draw_rect(Rect2(px - 4, ny - 1, 4, 3).grow(gw), PixelDraw.OUTLINE, true)
	draw_rect(Rect2(inn.position.x, ny - 1, inn.size.x, 3), PixelDraw.OUTLINE, true)
	draw_rect(Rect2(inn.position.x + 1, ny, inn.size.x - 2, 1), PixelDraw.HONEY, true)
	for i in range(5):
		draw_rect(Rect2(px + i, ny - (4 - i), 1, (4 - i) * 2 + 1), PixelDraw.OUTLINE, true)
	for i in range(3):
		draw_rect(Rect2(px + 1 + i, ny - (2 - i), 1, (2 - i) * 2 + 1), PixelDraw.HONEY, true)
	draw_rect(Rect2(px - 4, ny - 1, 4, 3), PixelDraw.OUTLINE, true)
	draw_rect(Rect2(px - 3, ny, 3, 1), PixelDraw.HONEY, true)


func _draw_progress() -> void:
	var cx: float = _cx()
	var box := Rect2(cx - 70, 136, 140, 26)
	if not PixelDraw.legacy():
		# B..F: wider for the bold font, 2px taller so descenders clear the thicker bottom outline.
		box = Rect2(cx - 86, 136, 172, 28)
	PixelDraw.rounded_rect(self, box, 3, PixelDraw.CREAM)
	var bar := Rect2(box.position.x + 8, box.position.y + 4, box.size.x - 16, 7)
	PixelDraw.meter(self, bar, in_zone_time / need_sec, PixelDraw.SAGE)
	# Window clock: thin honey bar that drains.
	var tb := Rect2(bar.position.x, bar.end.y + 2, bar.size.x * clampf(time_left() / window_sec, 0.0, 1.0), 1)
	if tb.size.x >= 1.0:
		PixelDraw.px(self, PixelDraw.snap_rect(tb), PixelDraw.HONEY)
	var msg: String
	if is_finished():
		msg = "Silky smooth!" if accuracy >= 0.9 else ("Nice and warm!" if accuracy >= 0.65 else "Still tasty!")
	elif hold_to_toggle:
		msg = "Tap to rise / fall   %.1f / %.1fs" % [in_zone_time, need_sec]
	else:
		msg = "Hold to rise   in zone %.1f / %.1fs" % [in_zone_time, need_sec]
	var base_y: float = box.end.y - (3.0 if PixelDraw.legacy() else 5.0)
	PixelDraw.text(self, Vector2(box.position.x, base_y), msg, PixelDraw.OUTLINE, 8, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)


func _draw_pop() -> void:
	if _pop_t < 0.0 or _pop_t > POP_SEC + 0.3:
		return
	var t: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
	var g: Rect2 = gauge_rect()
	var c := Vector2(g.get_center().x, _gy(zone_center))
	var n: int = 8 if accuracy >= 0.9 else (5 if accuracy >= 0.65 else 3)
	for k in range(n):
		var ang: float = float(k) * TAU / float(n) + 0.3
		var rr: float = 12.0 + (0.0 if reduced_motion() else t * 12.0)
		PixelDraw.sparkle(self, c + Vector2(cos(ang), sin(ang)) * rr, 1 if k % 2 == 0 else 2, PixelDraw.HONEY if accuracy >= 0.65 else PixelDraw.HONEY_LIGHT)
	if accuracy >= 0.9:
		var lift: float = 0.0 if reduced_motion() else roundf(t * 6.0)
		PixelDraw.star(self, Vector2(g.end.x + 14, _gy(zone_hi()) - 8 - lift), 4, PixelDraw.HONEY)


## Crisp 9x8 pixel paw (four toes + pad); readable at 1x where PixelDraw.paw blurs together.
const PAW_PX: Array[String] = ["..XX.XX..", "..XX.XX..", "XX.....XX", "XX.XXX.XX", "..XXXXX..", ".XXXXXXX.", ".XXXXXXX.", "..XXXXX.."]


static func paw_px(ci: CanvasItem, center: Vector2, color: Color) -> void:
	var o: Vector2 = PixelDraw.snap(center) - Vector2(4, 4)
	for row in range(PAW_PX.size()):
		var line: String = PAW_PX[row]
		for col in range(line.length()):
			if line[col] == "X":
				ci.draw_rect(Rect2(o.x + col, o.y + row, 1, 1), color, true)
