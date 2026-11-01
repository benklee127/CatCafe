extends SceneTree

## Headless probe for the minigame framework (MinigameHost + CookingGame + recipes).
## Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_framework.gd
## Every verb is replaced by DebugInstantStep with injected accuracies, so this works before
## the real verbs exist. Exit code 0 when every check passes, 1 otherwise.
##
## Checks:
##   data     : recipes.json has the 10 design recipes, validates against RecipeDefinition schema,
##              stations are "counter" or decor ids, at most one back_burner per recipe.
##   math     : compute_score / compute_money / hot streak vs 4 hand-computed cases; kid-size drop;
##              seeded rolls are deterministic and inside their ranges; registry tolerance.
##   run      : open -> tree paused + cafe frozen -> ticket -> 3 steps -> serve -> result card ->
##              Back to cafe -> unpaused + finished(context, result) payload matches hand values.
##   burner   : a recipe with a back_burner completes and records the burner step.
##   park     : Esc-park prompt freezes the game; Keep cooking resumes; Park emits parked(context)
##              with the same seed; reopening the parked context finishes normally.
##   pause    : a tree that was already paused stays paused after close(); aborted is emitted.

const HOST_SCENE := "res://UI/Minigame/MinigameHost.tscn"
const COOKING_GAME := "res://Scripts/minigame/cooking/CookingGame.gd"
const DEBUG_STEP := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"
const REGISTRY := "res://Scripts/minigame/cooking/StepRegistry.gd"
const VALIDATOR := "res://Scripts/data/SchemaValidator.gd"
const RECIPES := "res://Data/recipes.json"
const DECOR := "res://Data/decor.json"
const EXPECTED_IDS: Array[String] = [
	"paw_print_cookies", "catpuccino", "purrfect_matcha_latte", "tuxedo_cocoa", "not_tuna_taiyaki",
	"kitten_mochi", "toe_bean_milk_tea", "cat_nap_chamomile", "calico_pancake_stack", "tuxedo_affogato",
]
const MAX_FRAMES := 3000
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
var _host: CanvasLayer
var _cookbook: Object
var _registry: Script
var _counter: Node
var _recipes: Array = []
var _events: Array = []


func _initialize() -> void:
	OS.add_logger(_logger)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passes += 1
	else:
		_fails.append(what)
		print("  FAIL: ", what)


func _near(a: float, b: float, what: String) -> void:
	_check(absf(a - b) <= EPS, "%s (got %.5f, want %.5f)" % [what, a, b])


func _run() -> void:
	print("probe_cooking_framework: start")
	_registry = load(REGISTRY)
	var cg: Script = load(COOKING_GAME)
	_cookbook = cg
	_check_data()
	_check_math(cg)

	# Minimal "cafe": a pausable node that counts frames.
	var src := GDScript.new()
	src.source_code = "extends Node\nvar ticks: int = 0\nfunc _process(_d: float) -> void:\n\tticks += 1\n"
	src.reload()
	_counter = Node.new()
	_counter.set_script(src)
	_counter.name = "FakeCafe"
	root.add_child(_counter)
	_host = (load(HOST_SCENE) as PackedScene).instantiate() as CanvasLayer
	root.add_child(_host)
	_host.connect("finished", func(c: Dictionary, r: Dictionary) -> void: _events.append(["finished", c, r, paused]))
	_host.connect("parked", func(c: Dictionary) -> void: _events.append(["parked", c, null, paused]))
	_host.connect("aborted", func(c: Dictionary) -> void: _events.append(["aborted", c, null, paused]))
	await process_frame

	await _check_input_plumbing()
	await _check_full_run()
	await _check_burner_run()
	await _check_park()
	await _check_prev_pause()

	OS.remove_logger(_logger)
	var mine: Array[String] = []
	for l in _logger.lines:
		if l.contains("minigame") or l.contains("Minigame") or l.contains("probe_cooking") or l.contains("recipes"):
			mine.append(l)
	for l in _logger.lines:
		print("  log: ", l)
	_check(mine.is_empty(), "no ERROR/WARNING lines from minigame files (%d)" % mine.size())
	print("probe_cooking_framework: %d passed, %d failed" % [_passes, _fails.size()])
	quit(0 if _fails.is_empty() else 1)


# --- data -------------------------------------------------------------------------------------

func _check_data() -> void:
	var f := FileAccess.open(RECIPES, FileAccess.READ)
	_check(f != null, "recipes.json opens")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	_check(data is Array, "recipes.json is an array")
	if not (data is Array):
		return
	_recipes = data
	var ids: Array[String] = []
	for r in _recipes:
		ids.append(String((r as Dictionary).get("id", "")))
	for want in EXPECTED_IDS:
		_check(ids.has(want), "recipe present: %s" % want)
	_check(ids.size() == 10, "exactly 10 recipes (got %d)" % ids.size())
	var validator: Object = (load(VALIDATOR) as Script).new()
	var res: Dictionary = validator.call("validate_array_with_file", _recipes, "RecipeDefinition.schema.json", "recipes")
	for e in res.get("errors", []):
		print("  schema: ", e)
	_check(bool(res.get("ok", false)), "recipes.json validates against RecipeDefinition.schema.json")
	var decor_ids: Array[String] = []
	var df := FileAccess.open(DECOR, FileAccess.READ)
	if df != null:
		var dd: Variant = JSON.parse_string(df.get_as_text())
		if dd is Array:
			for d in dd:
				decor_ids.append(String((d as Dictionary).get("id", "")))
	for r in _recipes:
		var rd: Dictionary = r
		var st: String = String(rd.get("station", ""))
		_check(st == "counter" or decor_ids.has(st), "station '%s' of %s is counter or a decor id" % [st, rd.get("id")])
		var burners: int = 0
		for s in rd.get("steps", []):
			if String((s as Dictionary).get("type", "")) == "back_burner":
				burners += 1
		_check(burners <= 1, "%s has at most one back_burner" % rd.get("id"))


func _recipe(id: String) -> Dictionary:
	for r in _recipes:
		if String((r as Dictionary).get("id", "")) == id:
			return (r as Dictionary).duplicate(true)
	return {}


# --- math -------------------------------------------------------------------------------------

func _check_math(cg: Script) -> void:
	var bal: Dictionary = cg.get_script_constant_map()["DEFAULT_BALANCE"]
	# Case 1: flawless + fast + 3 hot steps -> clamp at 1.0, S.
	var s1: Array = [{"type": "pour", "accuracy": 1.0}, {"type": "keep_zone", "accuracy": 1.0}, {"type": "trace", "accuracy": 1.0}]
	var hb1: float = cg.call("hot_bonus_for", 3, bal)
	_near(hb1, 0.09, "case1 hot bonus 3 steps = 0.09")
	var r1: Dictionary = cg.call("compute_score", s1, 10.0, 16.0, hb1, bal, false)
	_near(float(r1["precision"]), 1.0, "case1 precision")
	_near(float(r1["speed"]), 1.0, "case1 speed")
	_near(float(r1["score"]), 1.0, "case1 score clamps to 1.0")
	_check(String(r1["grade"]) == "S", "case1 grade S")
	_check(int(cg.call("compute_money", 6.0, "S", 1.0, 1.0, bal)) == 9, "case1 money round(6*1.5)=9")
	# Case 2: slow but flawless (2x par) -> 0.70 + 0.3*0.4 = 0.82 -> A (design: "never below Great").
	var r2: Dictionary = cg.call("compute_score", s1, 32.0, 16.0, 0.0, bal, false)
	_near(float(r2["speed"]), 0.4, "case2 speed at 2x par = 0.4")
	_near(float(r2["score"]), 0.82, "case2 score 0.82")
	_check(String(r2["grade"]) == "A", "case2 grade A")
	_check(int(cg.call("compute_money", 6.0, "A", 1.2, 1.0, bal)) == 9, "case2 money round(6*1.2*1.2)=9 (8.64)")
	# Case 3: mixed. acc [0.85, 0.65, 0.40(trace w1.5)], t=20, par=16, 1 hot step.
	# precision = (0.85+0.65+0.6)/3.5 = 0.6; speed = 1-0.6*4/16 = 0.85; score = 0.42+0.255+0.03 = 0.705 -> B
	var s3: Array = [{"type": "pour", "accuracy": 0.85}, {"type": "keep_zone", "accuracy": 0.65}, {"type": "trace", "accuracy": 0.40}]
	var r3: Dictionary = cg.call("compute_score", s3, 20.0, 16.0, cg.call("hot_bonus_for", 1, bal), bal, false)
	_near(float(r3["precision"]), 0.6, "case3 precision 0.6")
	_near(float(r3["speed"]), 0.85, "case3 speed 0.85")
	_near(float(r3["score"]), 0.705, "case3 score 0.705")
	_check(String(r3["grade"]) == "B", "case3 grade B")
	_check(int(cg.call("compute_money", 8.0, "B", 1.0, 1.0, bal)) == 8, "case3 money 8")
	# Case 4: struggling, very slow (3x par) -> floor 0.4. acc all 0.4 -> 0.28+0.12 = 0.40 -> C, money round(5*0.7)=4 (3.5)
	var s4: Array = [{"type": "pour", "accuracy": 0.4}, {"type": "place", "accuracy": 0.4}, {"type": "trace", "accuracy": 0.4}]
	var r4: Dictionary = cg.call("compute_score", s4, 48.0, 16.0, 0.0, bal, false)
	_near(float(r4["speed"]), 0.4, "case4 speed floor 0.4")
	_near(float(r4["score"]), 0.40, "case4 score 0.40")
	_check(String(r4["grade"]) == "C", "case4 grade C")
	_check(int(cg.call("compute_money", 5.0, "C", 1.0, 1.0, bal)) == 4, "case4 money round(3.5)=4")
	# No-clock: speed forced to 1.0.
	var r5: Dictionary = cg.call("compute_score", s4, 48.0, 16.0, 0.0, bal, true)
	_near(float(r5["speed"]), 1.0, "no-clock speed 1.0")
	# Hot streak cap.
	_near(float(cg.call("hot_bonus_for", 7, bal)), 0.09, "hot streak caps at 0.09")
	# Par = (sum + bonus) x mult.
	var cat: Dictionary = _recipe("catpuccino")
	_near(float(cg.call("compute_par", cat["steps"], 3.0, 1.0)), 16.0, "catpuccino par 16")
	_near(float(cg.call("compute_par", cat["steps"], 3.0, 0.85)), 13.6, "catpuccino To go! par 13.6")
	# Kid size drops the kid_skip step.
	var kid: Array = cg.call("build_step_list", cat, {"drop_steps": 1})
	_check(kid.size() == 2 and String((kid[1] as Dictionary)["type"]) == "trace", "kid size drops the steam step")
	# Seeded rolls deterministic + in range.
	var p: Dictionary = (cat["steps"][0] as Dictionary)["params"]
	var a: Dictionary = cg.call("roll_targets", "pour", p, 42, 0)
	var b: Dictionary = cg.call("roll_targets", "pour", p, 42, 0)
	var c: Dictionary = cg.call("roll_targets", "pour", p, 43, 0)
	_check(is_equal_approx(float(a["target"]), float(b["target"])), "rolls deterministic for a seed")
	_check(not is_equal_approx(float(a["target"]), float(c["target"])), "rolls differ across seeds")
	_check(float(a["target"]) >= 0.55 and float(a["target"]) <= 0.80, "pour target inside target_range")
	# Registry tolerance.
	_check(_registry.call("create_step", "bogus_verb", null, true) == null, "registry: unknown type -> null")
	var dbg: Object = _registry.call("create_step", "pour", DEBUG_STEP, true)
	_check(dbg != null, "registry: explicit override path instantiates")
	if dbg != null:
		(dbg as Node).free()
	for t in ["pour", "keep_zone", "stop_ring", "trace", "place", "back_burner"]:
		var has: bool = _registry.call("has_verb", t)
		print("  verb %-12s %s" % [t, "built" if has else "missing (stand-in)"])


# --- runs -------------------------------------------------------------------------------------

func _ctx(id: String, accs: Array, times: Array, seed_v: int = 777) -> Dictionary:
	return {
		"recipe": _recipe(id),
		"seed": seed_v,
		"modifier": "",
		"patron_name": "Probe Patron",
		"settings": {"reduced_motion": true},
		"step_override": {"script": DEBUG_STEP, "accuracy": accs, "time": times},
	}


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _wait_ready(game: Node) -> bool:
	for i in range(MAX_FRAMES):
		if game == null or not is_instance_valid(game):
			return false
		if bool(game.call("is_ready_to_serve")):
			return true
		await process_frame
	return false


func _check_full_run() -> void:
	print("run: catpuccino")
	_events.clear()
	var ticks_before: int = int(_counter.get("ticks"))
	await _frames(3)
	_check(int(_counter.get("ticks")) > ticks_before, "fake cafe ticks while closed")
	var ctx: Dictionary = _ctx("catpuccino", [1.0, 0.9, 0.8], [2.0, 3.0, 6.0])
	_host.call("open", load(COOKING_GAME), ctx)
	_check(bool(_host.call("is_open")), "host is_open after open")
	_check(paused, "tree paused on open")
	var frozen: int = int(_counter.get("ticks"))
	var game: Node = _host.call("get_game")
	_check(game != null, "game instantiated")
	_check(int(ctx.get("_play_scale", 0)) >= 1, "host wrote _play_scale into context")
	var ok: bool = await _wait_ready(game)
	_check(ok, "catpuccino reaches the serve bell")
	_check(int(_counter.get("ticks")) == frozen, "fake cafe frozen while cooking")
	_check(bool(game.call("press_serve")), "press_serve rings the bell")
	await process_frame
	_check(bool(_host.call("is_result_showing")), "result card showing after serve")
	_check(paused, "still paused on result card")
	_host.call("choose_result", false)
	_check(not paused, "tree unpaused after Back to cafe")
	_check(not bool(_host.call("is_open")), "host closed")
	_check(_events.size() == 1 and _events[0][0] == "finished", "finished emitted once")
	if _events.size() >= 1 and _events[0][0] == "finished":
		_check(_events[0][3] == false, "finished emitted after unpause")
		_check(_events[0][1] == ctx, "finished carries the same context")
		var r: Dictionary = _events[0][2]
		for k in ["grade", "score", "precision", "speed", "steps", "time_sec", "par_sec", "hot_streak", "money", "rep"]:
			_check(r.has(k), "result has key %s" % k)
		_near(float(r.get("precision", 0.0)), 3.1 / 3.5, "run precision (1+0.9+0.8*1.5)/3.5")
		_check(int(r.get("hot_streak", -1)) == 2, "run hot streak 2 (steps 1+2 under par with acc>=0.85)")
		_near(float(r.get("par_sec", 0.0)), 16.0, "run par 16")
		_check(float(r.get("time_sec", 99.0)) < 1.0, "run clock only counts active step time (%.3f)" % float(r.get("time_sec", 99.0)))
		_near(float(r.get("speed", 0.0)), 1.0, "run speed 1.0")
		_near(float(r.get("score", 0.0)), 0.7 * 3.1 / 3.5 + 0.3 + 0.06, "run score 0.98")
		_check(String(r.get("grade", "")) == "S", "run grade S")
		_check(int(r.get("money", 0)) == 9, "run money 9")
		_near(float(r.get("rep", 0.0)), 1.0, "run rep 1.0")
		var steps: Array = r.get("steps", [])
		_check(steps.size() == 3, "run has 3 step entries")
		if steps.size() == 3:
			var s2: Dictionary = steps[2]
			_check(String(s2.get("type", "")) == "trace" and is_equal_approx(float(s2.get("accuracy", 0.0)), 0.8) and is_equal_approx(float(s2.get("time", 0.0)), 6.0), "step entry {type,label,accuracy,time}")
			_check(s2.has("label"), "step entry has label")
		_check(r.get("next_order", true) == false, "result.next_order false for Back to cafe")
	await _frames(3)
	_check(int(_counter.get("ticks")) > frozen, "fake cafe resumes after close")


func _check_input_plumbing() -> void:
	print("input: raw events reach the game through the SubViewport")
	_events.clear()
	var ctx: Dictionary = _ctx("catpuccino", [1.0, 1.0, 1.0], [1.0, 1.0, 1.0])
	ctx["step_override"]["delay"] = 30.0
	_host.call("open", COOKING_GAME, ctx)
	await _frames(2)
	var game: Node = _host.call("get_game")
	_check(String(game.call("get_hud_info")["phase"]) == "TICKET", "starts on the ticket")
	var k := InputEventKey.new()
	k.keycode = KEY_SPACE
	k.physical_keycode = KEY_SPACE
	k.pressed = true
	root.push_input(k)
	var k2: InputEventKey = k.duplicate()
	k2.pressed = false
	root.push_input(k2)
	await _frames(2)
	_check(String(game.call("get_hud_info")["phase"]) == "HINT", "Space skips the ticket (phase %s)" % String(game.call("get_hud_info")["phase"]))
	var svc: Control = _host.find_child("PlayView", true, false) as Control
	var center: Vector2 = svc.get_global_rect().get_center()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = center
	mb.global_position = center
	root.push_input(mb, true)
	var mb2: InputEventMouseButton = mb.duplicate()
	mb2.pressed = false
	root.push_input(mb2, true)
	await _frames(2)
	_check(String(game.call("get_hud_info")["phase"]) == "ACTIVE", "LMB in the PlayArea skips the hint (phase %s)" % String(game.call("get_hud_info")["phase"]))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	_check(bool(_host.call("is_park_prompt_showing")), "Esc opens the park prompt")
	root.push_input(esc.duplicate())
	await process_frame
	_check(not bool(_host.call("is_park_prompt_showing")), "Esc again = keep cooking")
	_host.call("close")
	_check(_events.size() == 1 and _events[0][0] == "aborted", "close() mid-cook emits aborted")
	await process_frame


func _check_burner_run() -> void:
	print("run: not_tuna_taiyaki (back burner)")
	_events.clear()
	var ctx: Dictionary = _ctx("not_tuna_taiyaki", [1.0, 0.85, 0.65, 0.9], [2.0, 2.0, 9.0, 2.0])
	ctx["has_next_order"] = true
	_host.call("open", COOKING_GAME, ctx)
	var game: Node = _host.call("get_game")
	var ok: bool = await _wait_ready(game)
	_check(ok, "taiyaki reaches the serve bell")
	if not ok:
		_host.call("close")
		return
	game.call("press_serve")
	await process_frame
	_host.call("choose_result", true)
	_check(_events.size() == 1 and _events[0][0] == "finished", "taiyaki finished")
	if _events.size() == 1 and _events[0][0] == "finished":
		var r: Dictionary = _events[0][2]
		var types: Array = []
		for s in r.get("steps", []):
			types.append(String((s as Dictionary)["type"]))
		_check(types.size() == 4 and types.has("back_burner"), "burner step recorded (%s)" % str(types))
		_check(r.get("next_order", false) == true, "result.next_order true for Next order")


func _check_park() -> void:
	print("park: paw_print_cookies")
	_events.clear()
	var ctx: Dictionary = _ctx("paw_print_cookies", [1.0, 1.0, 1.0], [1.0, 1.0, 1.0], 12345)
	ctx["step_override"]["delay"] = 5.0
	_host.call("open", COOKING_GAME, ctx)
	await _frames(10)
	var game: Node = _host.call("get_game")
	_host.call("request_park")
	_check(bool(_host.call("is_park_prompt_showing")), "park prompt showing")
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED, "game frozen under the park prompt")
	var phase_before: String = String(game.call("get_hud_info")["phase"])
	await _frames(120)
	_check(String(game.call("get_hud_info")["phase"]) == phase_before, "game does not advance while prompt is up")
	_host.call("cancel_park")
	_check(not bool(_host.call("is_park_prompt_showing")) and game.process_mode == Node.PROCESS_MODE_INHERIT, "Keep cooking resumes")
	_host.call("request_park")
	_host.call("confirm_park")
	_check(not paused and not bool(_host.call("is_open")), "park closes + unpauses")
	_check(_events.size() == 1 and _events[0][0] == "parked", "parked emitted")
	if _events.size() == 1 and _events[0][0] == "parked":
		var pc: Dictionary = _events[0][1]
		_check(int(pc.get("seed", 0)) == 12345, "parked context keeps its seed")
		_check(int(pc.get("park_count", 0)) == 1, "park_count incremented")
		# Resume.
		_events.clear()
		pc["step_override"]["delay"] = 0.0
		await process_frame
		_host.call("open", COOKING_GAME, pc)
		var g2: Node = _host.call("get_game")
		_check(int(g2.get("seed_value")) == 12345, "resumed game uses the same seed")
		var ok: bool = await _wait_ready(g2)
		_check(ok, "resumed order reaches the bell")
		g2.call("press_serve")
		await process_frame
		_host.call("choose_result", false)
		_check(_events.size() == 1 and _events[0][0] == "finished", "resumed order finishes")


func _check_prev_pause() -> void:
	print("pause: pre-paused tree")
	_events.clear()
	paused = true
	_host.call("open", COOKING_GAME, _ctx("catpuccino", [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]))
	await _frames(5)
	_host.call("close")
	_check(paused, "previously paused tree stays paused after close")
	_check(_events.size() == 1 and _events[0][0] == "aborted", "close() emits aborted")
	paused = false
	# Bad game input is tolerated.
	_events.clear()
	var log_mark: int = _logger.lines.size()
	print("  (one expected ERROR follows: deliberately bad game path)")
	_host.call("open", "res://does/not/exist.gd", {})
	_check(_logger.lines.size() == log_mark + 1, "bad game path logs exactly one error")
	_logger.lines.resize(log_mark)
	_check(not bool(_host.call("is_open")) and not paused, "bad game path does not open or pause")
	_check(_events.size() == 1 and _events[0][0] == "aborted", "bad game path emits aborted")
