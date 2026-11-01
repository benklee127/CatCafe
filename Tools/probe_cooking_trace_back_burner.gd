extends SceneTree

## Headless probe for the TRACE and BACK_BURNER cooking verbs.
## Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_trace_back_burner.gd
## Exit code 0 when every check passes, 1 otherwise.
##
## Every case is driven with real simulated input (Input.parse_input_event: LMB, mouse motion,
## Space, arrows, O), at _play_scale 3 like the 1600x900 overlay.
##   paths   : every TracePaths shape builds a long-enough path that fits the cup.
##   trace   : mouse perfect / okay / bad / partial / idle, leniency, magnet, hold-to-toggle,
##             keyboard auto-pen steered vs unsteered; accuracy bands + coverage cap + extra.art.
##   burner  : perfect / good / late / early press / ring click vs outside click / Space passes
##             through / leniency widens the window / reduced motion / get_burner_info states.
##   game    : a real CookingGame run (burner + trace): the burner in the BurnerLayer slot
##             swallows its ring click so the trace card never sees it, O collects it mid-trace,
##             and the recorded results match.

const TRACE := "res://Scripts/minigame/cooking/steps/TraceStep.gd"
const BURNER := "res://Scripts/minigame/cooking/steps/BackBurnerStep.gd"
const PATHS := "res://Scripts/minigame/cooking/TracePaths.gd"
const COOKING_GAME := "res://Scripts/minigame/cooking/CookingGame.gd"
const SCALE := 3
const DT := 1.0 / 60.0

class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("%s %s %s (%s:%d %s)" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", code, rationale, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Earlier sibling of the step under test: counts the primary presses that reach it
## (i.e. that the step did NOT mark handled).
class Catcher extends Node:
	var clicks: int = 0
	var spaces: int = 0

	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			clicks += 1
		elif e is InputEventKey and (e as InputEventKey).pressed and not (e as InputEventKey).echo and (e as InputEventKey).keycode == KEY_SPACE:
			spaces += 1


var _fails: Array[String] = []
var _passes: int = 0
var _logger := ErrorCounter.new()
var _paths: Script
var _mouse := Vector2.ZERO
var _last: Dictionary = {}
var _report: Array[String] = []


func _initialize() -> void:
	OS.add_logger(_logger)
	Input.use_accumulated_input = false
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails.append(what)
		print("FAIL: ", what)


func _band(v: float, lo: float, hi: float, what: String) -> void:
	_check(v >= lo - 0.0001 and v <= hi + 0.0001, "%s: %.3f in [%.2f, %.2f]" % [what, v, lo, hi])
	_report.append("%-44s %.3f" % [what, v])


func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame


# --- Input helpers ----------------------------------------------------------------------------

## Play/root-viewport coords -> window coords (headless root is 64x64 with a 1600x900 content
## scale, so events are scaled by the stretch transform on the way in).
func _win(pos: Vector2) -> Vector2:
	return root.get_final_transform() * pos


func _btn(pos: Vector2, pressed: bool) -> void:
	_mouse = pos
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _win(pos)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(e)


func _move(pos: Vector2, held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _win(pos)
	e.global_position = e.position
	e.relative = e.position - _win(_mouse)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	_mouse = pos
	Input.parse_input_event(e)


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _release_all_keys() -> void:
	for k in [KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_O]:
		if Input.is_key_pressed(k):
			_key(k, false)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_btn(_mouse, false)


# --- Step factories -----------------------------------------------------------------------------

func _trace_params(shape: String, more: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {
		"_type": "trace", "_label": "Latte art", "_index": 0, "_tier": 1, "_window_mult": 1.0,
		"_roll": {"shape": shape}, "_play_scale": SCALE, "_safe_rect": Rect2(8, 8, 256, 164),
		"_slot_rect": Rect2(272, 4, 44, 44), "_reduced_motion": false, "_prev": [],
		"path_pool": [shape], "time_sec": 4.5, "tolerance_px": 14, "min_coverage": 0.8,
		"coverage_cap": 0.6, "ink": "#FBF3E4", "canvas": "#7A4E33",
	}
	p.merge(more, true)
	return p


func _make(script_path: String, params: Dictionary, leniency: float = 1.0, toggle: bool = false, before: Node = null) -> Node2D:
	var node: Node2D = (load(script_path) as Script).new()
	if before != null:
		root.add_child(before)
	root.add_child(node)
	node.set("hold_to_toggle", toggle)
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	node.call("start", params, leniency, r)
	_last = {}
	node.connect("done", func(acc: float, t: float) -> void: _last = {"acc": acc, "time": t})
	return node


func _free(nodes: Array) -> void:
	_release_all_keys()
	await _frames(2)
	for n in nodes:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await _frames(2)


func _wait_done(max_frames: int = 900) -> bool:
	var f: int = 0
	while _last.is_empty() and f < max_frames:
		await process_frame
		f += 1
	return not _last.is_empty()


# --- Run ----------------------------------------------------------------------------------------

func _run() -> void:
	_paths = load(PATHS)
	_check(_paths != null, "TracePaths loads")
	_check(load(TRACE) != null, "TraceStep loads")
	_check(load(BURNER) != null, "BackBurnerStep loads")
	if not _fails.is_empty():
		_finish()
		return
	_check_paths()
	await _check_trace_mouse()
	await _check_trace_keyboard()
	await _check_trace_misc()
	await _check_burner()
	await _check_game()
	_finish()


func _finish() -> void:
	print("--- accuracy report ---")
	for l in _report:
		print("  ", l)
	var own: Array[String] = []
	for l in _logger.lines:
		if l.contains("TraceStep") or l.contains("BackBurnerStep") or l.contains("TracePaths") or l.contains("probe_cooking_trace"):
			own.append(l)
	for l in own:
		print("OWN LOG: ", l)
	_check(own.is_empty(), "no ERROR/WARNING lines from the trace/back-burner files")
	print("probe_cooking_trace_back_burner: %d passed, %d failed" % [_passes, _fails.size()])
	quit(0 if _fails.is_empty() else 1)


func _check_paths() -> void:
	var cup := Rect2(136 - 48, 102 - 48, 96, 96)
	for shape in _paths.get("SHAPES"):
		var p: Dictionary = _paths.call("build", shape, Vector2(136, 102), 36.0)
		var pts: PackedVector2Array = p["points"]
		var inside: bool = true
		for q in pts:
			if not cup.has_point(q):
				inside = false
		_check(float(p["length"]) > 120.0 and pts.size() > 60, "path %s is long enough (%.0f px)" % [shape, float(p["length"])])
		_check(inside, "path %s fits inside the cup" % shape)
	var bad: Dictionary = _paths.call("build", "no_such_shape", Vector2(136, 102), 36.0)
	_check(String(bad["name"]) == "paw", "unknown shape falls back to paw")
	var bt: Dictionary = _paths.call("build", "bow_tie", Vector2(136, 102), 36.0)
	_check(is_equal_approx(float(bt["split"]), 0.5), "bow tie has a two-tone split")


## Drives a mouse trace: press at the start, follow the path at `pace` (share of time_sec),
## offset `off_fn(s) -> float` art px along the normal, stop after `cover` of the length and
## release. Returns the accuracy (or -1 on timeout).
func _mouse_trace(step: Node2D, off_fn: Callable, cover: float = 1.0, pace: float = 0.7, toggle: bool = false) -> float:
	var path: Dictionary = step.get("path")
	var total: float = float(path["length"])
	var speed: float = total / (4.5 * pace)
	var s: float = 0.0
	var start: Vector2 = _on_path(path, 0.0, float(off_fn.call(0.0)))
	_move(start, false)
	await process_frame
	_btn(start, true)
	if toggle:
		await process_frame
		_btn(start, false)
	await process_frame
	while s < total * cover and _last.is_empty():
		s = minf(s + speed * DT, total * cover)
		_move(_on_path(path, s, float(off_fn.call(s))), not toggle)
		await process_frame
	if _last.is_empty():
		_btn(_mouse, true if toggle else false)
		if toggle:
			await process_frame
			_btn(_mouse, false)
	var ok: bool = await _wait_done()
	return float(_last.get("acc", -1.0)) if ok else -1.0


func _on_path(path: Dictionary, s: float, off: float) -> Vector2:
	var p: Vector2 = _paths.call("point_at", path, s)
	var n: Vector2 = (_paths.call("tangent_at", path, s) as Vector2).orthogonal()
	return p + n * off


func _check_trace_mouse() -> void:
	var zero := func(_s: float) -> float: return 0.0
	# Perfect.
	for shape in ["cat_face", "paw", "fish", "spiral", "bow_tie"]:
		var st: Node2D = _make(TRACE, _trace_params(shape))
		var acc: float = await _mouse_trace(st, zero)
		_band(acc, 0.95, 1.0, "trace mouse perfect %s" % shape)
		_check(float(st.call("coverage")) >= 0.98, "perfect %s covers the path" % shape)
		var ex: Dictionary = st.get("extra")
		_check(ex.get("art", []) is Array and not (ex.get("art", []) as Array).is_empty(), "perfect %s exports extra.art" % shape)
		_check(float(_last.get("time", 0.0)) > 1.0 and float(_last.get("time", 0.0)) < 5.0, "perfect %s reports a sane time (%.2f)" % [shape, float(_last.get("time", 0.0))])
		await _free([st])
	# Okay: a steady 1.6 art px (4.8 screen px) off the line -> ~0.66.
	var okay := func(_s: float) -> float: return 1.6
	var s2: Node2D = _make(TRACE, _trace_params("cat_face"))
	var acc_okay: float = await _mouse_trace(s2, okay)
	_band(acc_okay, 0.58, 0.75, "trace mouse okay (4.8 screen px off)")
	await _free([s2])
	# Okay, wobbly hand: +-2 art px sine.
	var wob := func(s: float) -> float: return 2.0 * sin(s * 0.25)
	var s3: Node2D = _make(TRACE, _trace_params("paw"))
	_band(await _mouse_trace(s3, wob), 0.5, 0.8, "trace mouse wobbly (+-6 screen px)")
	await _free([s3])
	# Bad: 3.5 art px off and gives up at half the path -> coverage cap.
	var bad := func(_s: float) -> float: return 3.5
	var s4: Node2D = _make(TRACE, _trace_params("cat_face"))
	var acc_bad: float = await _mouse_trace(s4, bad, 0.5)
	_band(acc_bad, 0.25, 0.3, "trace mouse bad (10.5 px off, half covered)")
	_check(float(s4.call("coverage")) < 0.8, "bad trace coverage < 0.8")
	await _free([s4])
	# Perfect line but only 60% of it: capped at coverage_cap.
	var s5: Node2D = _make(TRACE, _trace_params("cat_face"))
	_band(await _mouse_trace(s5, zero, 0.6), 0.6, 0.6, "trace mouse perfect but 60% covered (cap)")
	await _free([s5])
	# Way off (12 art px): nothing covered, floor.
	var far := func(_s: float) -> float: return 12.0
	var s6: Node2D = _make(TRACE, _trace_params("loaf"))
	_band(await _mouse_trace(s6, far), 0.25, 0.25, "trace mouse far off (floor)")
	await _free([s6])
	# Leniency 2.0 (Sleepy) forgives the same okay line.
	var s7: Node2D = _make(TRACE, _trace_params("cat_face"), 2.0)
	var acc_len: float = await _mouse_trace(s7, okay, 1.0, 1.2)
	_band(acc_len, 0.78, 0.9, "trace mouse okay at leniency 2.0")
	_check(acc_len > acc_okay + 0.1, "leniency raises trace accuracy")
	await _free([s7])
	# Magnet: 2.5 art px (7.5 screen px) off snaps onto the path.
	var mag := func(_s: float) -> float: return 2.5
	var s8: Node2D = _make(TRACE, _trace_params("cat_face", {"magnet": true}))
	_band(await _mouse_trace(s8, mag), 0.95, 1.0, "trace mouse 7.5 px off with magnet")
	await _free([s8])
	var s8b: Node2D = _make(TRACE, _trace_params("cat_face"))
	_band(await _mouse_trace(s8b, mag), 0.3, 0.55, "trace mouse 7.5 px off without magnet")
	await _free([s8b])
	# Hold-to-toggle: tap to start, tap to stop.
	var s9: Node2D = _make(TRACE, _trace_params("heart"), 1.0, true)
	_band(await _mouse_trace(s9, zero, 1.0, 0.7, true), 0.95, 1.0, "trace hold-to-toggle perfect")
	await _free([s9])
	# Two-tone bow tie colours the second wing with ink2.
	var s10: Node2D = _make(TRACE, _trace_params("bow_tie", {"ink": "#FFF6EA", "ink2": "#4A3426", "canvas": "#C9A27A"}))
	await _mouse_trace(s10, zero)
	var cols := {}
	for stk in s10.get("strokes"):
		for c in (stk["cols"] as PackedColorArray):
			cols[c.to_html(false)] = true
	_check(cols.has("fff6ea") and cols.has("4a3426"), "two-tone bow tie draws both inks (%s)" % str(cols.keys()))
	await _free([s10])


## Keyboard: hold Space; steer with the arrow that best pushes the pen back across the path.
func _kb_trace(step: Node2D, steer: bool) -> float:
	var held: Dictionary = {}
	_key(KEY_SPACE, true)
	var f: int = 0
	while _last.is_empty() and f < 600:
		await process_frame
		f += 1
		var want: Dictionary = {}
		if steer and _last.is_empty():
			var off: float = float(step.get("kb_off"))
			if absf(off) > 0.4:
				var n: Vector2 = step.call("kb_normal")
				var d: Vector2 = -n * signf(off)
				if absf(d.x) >= 0.35:
					want[KEY_RIGHT if d.x > 0.0 else KEY_LEFT] = true
				if absf(d.y) >= 0.35:
					want[KEY_DOWN if d.y > 0.0 else KEY_UP] = true
		for k in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var w: bool = want.has(k)
			if w != held.has(k):
				_key(k, w)
				if w:
					held[k] = true
				else:
					held.erase(k)
	_key(KEY_SPACE, false)
	for k in held.keys():
		_key(k, false)
	return float(_last.get("acc", -1.0))


func _check_trace_keyboard() -> void:
	var steered: Array[float] = []
	var loose: Array[float] = []
	for shape in ["cat_face", "spiral", "zigzag"]:
		var a: Node2D = _make(TRACE, _trace_params(shape))
		await process_frame
		var acc_a: float = await _kb_trace(a, true)
		steered.append(acc_a)
		_band(acc_a, 0.85, 1.0, "trace keyboard steered %s" % shape)
		_check(bool((a.get("extra") as Dictionary).get("keyboard", false)), "keyboard trace flags extra.keyboard")
		await _free([a])
		var b: Node2D = _make(TRACE, _trace_params(shape))
		await process_frame
		var acc_b: float = await _kb_trace(b, false)
		loose.append(acc_b)
		_band(acc_b, 0.25, 0.8, "trace keyboard unsteered %s" % shape)
		await _free([b])
	var ms: float = 0.0
	var ml: float = 0.0
	for i in range(steered.size()):
		ms += steered[i]
		ml += loose[i]
	_check(ms > ml + 0.3, "steering beats drifting (%.2f vs %.2f summed)" % [ms, ml])


func _check_trace_misc() -> void:
	# Idle: never touches it -> grace (3 s) + time (4.5 s) -> floor.
	var st: Node2D = _make(TRACE, _trace_params("paw", {"time_sec": 1.0}))
	var ok: bool = await _wait_done(400)
	_check(ok, "idle trace times out on its own")
	_band(float(_last.get("acc", -1.0)), 0.25, 0.25, "trace idle (floor)")
	await _free([st])
	# Lifting early (coverage < 0.9) does not end it; the clock does.
	var s2: Node2D = _make(TRACE, _trace_params("circle", {"time_sec": 2.5}))
	var zero := func(_s: float) -> float: return 0.0
	var acc: float = await _mouse_trace(s2, zero, 0.7, 0.4)
	_check(float(s2.get("draw_t")) >= 2.49, "early lift waited for the clock (draw_t %.2f)" % float(s2.get("draw_t")))
	_band(acc, 0.6, 0.6, "trace 70% then lift (cap)")
	await _free([s2])
	# Unknown roll shape still plays (paw fallback).
	var s3: Node2D = _make(TRACE, _trace_params("teapot"))
	_check(String(s3.get("shape")) == "paw", "unknown trace shape falls back to paw")
	await _free([s3])


# --- Burner -------------------------------------------------------------------------------------

func _burner_params(cook: float, more: Dictionary = {}) -> Dictionary:
	var p: Dictionary = {
		"_type": "back_burner", "_label": "Close the iron", "_index": 1, "_tier": 1, "_window_mult": 1.0,
		"_roll": {"cook_sec": cook}, "_play_scale": SCALE, "_safe_rect": Rect2(8, 8, 256, 164),
		"_slot_rect": Rect2(272, 4, 44, 44), "_reduced_motion": false, "_prev": [],
		"cook_range": [cook, cook], "done_window_sec": 1.2, "good_window_sec": 1.3, "item": "iron",
	}
	p.merge(more, true)
	return p


func _until_elapsed(node: Node2D, t: float) -> void:
	var f: int = 0
	while float(node.get("elapsed")) < t and f < 2000:
		await process_frame
		f += 1


func _ring_click(node: Node2D) -> void:
	var c: Vector2 = (node.call("slot_rect") as Rect2).get_center()
	_btn(c + Vector2(3, -2), true)
	await process_frame
	_btn(c + Vector2(3, -2), false)
	await process_frame


func _check_burner() -> void:
	# Perfect: O shortly after it is ready.
	var cat := Catcher.new()
	var b: Node2D = _make(BURNER, _burner_params(1.0), 1.0, false, cat)
	_check(String((b.call("get_burner_info") as Dictionary)["state"]) == "cooking", "burner starts cooking")
	await _until_elapsed(b, 0.4)
	_key(KEY_O, true)
	await process_frame
	_key(KEY_O, false)
	await process_frame
	_check(not bool(b.get("collected")) and b.call("is_running"), "early O does not collect")
	await _ring_click(b)
	_check(not bool(b.get("collected")), "early ring click does not collect")
	_check(cat.clicks == 0, "ring click while cooking is swallowed (card never sees it)")
	_btn(Vector2(140, 100), true)
	await process_frame
	_btn(Vector2(140, 100), false)
	await process_frame
	_check(cat.clicks == 1 and not bool(b.get("collected")), "click outside the ring passes through")
	_key(KEY_SPACE, true)
	await process_frame
	_key(KEY_SPACE, false)
	await process_frame
	_check(cat.spaces == 1 and not bool(b.get("collected")), "Space passes through to the card")
	await _until_elapsed(b, 1.3)
	_check(String((b.call("get_burner_info") as Dictionary)["state"]) == "ready", "burner glows ready")
	_key(KEY_O, true)
	await process_frame
	_key(KEY_O, false)
	_check(await _wait_done(120), "O collects the ready burner")
	_band(float(_last.get("acc", -1.0)), 1.0, 1.0, "burner perfect (O at +0.3 s)")
	_check(absf(float(_last.get("time", 0.0)) - 1.3) < 0.1, "burner time is the collect time, not the pop (%.2f)" % float(_last.get("time", 0.0)))
	await _free([b, cat])
	# Good: ring click at +1.8 s.
	var b2: Node2D = _make(BURNER, _burner_params(1.0))
	await _until_elapsed(b2, 2.8)
	_check(String((b2.call("get_burner_info") as Dictionary)["state"]) == "good", "burner in good window")
	await _ring_click(b2)
	_check(await _wait_done(120), "ring click collects")
	_band(float(_last.get("acc", -1.0)), 0.65, 0.65, "burner good (+1.8 s)")
	await _free([b2])
	# Late: +5 s -> still tasty, never burns.
	var b3: Node2D = _make(BURNER, _burner_params(1.0, {"item": "pot"}))
	await _until_elapsed(b3, 6.0)
	_check(String((b3.call("get_burner_info") as Dictionary)["state"]) == "late", "burner late (never burns)")
	_key(KEY_O, true)
	await process_frame
	_key(KEY_O, false)
	_check(await _wait_done(120), "late collect works")
	_band(float(_last.get("acc", -1.0)), 0.4, 0.4, "burner late (+5 s, still tasty)")
	await _free([b3])
	# Leniency 2.0 doubles the done window: +2.0 s is still perfect.
	var b4: Node2D = _make(BURNER, _burner_params(1.0, {"item": "portafilter"}), 2.0)
	await _until_elapsed(b4, 3.0)
	await _ring_click(b4)
	_check(await _wait_done(120), "leniency collect works")
	_band(float(_last.get("acc", -1.0)), 1.0, 1.0, "burner +2.0 s at leniency 2.0")
	await _free([b4])
	# Tier 3 window (x0.7): +1.0 s is already "good".
	var b5: Node2D = _make(BURNER, _burner_params(1.0, {"_window_mult": 0.7}))
	await _until_elapsed(b5, 2.0)
	await _ring_click(b5)
	await _wait_done(120)
	_band(float(_last.get("acc", -1.0)), 0.65, 0.65, "burner +1.0 s at tier 3")
	await _free([b5])
	# Reduced motion: finishes on the collect frame (no pop delay).
	var b6: Node2D = _make(BURNER, _burner_params(0.5, {"_reduced_motion": true}))
	await _until_elapsed(b6, 0.6)
	_key(KEY_O, true)
	await process_frame
	_key(KEY_O, false)
	_check(not _last.is_empty(), "reduced motion: collect finishes immediately")
	await _free([b6])


# --- Real CookingGame run -----------------------------------------------------------------------

func _check_game() -> void:
	var recipe: Dictionary = {
		"id": "probe_burner_trace", "display_name": "Probe Latte", "tier": 1, "base_price": 6,
		"station": "counter", "par_bonus_sec": 2.0,
		"steps": [
			{"type": "back_burner", "label": "Pull the shot", "par_sec": 3.0, "weight": 1.0,
				"params": {"cook_sec": 2.0, "done_window_sec": 1.2, "good_window_sec": 1.3, "item": "portafilter"}},
			{"type": "trace", "label": "Latte art", "par_sec": 5.0, "weight": 1.5,
				"params": {"path_pool": ["circle"], "time_sec": 4.5, "tolerance_px": 14, "min_coverage": 0.8, "coverage_cap": 0.6, "ink": "#FBF3E4", "canvas": "#7A4E33"}},
		],
	}
	var game: Node2D = (load(COOKING_GAME) as Script).new()
	root.add_child(game)
	var result: Dictionary = {}
	game.connect("scored", func(r: Dictionary) -> void: result.merge(r, true))
	game.call("setup", {"recipe": recipe, "seed": 99, "skip_intro": true, "pace": 0.05, "_play_scale": SCALE, "settings": {}})
	# Wait for the trace card to be active and settled.
	var trace: Node2D = null
	var f: int = 0
	while f < 300:
		await process_frame
		f += 1
		var a: Variant = game.get("_active")
		if a != null and is_instance_valid(a) and String((a as Node).get_script().resource_path) == TRACE and (a as Node).process_mode != Node.PROCESS_MODE_DISABLED and (game.get("_step_layer") as Node2D).position == Vector2.ZERO:
			trace = a
			break
	var burner: Variant = game.get("_burner")
	_check(trace != null, "CookingGame runs the real TraceStep as the active card")
	_check(burner != null and String((burner as Node).get_script().resource_path) == BURNER, "CookingGame runs the real BackBurnerStep in the burner slot")
	if trace == null or burner == null:
		game.queue_free()
		return
	var bn: Node2D = burner
	_check(bn.get_parent().name == "BurnerLayer", "burner lives in the BurnerLayer")
	var hud: Dictionary = game.call("get_hud_info")
	_check(String((hud.get("burner", {}) as Dictionary).get("state", "")) == "cooking", "HUD burner slot reads get_burner_info()")
	# Ring click while cooking: swallowed by the burner, the trace never starts a stroke.
	await _ring_click(bn)
	_check(not bool(trace.get("pen_down")) and (trace.get("strokes") as Array).is_empty() and (trace.get("cur_pts") as PackedVector2Array).is_empty(), "burner ring click never reaches the trace card")
	# Trace the circle slowly; collect the burner with O as soon as it is ready.
	var path: Dictionary = trace.get("path")
	var total: float = float(path["length"])
	var s: float = 0.0
	_last = {}
	_move(_on_path(path, 0.0, 0.0), false)
	await process_frame
	_btn(_on_path(path, 0.0, 0.0), true)
	await process_frame
	var collected_mid: bool = false
	f = 0
	while is_instance_valid(trace) and trace.call("is_running") and f < 600:
		f += 1
		s = minf(s + total / 3.6 * DT, total)
		_move(_on_path(path, s, 0.0), true)
		if is_instance_valid(bn) and bn.call("can_collect") and not collected_mid:
			_key(KEY_O, true)
			collected_mid = true
		await process_frame
		if collected_mid and Input.is_key_pressed(KEY_O):
			_key(KEY_O, false)
	_btn(_mouse, false)
	_check(collected_mid, "burner became collectable while the trace was being drawn")
	f = 0
	while int(game.get("phase")) != 5 and f < 600:   # Phase.SERVE
		await process_frame
		f += 1
	_check(int(game.get("phase")) == 5, "game reaches the Serve bell")
	_key(KEY_ENTER, true)
	await process_frame
	_key(KEY_ENTER, false)
	f = 0
	while result.is_empty() and f < 120:
		await process_frame
		f += 1
	_check(not result.is_empty(), "game emits scored(result)")
	if not result.is_empty():
		var steps: Array = result.get("steps", [])
		_check(steps.size() == 2, "result has both steps")
		if steps.size() == 2:
			_band(float((steps[0] as Dictionary)["accuracy"]), 1.0, 1.0, "game: burner collected mid-trace")
			_band(float((steps[1] as Dictionary)["accuracy"]), 0.95, 1.0, "game: trace while the burner ran")
			_check(((steps[1] as Dictionary).get("extra", {}) as Dictionary).has("art"), "trace extra.art reaches the result payload")
			_check(String(result.get("grade", "")) == "S", "perfect burner + trace grades S (%s)" % String(result.get("grade", "")))
	game.queue_free()
	await _frames(2)
