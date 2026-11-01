extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## STOP_RING verb: tap when the ring is golden (bake, toast, flip, stamp, pound).
##
## A knob sweeps clockwise round a ring from the top: raw (cream) -> golden (honey, star notch)
## -> toasty (oak). The food in the porthole browns with the knob. Tap (LMB / Space) to stop it.
##   * Sweep:   params.sweep_sec, else _sweep_sec x _roll.sweep_mult (tier 2.4 / 2.0 / 1.6 s),
##              x time_scale() (leniency slows the sweep).
##   * Golden:  golden_sec (0.40 s) centred on golden_center (0.5 of the sweep), x window_scale().
##              Its middle perfect_sec (0.16 s, x window_scale()) scores 1.0, the rest 0.85.
##   * Miss:    a tap outside the window (too raw / too toasty) or letting the sweep run out loops
##              once ("it cooled a bit"); the retry is capped at retry_cap (0.7). A second miss
##              scores 0.4 ("still tasty").
##   * hits: n  stamping conveyor: n items roll through the porthole; accuracy = mean of hits.
##   * tempo_sec  steady-tempo pounding (mochi): each beat is one sweep of tempo_sec (x leniency)
##              with almost no gap between beats. No sweep_mult roll, so the tempo is steady.
##   * food:    cookie | stamp | taiyaki | pancake | mochi (cosmetic).
## extra = {brown: mean 0..1 (0.5 = golden), browns: [per hit], hits: [per-hit accuracy]}.
## Hooks for later audio: _sfx(id) is called with "tick", "golden", "good", "miss", "cool".

const RAW_COL := Color("#F3DDB0")
const GOLD_COL := Color("#E0A24A")
const TOAST_COL := Color("#9A5E33")
const MOCHI_COL := Color("#FFFDF7")

const POP_SEC := 0.5
const GAP_SEC := 0.3
const TEMPO_GAP_SEC := 0.08
const COOL_SEC := 0.6
const RING_R := 34.0
const RING_W := 7.0

enum State { IDLE, SWEEP, POP, COOL, DONE }

var state: int = State.IDLE
## Seconds into the current sweep.
var t: float = 0.0
var dur: float = 2.4
var center_t: float = 1.2
var golden_half: float = 0.2
var perfect_half: float = 0.08
var hits_total: int = 1
var hit_index: int = 0
var retrying: bool = false
var retry_cap: float = 0.7
var tempo: bool = false
var food: String = "cookie"

var hit_scores: Array[float] = []
var hit_browns: Array[float] = []
var _state_t: float = 0.0
var _pop_acc: float = 0.0
var _pop_text: String = ""
var _pop_brown: float = 0.0
var _last_tick: int = -1
var _imprint_offset: Vector2 = Vector2.ZERO


func _on_start() -> void:
	hits_total = maxi(int(params.get("hits", 1)), 1)
	food = String(params.get("food", "cookie"))
	retry_cap = float(params.get("retry_cap", 0.7))
	tempo = params.has("tempo_sec")
	var sweep: float
	if tempo:
		sweep = float(params.get("tempo_sec", 0.9))
	elif params.has("sweep_sec"):
		sweep = float(params.get("sweep_sec"))
	else:
		sweep = float(params.get("_sweep_sec", 2.4)) * float(roll("sweep_mult", 1.0))
	dur = maxf(sweep * time_scale(), 0.2)
	center_t = clampf(float(params.get("golden_center", 0.5)), 0.15, 0.85) * dur
	var ws: float = window_scale()
	golden_half = minf(float(params.get("golden_sec", 0.4)) * ws * 0.5, dur * 0.45)
	golden_half = minf(golden_half, minf(center_t, dur - center_t))
	perfect_half = minf(float(params.get("perfect_sec", 0.16)) * ws * 0.5, golden_half)
	hit_index = 0
	retrying = false
	hit_scores.clear()
	hit_browns.clear()
	t = 0.0
	state = State.SWEEP
	_state_t = 0.0
	queue_redraw()


## Probe / debug view of the timing state.
func get_debug_state() -> Dictionary:
	return {
		"state": state, "t": t, "dur": dur, "center_t": center_t,
		"golden_half": golden_half, "perfect_half": perfect_half,
		"hit_index": hit_index, "hits_total": hits_total, "retrying": retrying,
		"scores": hit_scores.duplicate(),
	}


func _process(delta: float) -> void:
	_state_t += delta
	match state:
		State.SWEEP:
			if not is_running():
				return
			t += delta
			var tick: int = int(t / dur * 8.0)
			if tick != _last_tick:
				_last_tick = tick
				_sfx("tick")
			if t >= dur:
				t = dur
				_miss("Too toasty!")
		State.POP:
			if _state_t >= _pop_hold():
				_advance()
		State.COOL:
			if _state_t >= COOL_SEC:
				t = 0.0
				_last_tick = -1
				state = State.SWEEP
				_state_t = 0.0
	queue_redraw()


func _pop_hold() -> float:
	if tempo:
		return TEMPO_GAP_SEC + 0.12
	return GAP_SEC + 0.2


func _on_tap(_pos: Vector2, _from_mouse: bool) -> void:
	if state != State.SWEEP or not is_running():
		return
	get_viewport().set_input_as_handled()
	var d: float = absf(t - center_t)
	if d <= perfect_half:
		_hit(1.0, "Golden!")
	elif d <= golden_half:
		_hit(0.85, "Nice!")
	else:
		_miss("Too raw!" if t < center_t else "Too toasty!")


func _hit(acc: float, text: String) -> void:
	var a: float = acc
	if retrying:
		a = minf(a, retry_cap)
		text = "Warm again!"
	_sfx("golden" if a >= 1.0 else "good")
	_record(a, text)


func _miss(text: String) -> void:
	if not retrying:
		retrying = true
		_sfx("cool")
		_pop_text = text
		_pop_acc = -1.0
		state = State.COOL
		_state_t = 0.0
		return
	_sfx("miss")
	_record(0.4, "Still tasty!")


func _record(acc: float, text: String) -> void:
	hit_scores.append(acc)
	var brown: float = clampf(t / dur, 0.0, 1.0) * (0.5 / maxf(center_t / dur, 0.01))
	brown = clampf(brown, 0.0, 1.0)
	hit_browns.append(brown)
	_pop_brown = brown
	_pop_acc = acc
	_pop_text = text
	_imprint_offset = Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * (1.0 - acc) * 8.0
	state = State.POP
	_state_t = 0.0
	if hit_scores.size() >= hits_total:
		var sum: float = 0.0
		var bsum: float = 0.0
		for i in range(hit_scores.size()):
			sum += hit_scores[i]
			bsum += hit_browns[i]
		extra = {
			"brown": bsum / float(hit_browns.size()),
			"browns": hit_browns.duplicate(),
			"hits": hit_scores.duplicate(),
		}
		state = State.DONE
		finish(sum / float(hit_scores.size()))


func _advance() -> void:
	hit_index += 1
	retrying = false
	t = 0.0
	_last_tick = -1
	state = State.SWEEP
	_state_t = 0.0


## Audio hook (cozy sounds are a follow-up). Override or connect later.
func _sfx(_id: String) -> void:
	pass


# --- Drawing ---------------------------------------------------------------------------------

func _ring_center() -> Vector2:
	var area: Rect2 = safe_rect()
	return Vector2(roundf(area.get_center().x), 82)


## 270-degree oven dial: starts bottom-left, golden centre (0.5) sits at the top.
const DIAL_START := PI * 0.75
const DIAL_SPAN := PI * 1.5


func _angle_at(time_v: float) -> float:
	return DIAL_START + DIAL_SPAN * clampf(time_v / dur, 0.0, 1.0)


static func brown_color(b: float) -> Color:
	if b <= 0.5:
		return RAW_COL.lerp(GOLD_COL, b / 0.5)
	return GOLD_COL.lerp(TOAST_COL, (b - 0.5) / 0.5)


func _current_brown() -> float:
	if state == State.POP or state == State.DONE:
		return _pop_brown
	if state == State.COOL:
		var k: float = clampf(_state_t / COOL_SEC, 0.0, 1.0)
		return lerpf(clampf(t / dur, 0.0, 1.0) * 0.5 / (center_t / dur), 0.1, k)
	return clampf(t / dur, 0.0, 1.0) * 0.5 / maxf(center_t / dur, 0.01)


func _draw() -> void:
	if not _started:
		return
	var c: Vector2 = _ring_center()
	var rm: bool = reduced_motion()
	# Porthole backing plate
	PixelDraw.shadow(self, c + Vector2(0, RING_R + 8), RING_R + 4, 3)
	PixelDraw.circle(self, c, RING_R + RING_W * 0.5 + 4, PixelDraw.CREAM)
	PixelDraw.circle(self, c, RING_R - RING_W * 0.5 - 1, PixelDraw.CREAM_DARK)
	# Zones (raw / golden / perfect / toasty)
	var rr: float = RING_R
	var a0: float = DIAL_START
	var a1: float = DIAL_START + DIAL_SPAN
	var outer: float = rr + RING_W * 0.5
	var inner: float = rr - RING_W * 0.5
	# Unlit track in oak so the dark-outlined knob reads against it.
	PixelDraw.ring(self, c, rr, RING_W, PixelDraw.OAK, a0, a1)
	PixelDraw.ring(self, c, rr, RING_W, Color(PixelDraw.OAK_DARK, 0.85), _angle_at(center_t + golden_half), a1)
	PixelDraw.ring(self, c, rr, RING_W, PixelDraw.HONEY, _angle_at(center_t - golden_half), _angle_at(center_t + golden_half))
	PixelDraw.ring(self, c, rr, RING_W, PixelDraw.HONEY_LIGHT, _angle_at(center_t - perfect_half), _angle_at(center_t + perfect_half))
	# Outlines of the dial + end caps + golden edges
	PixelDraw.ring(self, c, outer + 0.5, 1.0, PixelDraw.OUTLINE, a0, a1)
	PixelDraw.ring(self, c, inner - 0.5, 1.0, PixelDraw.OUTLINE, a0, a1)
	for edge in [0.0, dur, center_t - golden_half, center_t + golden_half]:
		var ea: float = _angle_at(edge)
		var dirv := Vector2(cos(ea), sin(ea))
		PixelDraw.line(self, c + dirv * (inner - 1.0), c + dirv * (outer + 1.0), PixelDraw.OUTLINE)
	# Raw / toasty end marks (dots) + star notch at golden centre (shape cue, not colour only)
	PixelDraw.disc(self, c + Vector2(cos(a0), sin(a0)) * (outer + 4), 1.5, PixelDraw.CREAM_DARK.darkened(0.2))
	PixelDraw.disc(self, c + Vector2(cos(a1), sin(a1)) * (outer + 4), 1.5, PixelDraw.OAK_DARK)
	var ga: float = _angle_at(center_t)
	var star_pos: Vector2 = c + Vector2(cos(ga), sin(ga)) * (outer + 6)
	var star_pulse: float = 0.0 if rm else 0.6 * maxf(0.0, 1.0 - absf(t - center_t) / maxf(golden_half * 2.0, 0.01))
	PixelDraw.star(self, star_pos, 4.0 + star_pulse, PixelDraw.HONEY)
	# Food in the porthole
	_draw_food(c, _current_brown())
	# Knob (needle)
	var knob_t: float = t
	if state == State.COOL:
		knob_t = lerpf(t, 0.0, clampf(_state_t / COOL_SEC, 0.0, 1.0))
	var ka: float = _angle_at(knob_t)
	var kd := Vector2(cos(ka), sin(ka))
	if state == State.SWEEP and knob_t > 0.0 and not rm:
		PixelDraw.ring(self, c, inner - 3.0, 1.0, Color(PixelDraw.OUTLINE, 0.3), a0, ka)
	var kp: Vector2 = c + kd * rr
	var in_gold: bool = absf(knob_t - center_t) <= golden_half
	var sweeping: bool = state == State.SWEEP
	if sweeping and in_gold:
		# Inside the golden zone: the whole zone lights up, so the moment to tap is felt.
		PixelDraw.ring(self, c, rr, RING_W, PixelDraw.HONEY_LIGHT, _angle_at(center_t - golden_half), _angle_at(center_t + golden_half))
	if sweeping and not rm:
		# Short trail behind the knob (two fading dots).
		for j in range(2):
			var tt: float = knob_t - dur * 0.035 * float(j + 1)
			if tt > 0.0:
				var ta: float = _angle_at(tt)
				PixelDraw.disc(self, c + Vector2(cos(ta), sin(ta)) * rr, 3.0, Color(PixelDraw.OUTLINE, 0.5 - 0.25 * float(j)))
	PixelDraw.disc(self, kp, 5.0, PixelDraw.OUTLINE)
	PixelDraw.disc(self, kp, 3.0, PixelDraw.CREAM)
	PixelDraw.disc(self, kp, 1.5, PixelDraw.HONEY if not (sweeping and in_gold) else PixelDraw.HONEY.darkened(0.25))
	if sweeping and in_gold and not rm:
		PixelDraw.sparkle(self, kp + Vector2(6, -6), 1, PixelDraw.CREAM)
	# Conveyor of hits
	if hits_total > 1:
		_draw_conveyor(c)
	if retrying and state == State.SWEEP:
		_bubble(c + Vector2(RING_R + 12, -RING_R + 2), "Retry", PixelDraw.CREAM)
	_draw_pop(c)


func _draw_food(c: Vector2, brown: float) -> void:
	var col: Color = brown_color(brown)
	match food:
		"stamp":
			_draw_stamp(c)
		"taiyaki":
			_draw_taiyaki(c, col)
		"pancake":
			_draw_pancake(c, col)
		"mochi":
			_draw_mochi(c)
		_:
			PixelDraw.circle(self, c + Vector2(0, 2), 13, col)
			for p in [Vector2(-5, -2), Vector2(4, -4), Vector2(-1, 5), Vector2(6, 4), Vector2(-7, 5)]:
				PixelDraw.disc(self, c + Vector2(0, 2) + p, 1.5, PixelDraw.COFFEE)
			if brown >= 0.35 and brown <= 0.7 and not reduced_motion() and state == State.SWEEP:
				PixelDraw.sparkle(self, c + Vector2(9, -9), 1, PixelDraw.CREAM)


func _draw_stamp(c: Vector2) -> void:
	var dough: Vector2 = c + Vector2(0, 7)
	PixelDraw.circle(self, dough, 12, RAW_COL)
	# Imprints from finished hits show on the current cookie only after its stamp lands.
	var show_print: bool = state == State.POP or state == State.DONE
	if show_print:
		PixelDraw.paw(self, dough + _imprint_offset, 5, Color(PixelDraw.OAK_DARK, 0.9))
	# The stamp descends as the knob approaches golden, bobbing back up after.
	var k: float = clampf(t / maxf(center_t, 0.01), 0.0, 2.0)
	var lift: float = 14.0 - 12.0 * (1.0 - absf(1.0 - k))
	if show_print:
		lift = 2.0 + 12.0 * clampf(_state_t / 0.3, 0.0, 1.0)
	if state == State.COOL:
		lift = 14.0
	var sp: Vector2 = dough + Vector2(0, -lift - 6)
	PixelDraw.outlined_rect(self, Rect2(sp.x - 9, sp.y - 2, 18, 5), PixelDraw.OAK)
	PixelDraw.outlined_rect(self, Rect2(sp.x - 2, sp.y - 9, 5, 8), PixelDraw.OAK_DARK)
	PixelDraw.circle(self, sp + Vector2(0.5, -10), 3, PixelDraw.OAK)


func _draw_taiyaki(c: Vector2, col: Color) -> void:
	var body := PackedVector2Array()
	for i in range(20):
		var a: float = TAU * float(i) / 20.0
		body.append(PixelDraw.snap(c + Vector2(cos(a) * 12, sin(a) * 8) + Vector2(-3, 1)))
	var tail := PackedVector2Array([c + Vector2(7, 1), c + Vector2(15, -6), c + Vector2(13, 1), c + Vector2(15, 8)])
	PixelDraw.outlined_poly(self, tail, col)
	PixelDraw.outlined_poly(self, body, col)
	PixelDraw.disc(self, c + Vector2(-10, -1), 1.2, PixelDraw.OUTLINE)
	for x in [-4, 0, 4]:
		PixelDraw.line(self, c + Vector2(x, -2), c + Vector2(x + 1, 0), col.darkened(0.25))
		PixelDraw.line(self, c + Vector2(x, 2), c + Vector2(x + 1, 4), col.darkened(0.25))


func _draw_pancake(c: Vector2, col: Color) -> void:
	# Pan
	PixelDraw.outlined_rect(self, Rect2(c.x - 18, c.y + 5, 36, 4), PixelDraw.COCOA.lightened(0.15))
	PixelDraw.outlined_rect(self, Rect2(c.x + 17, c.y + 6, 9, 2), PixelDraw.OAK_DARK)
	var squash: float = 1.0
	var hop: float = 0.0
	if (state == State.POP or state == State.DONE) and not reduced_motion():
		var k: float = clampf(_state_t / 0.35, 0.0, 1.0)
		hop = sin(k * PI) * 10.0
		squash = absf(cos(k * PI))
	var h: float = maxf(roundf(6.0 * squash), 1.0)
	PixelDraw.rounded_rect(self, Rect2(c.x - 14, c.y + 5 - h - hop, 28, h + 1), 2, col)


func _draw_mochi(c: Vector2) -> void:
	# Mortar (usu)
	PixelDraw.rounded_rect(self, Rect2(c.x - 16, c.y + 4, 32, 12), 3, PixelDraw.OAK)
	PixelDraw.px(self, Rect2(c.x - 14, c.y + 8, 28, 1), PixelDraw.OAK_DARK)
	# Mochi gets smoother with good hits
	var lumps: float = 2.0
	for s in hit_scores:
		lumps -= 0.5 * s
	lumps = maxf(lumps, 0.0)
	var blob := PackedVector2Array()
	for i in range(18):
		var a: float = PI + PI * float(i) / 17.0
		var r: float = 13.0 + (sin(a * 5.0) * lumps)
		blob.append(PixelDraw.snap(c + Vector2(0, 5) + Vector2(cos(a) * 14.0, sin(a) * r * 0.75)))
	PixelDraw.outlined_poly(self, blob, MOCHI_COL)
	# Mallet (kine): rises then swings down as the knob reaches golden.
	var k: float = clampf(t / maxf(center_t, 0.01), 0.0, 1.0)
	var down: bool = state == State.POP or state == State.DONE
	var head_y: float = c.y - 22.0 + (k * 14.0 if not down else 18.0)
	if state == State.COOL:
		head_y = c.y - 22.0
	var hx: float = c.x + 6
	PixelDraw.outlined_rect(self, Rect2(hx + 6, head_y - 9, 3, 16), PixelDraw.OAK_DARK)
	PixelDraw.rounded_rect(self, Rect2(hx - 6, head_y - 2, 16, 8), 2, PixelDraw.OAK)


func _draw_conveyor(c: Vector2) -> void:
	var n: int = hits_total
	var spacing: float = 16.0
	var y: float = c.y + RING_R + 18
	var x0: float = c.x - spacing * float(n - 1) * 0.5
	for i in range(n):
		var p := Vector2(roundf(x0 + spacing * i), y)
		var done_i: bool = i < hit_scores.size()
		var col: Color = MOCHI_COL if food == "mochi" else (brown_color(hit_browns[i]) if done_i and food != "stamp" else RAW_COL)
		PixelDraw.circle(self, p, 5, col)
		if done_i:
			if food == "stamp":
				PixelDraw.paw(self, p, 2.5, PixelDraw.OAK_DARK)
			var stars: int = _stars_for(hit_scores[i])
			for s in range(stars):
				PixelDraw.disc(self, p + Vector2(-3 + s * 3, -8), 1.0, PixelDraw.HONEY)
		elif i == hit_index and state != State.DONE:
			PixelDraw.line(self, p + Vector2(-2, -9), p + Vector2(2, -9), PixelDraw.CREAM)
			PixelDraw.line(self, p + Vector2(-1, -8), p + Vector2(1, -8), PixelDraw.CREAM)
			PixelDraw.line(self, p + Vector2(0, -7), p + Vector2(0, -7), PixelDraw.CREAM)


static func _stars_for(acc: float) -> int:
	if acc >= 0.99:
		return 3
	if acc >= 0.85:
		return 2
	if acc >= 0.65:
		return 1
	return 0


func _draw_pop(c: Vector2) -> void:
	var show: bool = state == State.POP or state == State.DONE or state == State.COOL
	if not show or _pop_text == "":
		return
	var k: float = clampf(_state_t / POP_SEC, 0.0, 1.0)
	var rm: bool = reduced_motion()
	if state != State.COOL and _pop_acc >= 0.85 and not rm and k < 1.0:
		var n: int = 8 if _pop_acc >= 1.0 else 5
		for i in range(n):
			var a: float = TAU * float(i) / float(n) + 0.3
			var dist: float = 14.0 + 16.0 * k
			PixelDraw.sparkle(self, c + Vector2(cos(a), sin(a)) * dist, 2 if i % 2 == 0 else 1, PixelDraw.HONEY_LIGHT if i % 2 == 0 else PixelDraw.CREAM)
	if state != State.COOL and _pop_acc >= 0.0:
		var stars: int = _stars_for(_pop_acc)
		var lift: float = 0.0 if rm else roundf(4.0 * k)
		for s in range(stars):
			PixelDraw.star(self, c + Vector2(-9 + s * 9, RING_R - 2 - lift), 3.5, PixelDraw.HONEY)
	var bubble_col: Color = PixelDraw.CREAM_DARK if state == State.COOL else PixelDraw.CREAM
	_bubble(c + Vector2(RING_R + 12, -RING_R + 2), _pop_text, bubble_col)
	if state == State.COOL:
		_bubble(c + Vector2(RING_R + 12, -RING_R + 17), "it cooled a bit", PixelDraw.CREAM)


func _bubble(pos: Vector2, s: String, col: Color) -> void:
	var w: float = PixelDraw.text_width(s) + 8
	var area: Rect2 = safe_rect()
	var x: float = minf(pos.x, area.end.x - w)
	var r := Rect2(x, pos.y, w, 13)
	PixelDraw.rounded_rect(self, r, 3, col)
	PixelDraw.text(self, r.position + Vector2(4, 10), s, PixelDraw.OUTLINE, 8)
