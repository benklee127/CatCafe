extends SceneTree

## Headless probe for the POUR and KEEP_ZONE verbs. Drives each verb with simulated input
## (Input.parse_input_event, so the device state the StepBase reads is real) and asserts
## accuracy bands. Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_pour_keep_zone.gd
## Exit code 0 when every check passes, 1 otherwise.

const POUR := "res://Scripts/minigame/cooking/steps/PourStep.gd"
const KEEP := "res://Scripts/minigame/cooking/steps/KeepZoneStep.gd"
const REGISTRY := "res://Scripts/minigame/cooking/StepRegistry.gd"
const MAX_FRAMES := 1200

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
var _done_acc: float = -1.0
var _done_count: int = 0


func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails.append(what)
		print("  FAIL: ", what)


func _run() -> void:
	print("probe_cooking_pour_keep_zone: start")
	var reg: Script = load(REGISTRY)
	_check(bool(reg.call("has_verb", "pour")), "registry finds the pour verb")
	_check(bool(reg.call("has_verb", "keep_zone")), "registry finds the keep_zone verb")
	_check_pour_static()
	await _check_pour_live()
	_check_zone_static()
	await _check_zone_live()
	for l in _logger.lines:
		if l.find("probe_cooking") < 0 and (l.find("PourStep") >= 0 or l.find("KeepZoneStep") >= 0):
			_check(false, "engine log from a verb: " + l)
	print("probe_cooking_pour_keep_zone: %d passed, %d failed" % [_passes, _fails.size()])
	quit(0 if _fails.is_empty() else 1)


# --- Input helpers ------------------------------------------------------------------------

func _primary(pressed: bool, keyboard: bool) -> void:
	if keyboard:
		var k := InputEventKey.new()
		k.keycode = KEY_SPACE
		k.physical_keycode = KEY_SPACE
		k.pressed = pressed
		Input.parse_input_event(k)
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = Vector2(100, 80)
		mb.global_position = mb.position
		Input.parse_input_event(mb)


func _tap(keyboard: bool) -> void:
	_primary(true, keyboard)
	_primary(false, keyboard)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _make(path: String, params: Dictionary, leniency: float = 1.0, toggle: bool = false) -> Node2D:
	var n: Node2D = load(path).new()
	n.set("hold_to_toggle", toggle)
	root.add_child(n)
	_done_acc = -1.0
	_done_count = 0
	n.connect("done", func(acc: float, _t: float) -> void:
		_done_acc = acc
		_done_count += 1)
	var p: Dictionary = params.duplicate(true)
	p["_window_mult"] = float(p.get("_window_mult", 1.0))
	n.call("start", p, leniency, RandomNumberGenerator.new())
	return n


func _cleanup(n: Node2D) -> void:
	# Make sure no input state leaks into the next case.
	_primary(false, true)
	_primary(false, false)
	await _frames(2)
	n.queue_free()
	await _frames(1)


# --- POUR -------------------------------------------------------------------------------------

func _check_pour_static() -> void:
	print("pour: score_fill bands")
	var s: Script = load(POUR)
	var cases: Array = [
		[0.70, 0.70, 1.0, false, 1.0, false],
		[0.73, 0.70, 1.0, false, 1.0, false],
		[0.65, 0.70, 1.0, false, 0.85, false],
		[0.78, 0.70, 1.0, false, 0.65, false],
		[0.55, 0.70, 1.0, false, 0.4, false],
		[0.90, 0.70, 1.0, false, 0.4, true],
		[0.86, 0.70, 2.0, false, 0.65, false],
		[0.74, 0.70, 1.0, true, 0.65, true],
		[0.72, 0.70, 1.0, true, 1.0, false],
	]
	for c: Array in cases:
		var r: Dictionary = s.call("score_fill", float(c[0]), float(c[1]), float(c[2]), [0.03, 0.06, 0.10], 0.15, 0.65, bool(c[3]))
		_check(is_equal_approx(float(r["accuracy"]), float(c[4])) and bool(r["spilled"]) == bool(c[5]),
			"score_fill(fill %.2f, target %.2f, ws %.1f, no_overflow %s) = %.2f/%s, got %.2f/%s" % [c[0], c[1], c[2], c[3], c[4], c[5], r["accuracy"], r["spilled"]])


## Holds until fill >= release_at, then releases. Returns the step for inspection.
func _pour_run(params: Dictionary, release_at: float, keyboard: bool, leniency: float = 1.0, toggle: bool = false) -> Node2D:
	var n: Node2D = _make(POUR, params, leniency, toggle)
	await _frames(2)
	_check(not bool(n.get("pouring")) and is_equal_approx(float(n.get("fill")), float(n.get("base_fill"))), "pour idles until held")
	if toggle:
		_tap(keyboard)
	else:
		_primary(true, keyboard)
	var f: int = 0
	while f < MAX_FRAMES and _done_count == 0:
		await process_frame
		f += 1
		if float(n.get("fill")) >= release_at and _done_count == 0:
			if toggle:
				_tap(keyboard)
			else:
				_primary(false, keyboard)
			await _frames(2)
			break
	return n


func _check_pour_live() -> void:
	print("pour: simulated play")
	var base: Dictionary = {"_type": "pour", "_roll": {"target": 0.7}, "vessel": "mug", "liquid": "#7A4E33"}
	var cases: Array = [
		# label, release offset from target, keyboard, leniency, toggle, expected accuracy
		["perfect (LMB)", -0.012, false, 1.0, false, 1.0],
		["perfect (Space)", -0.012, true, 1.0, false, 1.0],
		["perfect (hold->toggle taps)", -0.012, true, 1.0, true, 1.0],
		["okay (LMB, ~5% over)", 0.045, false, 1.0, false, 0.85],
		["meh (Space, ~8% over)", 0.075, true, 1.0, false, 0.65],
		["bad (LMB, ~12% over)", 0.12, false, 1.0, false, 0.4],
		["bad (Space, short pour)", -0.3, true, 1.0, false, 0.4],
		["relaxed leniency 1.5 (~8% over)", 0.075, false, 1.5, false, 0.85],
		["sleepy leniency 2.0 (~5% over)", 0.045, true, 2.0, false, 1.0],
	]
	for c: Array in cases:
		var n: Node2D = await _pour_run(base, 0.7 + float(c[1]), bool(c[2]), float(c[3]), bool(c[4]))
		_check(_done_count == 1, "%s: done emitted once (got %d)" % [c[0], _done_count])
		_check(is_equal_approx(_done_acc, float(c[5])), "%s: accuracy %.2f (got %.2f, fill %.3f)" % [c[0], c[5], _done_acc, float(n.get("fill"))])
		await _cleanup(n)

	# Flow ramps from flow_min to flow_max over ramp_sec.
	var r: Node2D = _make(POUR, base)
	await _frames(1)
	_primary(true, false)
	await _frames(3)
	var f0: float = float(r.get("flow"))
	await _frames(70)
	var f1: float = float(r.get("flow"))
	_check(f0 < 0.25 and absf(f1 - 0.6) < 0.01, "flow accelerates 0.15 -> 0.6 (start %.3f, after 1.2 s %.3f)" % [f0, f1])
	await _cleanup(r)

	# Spill: past +15% -> spilled; hold to the brim -> ends by itself.
	var sp: Node2D = await _pour_run(base, 2.0, false)
	_check(_done_count == 1 and bool(sp.get("spilled")) and is_equal_approx(float(sp.get("fill")), 1.0), "holding to the brim spills and auto-finishes")
	_check(_done_acc <= 0.65, "spill is capped at 0.65 (got %.2f)" % _done_acc)
	var ex: Dictionary = sp.get("extra")
	_check(ex.has("fill") and ex.has("target") and ex.has("liquid") and bool(ex.get("spilled", false)), "extra carries fill/target/liquid/spilled")
	await _cleanup(sp)

	# no_overflow: 4% over -> capped 0.65 with the spill flag.
	var no: Dictionary = base.duplicate(true)
	no["no_overflow"] = true
	var nn: Node2D = await _pour_run(no, 0.74, false)
	_check(is_equal_approx(_done_acc, 0.65) and bool(nn.get("spilled")), "no_overflow caps a small overfill at 0.65 (got %.2f)" % _done_acc)
	await _cleanup(nn)

	# Layered pour: line B moves by layer A's error and starts on top of layer A.
	var lb: Dictionary = {"_type": "pour", "_roll": {"target": 0.80}, "vessel": "glass", "liquid": "#FBF3E4", "layer": "B", "line_from_prev": true,
		"_prev": [{"type": "pour", "accuracy": 0.85, "extra": {"fill": 0.50, "target": 0.45, "liquid": "c9a27a"}}]}
	var b: Node2D = _make(POUR, lb)
	await _frames(1)
	_check(absf(float(b.get("target")) - 0.85) < 0.0001, "layer B line shifts by A's +0.05 error (target %.3f)" % float(b.get("target")))
	_check(absf(float(b.get("fill")) - 0.50) < 0.0001 and absf(float(b.get("base_fill")) - 0.50) < 0.0001, "layer B starts on top of layer A")
	_check((b.get("base_liquid") as Color).is_equal_approx(Color("#c9a27a")), "layer B shows layer A's colour")
	await _cleanup(b)
	var lb2: Node2D = await _pour_run(lb, 0.85 - 0.012, false)
	_check(is_equal_approx(_done_acc, 1.0), "layer B perfect on the shifted line (got %.2f)" % _done_acc)
	await _cleanup(lb2)

	# Frozen during the hint: no input reaches a disabled step.
	var fz: Node2D = _make(POUR, base)
	fz.process_mode = Node.PROCESS_MODE_DISABLED
	_primary(true, false)
	await _frames(20)
	_check(not bool(fz.get("pouring")) and _done_count == 0, "frozen (hint) pour ignores input")
	await _cleanup(fz)

	# Every vessel / alias draws without errors.
	for v: String in ["mug", "glass", "bowl", "pan", "mold", "cup", "pitcher", "scoop", "batter"]:
		var vv: Dictionary = base.duplicate(true)
		vv["vessel"] = v
		vv["base_fill"] = 0.2
		var vn: Node2D = await _pour_run(vv, 0.95, false)
		_check(_done_count == 1, "vessel %s plays to the end" % v)
		await _cleanup(vn)


# --- KEEP_ZONE ------------------------------------------------------------------------------

func _check_zone_static() -> void:
	print("keep_zone: score_zone")
	var s: Script = load(KEEP)
	var cases: Array = [[2.0, 2.0, 2.0, 1.0], [2.0, 4.0, 2.0, 0.5], [2.0, 2.5, 2.0, 0.8], [0.1, 0.1, 2.0, 0.4], [1.0, 2.0, 2.0, 0.4], [1.5, 1.5, 2.0, 0.75]]
	for c: Array in cases:
		var got: float = float(s.call("score_zone", float(c[0]), float(c[1]), float(c[2])))
		_check(absf(got - float(c[3])) < 0.0001, "score_zone(in %.1f, active %.1f, need %.1f) = %.2f (got %.3f)" % [c[0], c[1], c[2], c[3], got])


## Bang-bang controller: wants the needle at `aim`. Returns the node when it finished.
func _zone_run(params: Dictionary, aim: float, keyboard: bool, leniency: float = 1.0, toggle: bool = false, mode: String = "aim") -> Node2D:
	var n: Node2D = _make(KEEP, params, leniency, toggle)
	await _frames(1)
	var want: bool = false
	var f: int = 0
	while f < MAX_FRAMES and _done_count == 0:
		var next: bool = want
		match mode:
			"aim":
				next = float(n.get("needle")) < aim
			"never":
				next = false
			"always":
				next = true
		if next != want:
			if toggle:
				_tap(keyboard)
			else:
				_primary(next, keyboard)
			want = next
		await process_frame
		f += 1
	return n


func _check_zone_live() -> void:
	print("keep_zone: simulated play")
	var base: Dictionary = {"_type": "keep_zone", "_roll": {"zone_center": 0.7}, "zone_size": 0.18, "need_sec": 2.0, "window_sec": 6.0, "rise_speed": 0.55, "fall_speed": 0.45, "gauge": "milk"}
	var cases: Array = [
		# label, aim, keyboard, leniency, toggle, mode, min acc, max acc
		["perfect (LMB)", 0.7, false, 1.0, false, "aim", 0.9, 1.0],
		["perfect (Space)", 0.7, true, 1.0, false, "aim", 0.9, 1.0],
		["perfect (hold->toggle taps)", 0.7, true, 1.0, true, "aim", 0.9, 1.0],
		["okay (hugging the top edge)", 0.79, false, 1.0, false, "aim", 0.45, 0.89],
		["bad (never holds)", 0.0, false, 1.0, false, "never", 0.4, 0.4],
		["bad (holds the whole time)", 0.0, true, 1.0, false, "always", 0.4, 0.4],
		["sleepy leniency 2.0 (same top-edge aim)", 0.79, false, 2.0, false, "aim", 0.9, 1.0],
	]
	for c: Array in cases:
		var n: Node2D = await _zone_run(base, float(c[1]), bool(c[2]), float(c[3]), bool(c[4]), String(c[5]))
		_check(_done_count == 1, "%s: done emitted once (got %d)" % [c[0], _done_count])
		_check(_done_acc >= float(c[6]) - 0.0001 and _done_acc <= float(c[7]) + 0.0001, "%s: accuracy in [%.2f, %.2f] (got %.3f, in %.2f s / active %.2f s, t %.2f)" % [c[0], c[6], c[7], _done_acc, float(n.get("in_zone_time")), float(n.get("active_time")), float(n.get("elapsed"))])
		if String(c[5]) == "aim" and float(c[3]) == 1.0 and float(c[1]) == 0.7:
			_check(not bool(n.get("timed_out")) and float(n.get("elapsed")) < 4.5, "%s: fills before the window ends (t %.2f)" % [c[0], float(n.get("elapsed"))])
		if String(c[5]) == "never":
			_check(bool(n.get("timed_out")) and absf(float(n.get("elapsed")) - 6.0) < 0.05, "never-hold times out at the 6 s window (t %.2f)" % float(n.get("elapsed")))
		await _cleanup(n)

	# Inertia: releasing at full rise keeps climbing briefly (mild), then falls.
	var m: Node2D = _make(KEEP, base)
	await _frames(1)
	_primary(true, false)
	await _frames(40)
	var v_up: float = float(m.get("velocity"))
	_primary(false, false)
	await _frames(2)
	var y0: float = float(m.get("needle"))
	await _frames(3)
	var y1: float = float(m.get("needle"))
	await _frames(40)
	var y2: float = float(m.get("needle"))
	_check(v_up > 0.5 and y1 > y0 and y2 < y1, "mild inertia: drifts up after release then falls (v %.2f, %.3f -> %.3f -> %.3f)" % [v_up, y0, y1, y2])
	await _cleanup(m)

	# Leniency widens the zone and the window.
	var w: Node2D = _make(KEEP, base, 2.0)
	_check(absf(float(w.get("zone_size")) - 0.36) < 0.0001 and absf(float(w.get("window_sec")) - 12.0) < 0.0001, "leniency 2.0: zone 0.36, window 12 s")
	await _cleanup(w)

	# Every gauge (and alias, drift, reduced motion) plays to the end without errors.
	for g: String in ["milk", "kettle", "whisk", "shaker", "teapot", "steam", "tea", "matcha", "shake"]:
		var gp: Dictionary = base.duplicate(true)
		gp["gauge"] = g
		gp["drift"] = 0.04
		gp["_reduced_motion"] = g == "tea"
		var gn: Node2D = await _zone_run(gp, 0.7, false)
		_check(_done_count == 1 and _done_acc >= 0.75, "gauge %s (drift 0.04) plays well with the aim bot (got %.3f)" % [g, _done_acc])
		await _cleanup(gn)
