extends SceneTree

## Headless probe for the Purr-fect Timing demo.
## Run (from the project folder):
##   Godot_console.exe --headless --path . --script res://Tools/probe_purrfect_timing.gd
##
## Checks:
##   windows    : Cozy +-120 / +-220 ms, leniency x1.5 / x2 scaling, oven scale.
##   calibration: offset_ms shifts judging (pure + full order with delayed inputs).
##   combo      : the Purr chain / bonus / points never go down; a missed beat is "ok".
##   orders     : a scripted bot plays every recipe with perfect / early / late / missed /
##                afk / mixed inputs on a manual clock; each order must finish (no softlock)
##                with the expected judgements and grade.
##   flow       : opening pauses the cafe, Esc pause + park + resume lose nothing, serving
##                unpauses and pays exactly once through MainLevel3D.add_money.
## Exit code 0 = all pass, 1 = any failure. `-- --force-fail` checks the failure exit path.

const DEMO := "res://Scenes/MinigameDemos/PurrfectTiming/PurrfectTimingDemo.tscn"
const JudgeScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTJudge.gd")
const RecipesScript := preload("res://Scripts/minigame_demos/purrfect_timing/PTRecipes.gd")
const MISS := 999.0
const DT := 1.0 / 120.0
const MAX_ORDER_SEC := 240.0

## Counts engine errors/warnings (script errors included) while the probe runs.
class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("%s %s %s (%s:%d %s)" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", code, rationale, file, line, function])
		_mutex.unlock()

var _logger: ErrorCounter
var _fails: Array[String] = []
var _checks: int = 0
var _demo: Node = null


func _initialize() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	_run.call_deferred()


func ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		_fails.append(msg)


func _run() -> void:
	print("== Purr-fect Timing probe ==")
	if "--force-fail" in OS.get_cmdline_user_args():
		ok(false, "forced failure (--force-fail) to check the exit code")
		await _finish()
		return
	_test_windows()
	_test_combo_pure()
	var demo: Node = load(DEMO).instantiate()
	root.add_child(demo)
	_demo = demo
	for i in 20:
		await process_frame
	var ov: Node = demo.get("overlay")
	var level: Node = demo.get("level")
	ok(ov != null and level != null, "demo has overlay + level")
	ok(demo.get("launcher") != null, "demo has the launcher panel")
	if ov == null or level == null:
		await _finish()
		return
	ov.set("force_manual_clock", true)
	await _test_orders(ov, level)
	await _test_flow(ov, level)
	await _test_input_events(ov)
	await _test_real_clock(ov)
	await _finish()


func _finish() -> void:
	OS.remove_logger(_logger)
	var mine: Array[String] = []
	for l in _logger.lines:
		if "purrfect_timing" in l or "PurrfectTiming" in l:
			mine.append(l)
	ok(mine.is_empty(), "no errors / warnings from Purr-fect Timing files (%d logged, %d total in run)" % [mine.size(), _logger.lines.size()])
	for l in _logger.lines:
		print("  log: ", l)
	print("== %d checks, %d failed ==" % [_checks, _fails.size()])
	for f in _fails:
		print("FAILED: ", f)
	paused = false
	if _demo != null:
		_demo.queue_free()
	for i in 5:
		await process_frame
	quit(1 if not _fails.is_empty() else 0)


# ------------------------------------------------------------------ pure logic

func _test_windows() -> void:
	print("-- judgement windows")
	var j: RefCounted = JudgeScript.new()
	var cases: Array = [
		[1.0, 0.0, "purrfect"], [1.0, 0.119, "purrfect"], [1.0, -0.12, "purrfect"], [1.0, 0.121, "good"],
		[1.0, -0.15, "good"], [1.0, 0.22, "good"], [1.0, 0.221, "ok"], [1.0, -0.5, "ok"],
		[1.5, 0.179, "purrfect"], [1.5, 0.181, "good"], [1.5, -0.33, "good"], [1.5, 0.331, "ok"],
		[2.0, 0.239, "purrfect"], [2.0, -0.241, "good"], [2.0, 0.44, "good"], [2.0, 0.441, "ok"],
	]
	for c in cases:
		j.set("leniency", c[0])
		var got: String = j.call("judge_delta", c[1])
		ok(got == c[2], "leniency x%.1f delta %+.0f ms -> %s (got %s)" % [c[0], c[1] * 1000.0, c[2], got])
	j.set("leniency", 1.0)
	ok(j.call("judge_delta", 0.35, 3.0) == "purrfect" and j.call("judge_delta", 0.6, 3.0) == "good", "oven scale x3 widens windows")
	print("-- calibration (pure)")
	for off in [-100.0, -40.0, 0.0, 60.0, 100.0]:
		j.set("offset_ms", off)
		var target: float = 10.0
		var raw: float = target + off / 1000.0
		var d: float = float(j.call("corrected", raw)) - target
		ok(absf(d) < 0.0005 and j.call("judge_delta", d) == "purrfect", "offset %+d ms cancels a %+d ms habit" % [int(off), int(off)])
	j.set("offset_ms", 80.0)
	ok(j.call("judge_delta", float(j.call("corrected", 10.0)) - 10.0) == "purrfect", "offset +80: on-time input still purrfect (-80 ms)")
	ok(j.call("judge_delta", float(j.call("corrected", 10.3)) - 10.0) == "good", "offset +80: raw +300 ms -> +220 ms good")


func _test_combo_pure() -> void:
	print("-- combo never punishes (pure)")
	var j: RefCounted = JudgeScript.new()
	var seq: Array[String] = ["purrfect", "purrfect", "good", "ok", "purrfect", "ok", "ok", "good", "purrfect", "purrfect", "good"]
	var prev_chain: int = 0
	var prev_bonus: int = 0
	var prev_points: float = 0.0
	var mono: bool = true
	for s in seq:
		j.call("add", s)
		var ch: int = j.get("chain")
		var bo: int = j.call("chain_bonus")
		var pts: float = j.get("points")
		if ch < prev_chain or bo < prev_bonus or pts < prev_points:
			mono = false
		prev_chain = ch
		prev_bonus = bo
		prev_points = pts
	ok(mono, "chain, chain bonus and points never decrease")
	ok(int(j.get("chain")) == 8, "chain counts every good+ hit across misses (8)")
	ok(int(j.get("best_combo")) == 4, "best combo is the longest unbroken run (4)")
	ok(int(j.call("chain_bonus")) == 1, "chain bonus +$1 at 8 hits")
	ok((j.get("counts") as Dictionary).keys().size() == 3 and int((j.get("counts") as Dictionary)["ok"]) == 3, "misses are counted as ok, no fail bucket")
	var j2: RefCounted = JudgeScript.new()
	for i in 6:
		j2.call("add", "purrfect")
	var before: int = j2.call("money", 6)
	j2.call("add", "ok")
	ok(int(j2.get("chain")) == 6 and int(j2.call("chain_bonus")) == 1, "a miss keeps the chain and its bonus")
	ok(int(j2.call("money", 6)) >= int(j2.call("base_money", 6)) + 1, "bonus money is kept after a miss (before %d)" % before)
	var jc: RefCounted = JudgeScript.new()
	for i in 5:
		jc.call("add", "ok")
	ok(jc.call("grade") == "C" and jc.call("grade_title", "C") == "STILL TASTY!" and int(jc.call("money", 6)) > 0, "all-ok order = C 'Still tasty!' and still pays")
	var js: RefCounted = JudgeScript.new()
	for i in 5:
		js.call("add", "good")
	ok(js.call("grade") == "A", "all-good order = A")
	js.call("add", "ok", "step1")
	js.call("drop_tag", "step1")
	ok(js.call("total") == 5 and js.call("grade") == "A", "drop_tag removes only that step's judgements")


# ------------------------------------------------------------------ bot orders

## Plays one order on the manual clock. delta_fn(n, kind) -> seconds offset from the ideal
## time (MISS = never send that input). start_fn(kind) -> false to skip "begin hold" inputs.
func _play(ov: Node, idx: int, settings: Dictionary, delta_fn: Callable, starts: bool = true, until_step: int = -1) -> Dictionary:
	var s: Dictionary = {"leniency_idx": 0, "audio": false, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false}
	s.merge(settings, true)
	if not bool(ov.get("is_open")):
		ov.set("settings", s)
		ov.call("open_recipe", idx)
	return _drive(ov, delta_fn, starts, until_step)


func _drive(ov: Node, delta_fn: Callable, starts: bool = true, until_step: int = -1) -> Dictionary:
	var g: Node = ov.get("game")
	var clk: RefCounted = ov.get("clock")
	var judge: RefCounted = ov.get("judge")
	var pending: Dictionary = {}
	var n: int = 0
	var prev_chain: int = int(judge.get("chain"))
	var chain_mono: bool = true
	var t_start: float = clk.get("manual_t")
	while (ov.get("current_result") as Dictionary).is_empty() and float(clk.get("manual_t")) - t_start < MAX_ORDER_SEC:
		if until_step >= 0 and int(g.get("step_index")) >= until_step and str(g.get("state")) == "play":
			break
		for a in g.call("bot_query"):
			var key: String = "oven" if a["kind"] == "oven" else "main"
			if not pending.has(key):
				var d: float = 0.0 if bool(a["start"]) else float(delta_fn.call(n, a["kind"]))
				if bool(a["start"]) and not starts:
					d = MISS
				pending[key] = {"t": float(a["t"]), "kind": a["kind"], "d": d, "step": int(g.get("step_index"))}
				n += 1
		var now: float = clk.get("manual_t")
		for key in pending.keys():
			var p: Dictionary = pending[key]
			if key == "main" and p["step"] != int(g.get("step_index")):
				pending.erase(key)
				continue
			if float(p["d"]) >= MISS:
				if now > float(p["t"]) + 0.6:
					pending.erase(key)  # let the next target come up
				continue
			var tf: float = float(p["t"]) + float(p["d"])
			if now >= tf:
				match str(p["kind"]):
					"press":
						g.call("input_press", tf)
					"release":
						g.call("input_release", tf)
					"oven":
						g.call("input_oven", tf)
				pending.erase(key)
		clk.set("manual_t", now + DT)
		g.call("update")
		var ch: int = judge.get("chain")
		if ch < prev_chain:
			chain_mono = false
		prev_chain = ch
	return {
		"result": (ov.get("current_result") as Dictionary).duplicate(true),
		"secs": float(clk.get("manual_t")) - t_start,
		"chain_mono": chain_mono,
	}


func _counts(r: Dictionary) -> Dictionary:
	return (r.get("result", {}) as Dictionary).get("counts", {})


func _serve_and_check(ov: Node, level: Node, r: Dictionary, label: String) -> void:
	var m0: int = int(level.get("money"))
	var applied0: int = int(ov.get("rewards_applied_count"))
	ok(paused, "%s: cafe paused while the order is open" % label)
	ov.call("serve")
	var res: Dictionary = r.get("result", {})
	ok(not paused, "%s: cafe unpaused after serving" % label)
	ok(not bool(ov.get("is_open")), "%s: overlay closed" % label)
	ok(int(level.get("money")) == m0 + int(res.get("money", -999)), "%s: add_money paid +$%d" % [label, int(res.get("money", 0))])
	ov.call("serve")
	ov.call("_apply_rewards", res)
	ok(int(level.get("money")) == m0 + int(res.get("money", -999)) and int(ov.get("rewards_applied_count")) == applied0 + 1, "%s: rewards applied exactly once" % label)


func _test_orders(ov: Node, level: Node) -> void:
	var recipes: Array = RecipesScript.all()
	print("-- perfect inputs, every recipe")
	for i in recipes.size():
		var r: Dictionary = _play(ov, i, {}, func(_n: int, _k: String) -> float: return 0.0)
		var c: Dictionary = _counts(r)
		var res: Dictionary = r["result"]
		var nm: String = str(recipes[i]["name"])
		ok(not res.is_empty(), "%s finished (%.1f s)" % [nm, r["secs"]])
		ok(int(c.get("good", -1)) == 0 and int(c.get("ok", -1)) == 0 and int(c.get("purrfect", 0)) > 0, "%s perfect run: all purrfect (%s)" % [nm, str(c)])
		ok(res.get("grade", "") == "S", "%s perfect run grade S" % nm)
		ok(float(r["secs"]) >= 20.0 and float(r["secs"]) <= 60.0, "%s order length %.1f s within 20..60 s of play" % [nm, r["secs"]])
		_serve_and_check(ov, level, r, nm)
		await process_frame

	print("-- early / late inputs (170 ms) are Good")
	var re: Dictionary = _play(ov, 0, {}, func(_n: int, _k: String) -> float: return -0.17)
	var ce: Dictionary = _counts(re)
	ok(int(ce.get("good", 0)) > 0 and int(ce.get("purrfect", -1)) == 0 and int(ce.get("ok", -1)) == 0, "early -170 ms: all good (%s)" % str(ce))
	ok(re["result"].get("grade", "") == "A", "early run grade A")
	_serve_and_check(ov, level, re, "early")
	var rl: Dictionary = _play(ov, 1, {}, func(_n: int, k: String) -> float: return 0.5 if k == "oven" else 0.17)
	var cl: Dictionary = _counts(rl)
	ok(int(cl.get("good", 0)) > 0 and int(cl.get("purrfect", -1)) == 0 and int(cl.get("ok", -1)) == 0, "late +170 ms (oven +500 ms): all good (%s)" % str(cl))
	_serve_and_check(ov, level, rl, "late")
	var rl2: Dictionary = _play(ov, 2, {}, func(_n: int, k: String) -> float: return 0.0 if k == "oven" else 0.17)
	ok(int(_counts(rl2).get("purrfect", 0)) == 1 and int(_counts(rl2).get("ok", -1)) == 0, "cookies late: oven purrfect, the rest good (%s)" % str(_counts(rl2)))
	_serve_and_check(ov, level, rl2, "late cookies")

	print("-- missed inputs are just ok, nothing softlocks")
	var rm: Dictionary = _play(ov, 0, {}, func(_n: int, _k: String) -> float: return MISS)
	var cm: Dictionary = _counts(rm)
	ok(not (rm["result"] as Dictionary).is_empty(), "missed (no taps / no releases) finishes in %.1f s" % rm["secs"])
	ok(int(cm.get("purrfect", -1)) == 0 and int(cm.get("good", -1)) == 0 and int(cm.get("ok", 0)) > 0, "missed: all ok (%s)" % str(cm))
	ok(rm["result"].get("grade", "") == "C" and int(rm["result"].get("money", 0)) > 0, "missed run grade C, still pays $%d" % int(rm["result"].get("money", 0)))
	_serve_and_check(ov, level, rm, "missed")
	for i in recipes.size():
		var ra: Dictionary = _play(ov, i, {}, func(_n: int, _k: String) -> float: return MISS, false)
		ok(not (ra["result"] as Dictionary).is_empty() and int(_counts(ra).get("ok", 0)) > 0, "afk (zero input) %s finishes in %.1f s, all ok" % [recipes[i]["name"], ra["secs"]])
		_serve_and_check(ov, level, ra, "afk %d" % i)

	print("-- mixed: combos never punish in a real order")
	var mixed := func(n: int, _k: String) -> float: return 0.4 if n % 3 == 2 else 0.0
	var rx: Dictionary = _play(ov, 3, {}, mixed)
	var rxr: Dictionary = rx["result"]
	ok(bool(rx["chain_mono"]), "chain never decreased during the order")
	ok(int(rxr.get("chain", 0)) == int(_counts(rx).get("purrfect", 0)) + int(_counts(rx).get("good", 0)), "chain = all good+ hits (%d)" % int(rxr.get("chain", 0)))
	ok(int(rxr.get("best_combo", 99)) < int(rxr.get("chain", 0)), "best combo (%d) < chain (%d): misses only end the brag streak" % [int(rxr.get("best_combo", 0)), int(rxr.get("chain", 0))])
	ok(int(rxr.get("chain_bonus", 0)) >= 1, "chain bonus kept (+$%d)" % int(rxr.get("chain_bonus", 0)))
	_serve_and_check(ov, level, rx, "mixed")

	print("-- leniency scaling in play")
	var r15: Dictionary = _play(ov, 0, {"leniency_idx": 1}, func(_n: int, _k: String) -> float: return 0.17)
	ok(int(_counts(r15).get("good", -1)) == 0 and int(_counts(r15).get("ok", -1)) == 0, "x1.5: +170 ms is purrfect (%s)" % str(_counts(r15)))
	_serve_and_check(ov, level, r15, "x1.5")
	var r2: Dictionary = _play(ov, 3, {"leniency_idx": 2}, func(_n: int, _k: String) -> float: return 0.23)
	ok(int(_counts(r2).get("good", -1)) == 0 and int(_counts(r2).get("ok", -1)) == 0, "x2: +230 ms is purrfect (%s)" % str(_counts(r2)))
	_serve_and_check(ov, level, r2, "x2")
	var r1: Dictionary = _play(ov, 0, {"leniency_idx": 0}, func(_n: int, k: String) -> float: return 0.3 if k == "press" else 0.0)
	ok(int(_counts(r1).get("ok", 0)) > 0, "x1: +300 ms taps are ok (%s)" % str(_counts(r1)))
	_serve_and_check(ov, level, r1, "x1 wide")

	print("-- calibration offset in play")
	var rc: Dictionary = _play(ov, 3, {"offset_ms": 80.0}, func(_n: int, _k: String) -> float: return 0.08)
	ok(int(_counts(rc).get("good", -1)) == 0 and int(_counts(rc).get("ok", -1)) == 0, "offset +80 with +80 ms late hands: all purrfect (%s)" % str(_counts(rc)))
	_serve_and_check(ov, level, rc, "offset +80")
	var rc2: Dictionary = _play(ov, 1, {"offset_ms": -100.0}, func(_n: int, _k: String) -> float: return -0.1)
	ok(int(_counts(rc2).get("good", -1)) == 0 and int(_counts(rc2).get("ok", -1)) == 0, "offset -100 with -100 ms early hands: all purrfect (%s)" % str(_counts(rc2)))
	_serve_and_check(ov, level, rc2, "offset -100")
	var rc3: Dictionary = _play(ov, 0, {"offset_ms": 100.0}, func(_n: int, _k: String) -> float: return -0.05)
	ok(int(_counts(rc3).get("purrfect", -1)) == 0 and int(_counts(rc3).get("ok", -1)) == 0, "offset +100 shifts -50 ms taps to -150 ms = good (%s)" % str(_counts(rc3)))
	_serve_and_check(ov, level, rc3, "offset +100 shift")

	print("-- hold -> toggle steaming")
	var rt: Dictionary = _play(ov, 1, {"hold_toggle": true}, func(_n: int, _k: String) -> float: return 0.0)
	ok(rt["result"].get("grade", "") == "S" and int(_counts(rt).get("ok", -1)) == 0, "toggle mode perfect run grade S (%s)" % str(_counts(rt)))
	_serve_and_check(ov, level, rt, "toggle")


func _test_flow(ov: Node, level: Node) -> void:
	print("-- pause / park / resume (no loss)")
	var was_paused: bool = paused
	var zero := func(_n: int, _k: String) -> float: return 0.0
	_play(ov, 0, {}, zero, true, 2)  # stop when step 3 (needle) is playing
	var g: Node = ov.get("game")
	var clk: RefCounted = ov.get("clock")
	var judge: RefCounted = ov.get("judge")
	ok(int(g.get("step_index")) == 2 and str(g.get("step_type")) == "needle", "reached the steam step")
	var before: int = int(judge.call("total"))
	ok(paused, "cafe paused while playing")
	ov.call("toggle_pause")
	ok(bool(ov.get("paused_menu")) and bool(clk.call("is_paused")), "Esc pause freezes the order clock")
	var t_frozen: float = clk.call("now")
	clk.set("manual_t", float(clk.get("manual_t")) + 30.0)
	g.call("update")
	ok(is_equal_approx(float(clk.call("now")), t_frozen) and str(g.get("state")) != "result", "30 s on the pause card changes nothing")
	ov.call("toggle_pause")
	ok(not bool(ov.get("paused_menu")) and not bool(clk.call("is_paused")), "resume from pause")
	ov.call("park")
	ok(not paused and not bool(ov.get("is_open")) and bool(ov.get("is_parked")), "park: cafe unpaused, window hidden, order parked")
	ok(paused == was_paused, "park restores the previous pause state")
	clk.set("manual_t", float(clk.get("manual_t")) + 60.0)
	ov.call("resume_parked")
	ok(paused and bool(ov.get("is_open")) and not bool(ov.get("is_parked")), "resume parked order: cafe paused again")
	ok(int(judge.call("total")) == before, "parked order kept its judgements (%d)" % before)
	var r: Dictionary = _drive(ov, zero)
	ok(not (r["result"] as Dictionary).is_empty() and r["result"].get("grade", "") == "S", "resumed order finishes with grade S")
	var m0: int = int(level.get("money"))
	ov.call("serve")
	ok(paused == was_paused, "serve restores the pause state")
	ok(int(level.get("money")) == m0 + int(r["result"].get("money", 0)), "parked order paid once (+$%d)" % int(r["result"].get("money", 0)))
	ov.call("serve")
	ok(int(level.get("money")) == m0 + int(r["result"].get("money", 0)), "second serve pays nothing")
	await process_frame


## Smoke test on the real clock with audio on: frames tick, the synth runs, nothing errors.
func _test_real_clock(ov: Node) -> void:
	print("-- real clock + synth smoke test")
	ov.set("force_manual_clock", false)
	ov.set("settings", {"leniency_idx": 0, "audio": true, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false})
	ov.call("open_recipe", 3)
	var clk: RefCounted = ov.get("clock")
	var t0: float = clk.call("now")
	for i in 90:
		await process_frame
	ok(float(clk.call("now")) > t0, "real clock advances while the cafe is paused")
	ok(paused and bool(ov.get("is_open")), "order open on the real clock")
	ov.call("park")
	ok(not paused, "park restores the cafe")
	ov.call("resume_parked")
	for i in 10:
		await process_frame
	ov.call("park")
	ov.set("force_manual_clock", true)


func _test_input_events(ov: Node) -> void:
	print("-- real input events (Esc / Space / mouse)")
	ov.set("settings", {"leniency_idx": 0, "audio": false, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false})
	_play(ov, 0, {}, func(_n: int, _k: String) -> float: return 0.0, true, 1)  # stop when the shot step plays
	var g: Node = ov.get("game")
	var clk: RefCounted = ov.get("clock")
	ok(str(g.get("state")) == "play" and str(g.get("step_type")) == "shot", "shot step playing")
	var sp := InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	root.push_input(sp)
	var sp2: InputEventKey = sp.duplicate()
	sp2.pressed = false
	root.push_input(sp2)
	ok((g.get("shot_hits") as Array).size() == 1, "Space press registers a shot hit")
	clk.set("manual_t", float(clk.get("manual_t")) + 0.5)
	g.call("update")
	var r: Rect2 = ov.call("play_area_rect")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = r.get_center()
	mb.global_position = r.get_center()
	root.push_input(mb, true)
	var mb2: InputEventMouseButton = mb.duplicate()
	mb2.pressed = false
	root.push_input(mb2, true)
	ok((g.get("shot_hits") as Array).size() == 2 or str(g.get("state")) == "outro", "mouse click in the play area registers a hit")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	ok(bool(ov.get("paused_menu")), "Esc opens the pause card")
	root.push_input(esc.duplicate())
	ok(not bool(ov.get("paused_menu")), "Esc again resumes")
	ov.call("park")
	ok(not paused, "park via API unpauses")
	await process_frame
