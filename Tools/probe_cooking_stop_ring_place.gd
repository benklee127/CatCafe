extends SceneTree

## Headless probe for the STOP_RING and PLACE cooking verbs.
## Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_stop_ring_place.gd
## Drives each verb with simulated input (Space key, LMB / RMB, arrow keys) pushed through the
## root viewport, and asserts the accuracy bands. Exit code 0 when every check passes, 1 otherwise.

const STOP_RING := "res://Scripts/minigame/cooking/steps/StopRingStep.gd"
const PLACE := "res://Scripts/minigame/cooking/steps/PlaceStep.gd"
const REGISTRY := "res://Scripts/minigame/cooking/StepRegistry.gd"
const MAX_FRAMES := 1200
const EPS := 0.0005

class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("%s %s %s (%s:%d %s)" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", code, rationale, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

var _fails: Array[String] = []
var _passes: int = 0
var _logger := ErrorCounter.new()
var _result: Array = []


func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails.append(what)
		print("  FAIL: ", what)


func _near(a: float, b: float, what: String, eps: float = EPS) -> void:
	_check(absf(a - b) <= eps, "%s (got %.4f, want %.4f)" % [what, a, b])


# --- helpers -------------------------------------------------------------------------------------

func _base_params(type: String, extra_params: Dictionary) -> Dictionary:
	var p: Dictionary = {
		"_type": type, "_label": type, "_index": 0, "_tier": 1, "_window_mult": 1.0,
		"_sweep_sec": 2.4, "_roll": {}, "_prev": [], "_play_scale": 4,
		"_safe_rect": Rect2(8, 8, 304, 164), "_slot_rect": Rect2(272, 4, 44, 44),
		"_reduced_motion": false,
	}
	for k in extra_params:
		p[k] = extra_params[k]
	return p


func _make(path: String, params: Dictionary, leniency: float = 1.0, toggle: bool = false) -> Node2D:
	var node: Node2D = (load(path) as Script).new()
	root.add_child(node)
	node.set("hold_to_toggle", toggle)
	_result = []
	node.connect("done", func(acc: float, t: float) -> void: _result = [acc, t])
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	node.call("start", params, leniency, r)
	return node


func _frame() -> void:
	await process_frame


func _space() -> void:
	var down := InputEventKey.new()
	down.keycode = KEY_SPACE
	down.pressed = true
	root.push_input(down, true)
	var up := InputEventKey.new()
	up.keycode = KEY_SPACE
	up.pressed = false
	root.push_input(up, true)


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	root.push_input(down, true)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	root.push_input(up, true)


func _mouse_button(pos: Vector2, pressed: bool, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func _mouse_move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev, true)


func _click(pos: Vector2) -> void:
	_mouse_button(pos, true)
	_mouse_button(pos, false)


## Waits until `cond(node)` is true (checked once per frame). Returns false on timeout.
func _wait(node: Node2D, cond: Callable) -> bool:
	for i in range(MAX_FRAMES):
		if cond.call(node):
			return true
		await process_frame
	return false


func _wait_done() -> bool:
	for i in range(MAX_FRAMES):
		if not _result.is_empty():
			return true
		await process_frame
	return false


func _dbg(node: Node2D) -> Dictionary:
	return node.call("get_debug_state")


# --- STOP_RING -----------------------------------------------------------------------------------

## Waits for the sweep, then fires `tap` once t >= center + offset (offset in seconds).
func _ring_tap_at(node: Node2D, offset: float, tap: Callable) -> bool:
	var ok: bool = await _wait(node, func(n: Node2D) -> bool:
		var d: Dictionary = _dbg(n)
		return int(d["state"]) == 1 and float(d["t"]) >= float(d["center_t"]) + offset - 0.004)
	if ok:
		tap.call()
	return ok


func _ring_tap_frac(node: Node2D, frac: float, tap: Callable) -> bool:
	var ok: bool = await _wait(node, func(n: Node2D) -> bool:
		var d: Dictionary = _dbg(n)
		return int(d["state"]) == 1 and float(d["t"]) >= float(d["dur"]) * frac)
	if ok:
		tap.call()
	return ok


func _test_stop_ring() -> void:
	print("[stop_ring]")
	var sp := func() -> void: _space()
	var p1: Dictionary = {"hits": 1, "food": "cookie", "golden_sec": 0.4, "perfect_sec": 0.16, "retry_cap": 0.7}

	# Timing derivation
	var n: Node2D = _make(STOP_RING, _base_params("stop_ring", p1.merged({"_roll": {"sweep_mult": 1.1}}, true)))
	var d: Dictionary = _dbg(n)
	_near(float(d["dur"]), 2.64, "sweep = tier sweep x roll mult")
	_near(float(d["golden_half"]), 0.2, "golden half = 0.2 s")
	_near(float(d["perfect_half"]), 0.08, "perfect half = 0.08 s")
	_near(float(d["center_t"]), 1.32, "golden centre at 0.5")
	# perfect (keyboard)
	await _ring_tap_at(n, 0.0, sp)
	_check(await _wait_done(), "perfect: finished")
	if not _result.is_empty():
		_near(float(_result[0]), 1.0, "perfect tap (Space) = 1.0")
		_check(float(_result[1]) > 1.2 and float(_result[1]) < 1.5, "perfect: time_sec ~ centre (%.2f)" % float(_result[1]))
	var ex: Dictionary = n.get("extra")
	_near(float(ex.get("brown", -1.0)), 0.5, "perfect: extra.brown ~ 0.5 (golden)", 0.02)
	n.queue_free()

	# okay (mouse)
	n = _make(STOP_RING, _base_params("stop_ring", p1))
	await _ring_tap_at(n, 0.14, func() -> void: _click(Vector2(160, 90)))
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.85, "golden-edge tap (LMB) = 0.85")
	n.queue_free()

	# okay early side
	n = _make(STOP_RING, _base_params("stop_ring", p1))
	await _ring_tap_at(n, -0.14, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.85, "early golden tap = 0.85")
	n.queue_free()

	# bad -> loop -> perfect retry capped at 0.7
	n = _make(STOP_RING, _base_params("stop_ring", p1))
	await _ring_tap_frac(n, 0.2, sp)
	await _frame()
	_check(int(_dbg(n)["state"]) == 3, "too-raw tap loops (COOL state)")
	_check(bool(_dbg(n)["retrying"]), "retry flag set after miss")
	_check(_result.is_empty(), "a first miss does not finish the step")
	await _ring_tap_at(n, 0.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.7, "miss then perfect retry = retry_cap 0.7")
	n.queue_free()

	# double miss -> 0.4
	n = _make(STOP_RING, _base_params("stop_ring", p1))
	await _ring_tap_frac(n, 0.1, sp)
	await _ring_tap_frac(n, 0.95, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.4, "two misses = 0.4 (still tasty)")
	n.queue_free()

	# no input at all -> two full sweeps -> 0.4
	n = _make(STOP_RING, _base_params("stop_ring", p1.merged({"_sweep_sec": 1.0}, true)))
	_check(await _wait_done(), "timeout: finishes without input")
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.4, "no tap = 0.4")
	n.queue_free()

	# conveyor hits:3 (mouse): perfect, okay, perfect
	n = _make(STOP_RING, _base_params("stop_ring", p1.merged({"hits": 3, "food": "stamp"}, true)))
	var clk := func() -> void: _click(Vector2(100, 100))
	await _ring_tap_at(n, 0.0, clk)
	_check(_result.is_empty(), "conveyor: first hit does not finish")
	await _ring_tap_at(n, 0.15, clk)
	await _ring_tap_at(n, 0.0, clk)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, (1.0 + 0.85 + 1.0) / 3.0, "conveyor hits:3 = mean of hits")
	ex = n.get("extra")
	_check((ex.get("hits", []) as Array).size() == 3, "conveyor: extra.hits has 3 entries")
	n.queue_free()

	# tempo mochi hits:4 perfect (keyboard), T2 window
	n = _make(STOP_RING, _base_params("stop_ring", p1.merged({"hits": 4, "food": "mochi", "tempo_sec": 0.9, "_tier": 2, "_window_mult": 0.85, "_roll": {"sweep_mult": 1.1}}, true)))
	d = _dbg(n)
	_near(float(d["dur"]), 0.9, "tempo: beat = tempo_sec (no roll)")
	_near(float(d["golden_half"]), 0.17, "tempo: T2 golden half = 0.4 x 0.85 / 2")
	for i in range(4):
		await _ring_tap_at(n, 0.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "tempo x4 perfect = 1.0")
	_check(not _result.is_empty() and float(_result[1]) < 4.6, "tempo: 4 beats finish quickly (%.2f s)" % (float(_result[1]) if not _result.is_empty() else -1.0))
	n.queue_free()

	# leniency 2.0: sweep doubles, windows double -> a 0.15 s-late tap is still perfect
	n = _make(STOP_RING, _base_params("stop_ring", p1), 2.0)
	d = _dbg(n)
	_near(float(d["dur"]), 4.8, "Sleepy leniency slows the sweep x2")
	_near(float(d["perfect_half"]), 0.16, "Sleepy leniency widens the perfect window x2")
	await _ring_tap_at(n, 0.14, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "Sleepy: 0.14 s late is still perfect")
	n.queue_free()

	# hold_to_toggle: taps still register on every press
	n = _make(STOP_RING, _base_params("stop_ring", p1.merged({"hits": 2}, true)), 1.0, true)
	await _ring_tap_at(n, 0.0, sp)
	await _ring_tap_at(n, 0.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "hold_to_toggle: both taps register")
	n.queue_free()

	# T3: 1.6 s sweep, 0.7 window
	n = _make(STOP_RING, _base_params("stop_ring", p1.merged({"_tier": 3, "_window_mult": 0.7, "_sweep_sec": 1.6}, true)))
	d = _dbg(n)
	_near(float(d["golden_half"]), 0.14, "T3 golden half = 0.4 x 0.7 / 2")
	await _ring_tap_at(n, 0.1, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.85, "T3: 0.1 s off = 0.85")
	n.queue_free()


# --- PLACE ---------------------------------------------------------------------------------------

## Swing: wait until the item is ready and |swing_x - target| is within [lo, hi], then tap.
func _swing_drop(node: Node2D, lo: float, hi: float, tap: Callable) -> bool:
	var ok: bool = await _wait(node, func(n: Node2D) -> bool:
		var d: Dictionary = _dbg(n)
		if not bool(d["ready"]):
			return false
		var off: float = absf(float(d["swing_x"]) - float(d["target_x"]))
		return off >= lo and off <= hi)
	if ok:
		tap.call()
	return ok


func _test_place_swing() -> void:
	print("[place swing]")
	var sp := func() -> void: _space()
	var bean: Dictionary = {"mode": "swing", "count": 1, "item": "red_bean", "swing_amp_px": 36, "swing_sec": 1.4, "bands_px": [5, 10, 18], "_roll": {"target_x": 0.1}}
	var n: Node2D = _make(PLACE, _base_params("place", bean))
	var d: Dictionary = _dbg(n)
	_near(float(d["target_x"]), 165.0, "marker offset by _roll.target_x x vessel width")
	await _swing_drop(n, 0.0, 2.0, sp)
	_check(await _wait_done(), "swing perfect: finished after landing")
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "swing drop on marker (Space) = 1.0")
	n.queue_free()

	n = _make(PLACE, _base_params("place", bean))
	await _swing_drop(n, 6.0, 9.5, func() -> void: _click(Vector2(10, 170)))
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.85, "swing drop 6-9.5 px off (LMB) = 0.85")
	n.queue_free()

	n = _make(PLACE, _base_params("place", bean))
	await _swing_drop(n, 11.0, 17.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.65, "swing drop 11-17 px off = 0.65")
	n.queue_free()

	n = _make(PLACE, _base_params("place", bean))
	await _swing_drop(n, 25.0, 60.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 0.4, "swing drop far off = 0.4 (wonky)")
	n.queue_free()

	# stacked marshmallow cats x3, keyboard, two perfect + one wonky; taps while falling ignored
	var marsh: Dictionary = {"mode": "swing", "count": 3, "item": "marshmallow_cat", "swing_amp_px": 40, "swing_sec": 1.6, "bands_px": [5, 10, 18], "stack": true, "_roll": {"target_x": -0.05}}
	n = _make(PLACE, _base_params("place", marsh))
	await _swing_drop(n, 0.0, 2.0, sp)
	await _frame()
	_space()
	_check(int(_dbg(n)["placed"]) == 0 and bool(_dbg(n)["falling"]), "tap while falling is ignored")
	await _swing_drop(n, 0.0, 2.0, sp)
	await _swing_drop(n, 30.0, 60.0, sp)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, (1.0 + 1.0 + 0.4) / 3.0, "stack x3 = mean of items")
	var ex: Dictionary = n.get("extra")
	_check((ex.get("offsets", []) as Array).size() == 3, "stack: extra.offsets has 3 entries")
	var placed: Array = n.get("placed")
	if placed.size() == 3:
		_check((placed[2]["pos"] as Vector2).y < (placed[0]["pos"] as Vector2).y, "stack: later items land higher")
		_check(absf(float(placed[2]["tilt"])) > 0.0, "stack: wonky item tilts")
	n.queue_free()

	# leniency 1.5 widens bands: 6.5 px is still perfect
	n = _make(PLACE, _base_params("place", bean), 1.5)
	_near(float(n.call("score_for_offset", 7.4)), 1.0, "Relaxed: 7.4 px within 5 x 1.5")
	_near(float(n.call("score_for_offset", 7.6)), 0.85, "Relaxed: 7.6 px is 0.85")
	_near(float(n.call("score_for_offset", 27.1)), 0.4, "Relaxed: 27.1 px is 0.4")
	n.queue_free()

	# pancake tints from earlier stop_ring browns
	var pan: Dictionary = {"mode": "swing", "count": 3, "item": "pancake", "swing_amp_px": 44, "swing_sec": 1.6, "bands_px": [5, 10, 18], "stack": true, "tint_from_prev": "stop_ring",
		"_prev": [{"type": "pour", "extra": {}}, {"type": "stop_ring", "extra": {"brown": 0.3}}, {"type": "stop_ring", "extra": {"brown": 0.5}}, {"type": "stop_ring", "extra": {"brown": 0.8}}]}
	n = _make(PLACE, _base_params("place", pan))
	var tints: Array = n.get("tints")
	_check(tints.size() == 3, "pancake: 3 tints from stop_ring browns")
	n.queue_free()


func _test_place_drag() -> void:
	print("[place drag]")
	var mochi: Dictionary = {"mode": "drag", "count": 4, "item": "eyes_ears", "bands_px": [5, 10, 18], "_roll": {"target_x": 0.0}}

	# perfect with the mouse (press / move / release in one frame)
	var n: Node2D = _make(PLACE, _base_params("place", mochi))
	await _frame()
	var targets: Array = _dbg(n)["targets"]
	_check(targets.size() == 4, "drag: 4 targets (2 ears + 2 eyes)")
	for t in targets:
		var tp: Vector2 = t["pos"]
		_mouse_button(Vector2(30, 116), true)
		_mouse_move(tp + Vector2(15, 0))
		_mouse_move(tp)
		_mouse_button(tp, false)
		await _frame()
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "drag x4 on markers (LMB) = 1.0")
	n.queue_free()

	# okay (7 px off) and bad (30 px off)
	for case in [[7.0, 0.85], [14.0, 0.65], [30.0, 0.4]]:
		n = _make(PLACE, _base_params("place", mochi))
		await _frame()
		targets = _dbg(n)["targets"]
		for t in targets:
			var tp: Vector2 = (t["pos"] as Vector2) + Vector2(0, float(case[0]))
			_mouse_button(Vector2(30, 116), true)
			_mouse_move(tp)
			_mouse_button(tp, false)
			await _frame()
		await _wait_done()
		_near(float(_result[0]) if not _result.is_empty() else -1.0, float(case[1]), "drag %.0f px off = %.2f" % [float(case[0]), float(case[1])])
		n.queue_free()

	# RMB undo: one bad drop, undo, then perfect
	n = _make(PLACE, _base_params("place", mochi))
	await _frame()
	targets = _dbg(n)["targets"]
	var far: Vector2 = (targets[0]["pos"] as Vector2) + Vector2(0, 40)
	_mouse_button(far, true)
	_mouse_button(far, false)
	await _frame()
	_check(int(_dbg(n)["placed"]) == 1, "drag: bad drop placed")
	_mouse_button(Vector2(100, 100), true, MOUSE_BUTTON_RIGHT)
	_mouse_button(Vector2(100, 100), false, MOUSE_BUTTON_RIGHT)
	await _frame()
	_check(int(_dbg(n)["placed"]) == 0, "drag: RMB undoes the last item")
	for t in targets:
		var tp: Vector2 = t["pos"]
		_mouse_button(tp, true)
		_mouse_button(tp, false)
		await _frame()
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "drag: after undo, perfect redo = 1.0")
	n.queue_free()

	# Undo during the settle window after the last item
	n = _make(PLACE, _base_params("place", mochi))
	await _frame()
	targets = _dbg(n)["targets"]
	for i in range(4):
		var tp: Vector2 = (targets[i]["pos"] as Vector2) + (Vector2(0, 30) if i == 3 else Vector2.ZERO)
		_mouse_button(tp, true)
		_mouse_button(tp, false)
		await _frame()
	_key(KEY_BACKSPACE)
	await _frame()
	_check(int(_dbg(n)["placed"]) == 3 and _result.is_empty(), "drag: Backspace undo inside the settle window")
	var tp3: Vector2 = targets[3]["pos"]
	_mouse_button(tp3, true)
	_mouse_button(tp3, false)
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "drag: settle undo + redo = 1.0")
	n.queue_free()

	# hold_to_toggle: click picks up, next click drops
	n = _make(PLACE, _base_params("place", mochi), 1.0, true)
	await _frame()
	targets = _dbg(n)["targets"]
	for t in targets:
		var tp: Vector2 = t["pos"]
		_click(Vector2(30, 116))
		await _frame()
		_check(bool(_dbg(n)["dragging"]), "toggle: first click picks up")
		_mouse_move(tp)
		await _frame()
		await _frame()
		_check(bool(_dbg(n)["dragging"]), "toggle: still carrying across frames")
		_click(tp)
		await _frame()
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "toggle drag x4 = 1.0")
	n.queue_free()

	# keyboard: arrow-key nudges + Space drops
	n = _make(PLACE, _base_params("place", mochi))
	await _frame()
	targets = _dbg(n)["targets"]
	for t in targets:
		var tp: Vector2 = t["pos"]
		_key(KEY_RIGHT)  # activates the keyboard cursor at the tray
		var cur: Vector2 = _dbg(n)["key_cursor"]
		var guard: int = 0
		while cur.round() != tp.round() and guard < 400:
			var dx: float = tp.x - cur.x
			var dy: float = tp.y - cur.y
			if absf(dx) >= 1.0:
				_key(KEY_RIGHT if dx > 0 else KEY_LEFT)
			elif absf(dy) >= 1.0:
				_key(KEY_DOWN if dy > 0 else KEY_UP)
			else:
				break
			cur = _dbg(n)["key_cursor"]
			guard += 1
		_space()
		await _frame()
	await _wait_done()
	_near(float(_result[0]) if not _result.is_empty() else -1.0, 1.0, "keyboard nudge + Space x4 = 1.0")
	n.queue_free()


func _test_registry() -> void:
	print("[registry]")
	var reg: Script = load(REGISTRY)
	_check(bool(reg.call("has_verb", "stop_ring")), "registry resolves stop_ring")
	_check(bool(reg.call("has_verb", "place")), "registry resolves place")
	var a: Node2D = reg.call("create_step", "stop_ring")
	var b: Node2D = reg.call("create_step", "place")
	_check(a != null and (a.get_script() as Script).resource_path == STOP_RING, "create_step(stop_ring) is StopRingStep")
	_check(b != null and (b.get_script() as Script).resource_path == PLACE, "create_step(place) is PlaceStep")
	if a: a.free()
	if b: b.free()


func _run() -> void:
	print("probe_cooking_stop_ring_place: start")
	_test_registry()
	await _test_stop_ring()
	await _test_place_swing()
	await _test_place_drag()
	var mine: Array[String] = []
	for l in _logger.lines:
		if l.contains("StopRingStep") or l.contains("PlaceStep") or l.contains("probe_cooking_stop_ring_place"):
			mine.append(l)
	for l in _logger.lines:
		print("  log: ", l)
	_check(mine.is_empty(), "no ERROR/WARNING lines from the verb files (%d)" % mine.size())
	print("probe_cooking_stop_ring_place: %d passed, %d failed" % [_passes, _fails.size()])
	quit(0 if _fails.is_empty() else 1)
