extends "res://Scripts/minigame/cooking/steps/StepBase.gd"

## BACK_BURNER verb: a parallel timer that cooks in the top-right burner slot while later cards
## play (oven, iron, pearls, espresso shot). Contract + params: Docs/MINIGAMES.md.
##
## Owned by CookingGame's BurnerLayer (a later sibling of StepLayer), so it sees input before
## the active card. It consumes ONLY clicks inside its ring (so they never count as a tap on the
## card) and the O key; Space and other clicks pass through to the card untouched.
## It also works as a plain card (e.g. in a test harness) because it only draws in slot_rect().
##
## Timeline (cook_sec = _roll.cook_sec; windows x window_scale()):
##   cooking  [0, cook)                          collecting does nothing ("not yet" wiggle)
##   ready    [cook, cook + done_window_sec)      -> 1.0  (glows, sparkles)
##   good     [.., + good_window_sec)             -> 0.65
##   late     after that, forever                 -> 0.4  "still tasty" - nothing ever burns
## Collect: click the ring or press O. A 0.4 s pop plays in the slot, then finish(acc, t) is
## called with t = the collect time (the pop does not count).
## get_burner_info() feeds the host header's burner slot.

signal sfx(id: String) ## Sound hooks: "ready", "not_yet", "collect", "pop".

const POP_SEC := 0.4
const RING_R := 16.0
const HIT_R := 21.0

var cook_sec: float = 8.0
var done_window: float = 1.2
var good_window: float = 1.3
var item: String = "pot"

var collected: bool = false
var collect_time: float = -1.0
var collect_acc: float = -1.0
var _pop_t: float = -1.0
var _wiggle_t: float = -1.0
var _anim_t: float = 0.0
var _ready_announced: bool = false


func _on_start() -> void:
	cook_sec = maxf(float(roll("cook_sec", params.get("cook_sec", 8.0))), 0.1)
	done_window = maxf(float(params.get("done_window_sec", 1.2)) * window_scale(), 0.05)
	good_window = maxf(float(params.get("good_window_sec", 1.3)) * window_scale(), 0.05)
	item = String(params.get("item", "pot"))
	extra = {"cook_sec": cook_sec}


# --- State -----------------------------------------------------------------------------------

## "cooking" | "ready" | "good" | "late" at time t (defaults to now).
func state_at(t: float) -> String:
	if t < cook_sec:
		return "cooking"
	if t < cook_sec + done_window:
		return "ready"
	if t < cook_sec + done_window + good_window:
		return "good"
	return "late"


func state() -> String:
	return state_at(collect_time if collected else elapsed)


## Accuracy if collected at time t (cooking -> -1: cannot collect yet).
func accuracy_at(t: float) -> float:
	match state_at(t):
		"ready":
			return 1.0
		"good":
			return 0.65
		"late":
			return 0.4
	return -1.0


func can_collect() -> bool:
	return is_running() and not collected and elapsed >= cook_sec


func get_burner_info() -> Dictionary:
	var st: String = state()
	return {
		"state": st,
		"progress": clampf(elapsed / cook_sec, 0.0, 1.0) if st == "cooking" else 1.0,
	}


# --- Input -----------------------------------------------------------------------------------

func _on_tap(play_pos: Vector2, from_mouse: bool) -> void:
	if not from_mouse or not is_running():
		return
	var c: Vector2 = slot_rect().get_center()
	if _local(play_pos).distance_to(c) > HIT_R:
		return
	# A click on our ring never reaches the card, even while cooking.
	get_viewport().set_input_as_handled()
	_try_collect()


func _on_burner_key() -> void:
	if not is_running():
		return
	get_viewport().set_input_as_handled()
	_try_collect()


func _local(play_pos: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * play_pos


func _try_collect() -> bool:
	if collected:
		return false
	if elapsed < cook_sec:
		_wiggle_t = 0.0
		sfx.emit("not_yet")
		queue_redraw()
		return false
	collected = true
	collect_time = elapsed
	collect_acc = accuracy_at(collect_time)
	extra = {"cook_sec": snappedf(cook_sec, 0.01), "late_sec": snappedf(maxf(collect_time - cook_sec, 0.0), 0.01), "state": state_at(collect_time)}
	sfx.emit("collect")
	if reduced_motion():
		_finish_now()
	else:
		_pop_t = 0.0
	queue_redraw()
	return true


func _finish_now() -> void:
	sfx.emit("pop")
	finish(collect_acc, collect_time)


# --- Frame -----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_anim_t += delta
	if _wiggle_t >= 0.0:
		_wiggle_t += delta
		if _wiggle_t > 0.3:
			_wiggle_t = -1.0
	if _pop_t >= 0.0 and is_running():
		_pop_t += delta
		if _pop_t >= POP_SEC:
			_finish_now()
	if is_running() and not collected and not _ready_announced and elapsed >= cook_sec:
		_ready_announced = true
		sfx.emit("ready")
	queue_redraw()


# --- Drawing ---------------------------------------------------------------------------------

func _draw() -> void:
	var s: Rect2 = slot_rect()
	var c: Vector2 = s.get_center()
	var st: String = state()
	var shake := Vector2.ZERO
	if _wiggle_t >= 0.0 and not reduced_motion():
		shake.x = roundf(sin(_wiggle_t * 60.0) * 1.5)
	var cc: Vector2 = c + shake
	var glow: bool = st == "ready" and not collected
	# Base plate.
	PixelDraw.circle(self, cc, RING_R + 3, PixelDraw.CREAM)
	PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.CREAM_DARK)
	# Progress / window ring.
	match st:
		"cooking":
			var p: float = clampf(elapsed / cook_sec, 0.0, 1.0)
			PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.HONEY, -PI * 0.5, -PI * 0.5 + TAU * p)
		"ready":
			PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.SAGE)
		"good":
			var left: float = 1.0 - clampf((elapsed - cook_sec - done_window) / good_window, 0.0, 1.0)
			PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.HONEY_LIGHT)
			if not collected:
				PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.HONEY, -PI * 0.5, -PI * 0.5 + TAU * left)
		"late":
			PixelDraw.ring(self, cc, RING_R, 4.0, PixelDraw.OAK)
	_draw_item(cc, st)
	if glow:
		var pulse: float = 0.0 if reduced_motion() else roundf((sin(_anim_t * 8.0) + 1.0) * 1.0)
		PixelDraw.ring(self, cc, RING_R + 4 + pulse, 1.0, PixelDraw.SAGE_DARK)
		if not reduced_motion():
			for k in range(4):
				var a: float = _anim_t * 2.5 + float(k) * TAU / 4.0
				PixelDraw.sparkle(self, cc + Vector2(cos(a), sin(a)) * (RING_R + 6), 1, PixelDraw.HONEY_LIGHT)
	# Status tag under the slot (outside the card's safe rect).
	if not collected:
		_draw_tag(Vector2(c.x, s.end.y + 9), st)
	else:
		_draw_collected(cc)
	if _pop_t >= 0.0:
		_draw_pop(cc)


func _draw_tag(top_center: Vector2, st: String) -> void:
	var label: String = ""
	var fill: Color = PixelDraw.CREAM
	match st:
		"cooking":
			label = "%ds" % int(ceilf(maxf(cook_sec - elapsed, 0.0)))
		"ready":
			label = "Ready!"
			fill = PixelDraw.SAGE
		"good":
			label = "Good"
			fill = PixelDraw.HONEY_LIGHT
		"late":
			label = "Tasty"
			fill = PixelDraw.CREAM_DARK
	var w: float = 42.0 if PixelDraw.legacy() else maxf(42.0, PixelDraw.text_width(label) + 20.0)
	var r := Rect2(roundf(top_center.x - w * 0.5), top_center.y - 6, w, 12)
	PixelDraw.rounded_rect(self, r, 2, fill)
	PixelDraw.text(self, r.position + Vector2(3, 9), label, PixelDraw.OUTLINE, 8)
	# O keycap.
	var k := Rect2(r.end.x - 12, r.position.y + 1, 11, 10)
	PixelDraw.rounded_rect(self, k, 2, PixelDraw.CREAM)
	PixelDraw.text(self, k.position + Vector2(3, 8), "O", PixelDraw.OUTLINE, 8)


func _draw_collected(cc: Vector2) -> void:
	var stars: int = 3 if collect_acc >= 0.95 else (2 if collect_acc >= 0.6 else 1)
	for i in range(3):
		PixelDraw.star(self, cc + Vector2(-9 + i * 9, RING_R + 12), 3, PixelDraw.HONEY if i < stars else PixelDraw.CREAM_DARK)


func _draw_pop(cc: Vector2) -> void:
	var t: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
	for k in range(6):
		var a: float = float(k) * TAU / 6.0 - PI * 0.5
		var rr: float = RING_R + 2.0 + t * 10.0
		if k % 2 == 0:
			PixelDraw.star(self, cc + Vector2(cos(a), sin(a)) * rr, 3.0 + (1.0 - t) * 1.5, PixelDraw.HONEY_LIGHT)
		else:
			PixelDraw.sparkle(self, cc + Vector2(cos(a), sin(a)) * rr, 1, PixelDraw.CREAM)


func _draw_item(cc: Vector2, st: String) -> void:
	var done: bool = st != "cooking"
	var steam: bool = not reduced_motion() and not collected
	match item:
		"iron":
			# Fish-shaped taiyaki iron, seen from above: two hinged plates + handle.
			PixelDraw.line(self, cc + Vector2(6, 0), cc + Vector2(11, 0), PixelDraw.OUTLINE, 2.0)
			PixelDraw.rounded_rect(self, Rect2(cc.x - 9, cc.y - 6, 15, 12), 4, PixelDraw.OAK_DARK if not done else PixelDraw.HONEY)
			draw_colored_polygon(PackedVector2Array([cc + Vector2(-6, 0), cc + Vector2(-2, -3), cc + Vector2(2, 0), cc + Vector2(-2, 3)]), PixelDraw.OAK if not done else PixelDraw.HONEY_LIGHT)
		"portafilter":
			# Espresso cup filling under the portafilter.
			var fill: float = clampf(elapsed / cook_sec, 0.0, 1.0) if not done else 1.0
			PixelDraw.rounded_rect(self, Rect2(cc.x - 7, cc.y - 9, 14, 4), 1, PixelDraw.OAK_DARK)
			PixelDraw.mug(self, cc + Vector2(-1, 8), 10, 10, PixelDraw.CREAM, PixelDraw.COFFEE, fill)
			if not done and steam:
				var dy: float = fmod(_anim_t * 10.0, 6.0)
				PixelDraw.px(self, Rect2(cc.x - 1, cc.y - 5 + dy, 1, 2), PixelDraw.COFFEE)
		_:
			# Pot with pearls.
			PixelDraw.rounded_rect(self, Rect2(cc.x - 9, cc.y - 4, 18, 12), 3, PixelDraw.SAGE_DARK if not done else PixelDraw.SAGE)
			draw_rect(Rect2(cc.x - 11, cc.y - 4, 22, 2), PixelDraw.OUTLINE, true)
			for i in range(3):
				var bob: float = 0.0 if not steam else roundf(sin(_anim_t * 5.0 + float(i) * 1.7))
				PixelDraw.disc(self, cc + Vector2(-5 + i * 5, 1 + bob), 1.6, PixelDraw.COCOA)
	if steam:
		for i in range(2):
			var ph: float = fmod(_anim_t * 0.9 + float(i) * 0.5, 1.0)
			var p: Vector2 = cc + Vector2(-3 + i * 6, -8 - ph * 7.0)
			draw_rect(Rect2(PixelDraw.snap(p), Vector2(1, 2)), Color(PixelDraw.CREAM, 1.0 - ph), true)
