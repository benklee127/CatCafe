extends SceneTree

## Counter Cats demo probe. Boots Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn
## (live cafe underneath), then plays full rounds through simulated input
## (root.push_input: Space/P/A/Esc/Enter keys and mouse clicks) at good and bad
## skill on both chaos levels, plus park/resume, leave, toggle mode and a freed-cat
## round. Asserts: no softlock, pause restored, rewards applied exactly once,
## money matches the grade, real-cat overstim/trust change within the per-round
## caps, events <= chaos cap and telegraphed >= ~1 s ahead.
## Usage:
##   godot --headless --path . --fixed-fps 60 --script res://Tools/probe_counter_cats.gd
## Exit code 0 = pass, 1 = fail.

const SCENE := "res://Scenes/MinigameDemos/CounterCats/CounterCatsDemo.tscn"
const R := preload("res://Scripts/minigame_demos/counter_cats/cc_recipes.gd")
const MAX_ROUND_FRAMES: int = 60 * 150

var demo: Node
var overlay: Node
var level: Node
var frame: int = 0
var fails: Array[String] = []
var log_lines: Array[String] = []

var runs: Array = [
	{"name": "good/cozy/catpuccino", "skill": "good", "chaos": 1, "recipe_id": "catpuccino", "fizz": true, "seed": 11},
	{"name": "bad/cozy/cookies", "skill": "bad", "chaos": 1, "recipe_id": "paw_cookies", "fizz": true, "seed": 12},
	{"name": "good/lively/parfait", "skill": "good", "chaos": 2, "recipe_id": "calico_parfait", "fizz": true, "seed": 13},
	{"name": "bad/lively/catpuccino", "skill": "bad", "chaos": 2, "recipe_id": "catpuccino", "fizz": true, "seed": 14},
	{"name": "good/lively/cookies+mouse", "skill": "good", "chaos": 2, "recipe_id": "paw_cookies", "fizz": true, "seed": 15, "mouse": true},
	{"name": "good/cozy/toggle+x2", "skill": "good", "chaos": 1, "recipe_id": "catpuccino", "fizz": true, "seed": 16, "toggle": true, "leniency": 2.0},
	{"name": "good/cozy/helper", "skill": "good", "chaos": 1, "recipe_id": "calico_parfait", "bond": true, "seed": 17},
	{"name": "good/off/catpuccino", "skill": "good", "chaos": 0, "recipe_id": "catpuccino", "fizz": true, "seed": 18},
	{"name": "good/lively/bat+sniff", "skill": "good", "chaos": 2, "recipe_id": "catpuccino", "fizz": true, "seed": 22, "force": ["bat", "sniff"]},
	{"name": "bad/lively/bat+sniff", "skill": "bad", "chaos": 2, "recipe_id": "paw_cookies", "fizz": true, "seed": 23, "force": ["bat", "sniff"]},
	{"name": "good/cozy/bat+mouse", "skill": "good", "chaos": 1, "recipe_id": "calico_parfait", "fizz": true, "seed": 24, "force": ["bat"], "mouse": true},
	{"name": "pet-spam caps", "skill": "good", "chaos": 0, "recipe_id": "calico_parfait", "fizz": true, "seed": 25, "pet_spam": true},
	{"name": "park+resume", "skill": "good", "chaos": 1, "recipe_id": "catpuccino", "fizz": true, "seed": 19, "park": true},
	{"name": "leave", "skill": "good", "chaos": 1, "recipe_id": "paw_cookies", "fizz": true, "seed": 20, "leave": true},
	{"name": "freed-cat", "skill": "good", "chaos": 1, "recipe_id": "catpuccino", "fizz": true, "seed": 21, "free_cat": true},
]
var run_i: int = -1
var run: Dictionary = {}
var stage: String = "boot"
var wait: int = 0
var round_frames: int = 0
var money_before: int = 0
var cats_before: Dictionary = {}     # node_id -> {o, t}
var closed_result: Dictionary = {}
var closed_report: Dictionary = {}
var money_at_close: int = 0
var applied_before: int = 0
var held: Dictionary = {}            # keycode -> true
var pet_seen: bool = false
var tele_start: Dictionary = {}      # event key -> frame
var parked_done: bool = false
var leave_armed: bool = false
var freed: bool = false
var result_frames: int = 0
var mouse_down: bool = false
var last_step: int = -99
var pet_mouse: bool = false

func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		push_error("probe: cannot load scene")
		quit(1)
		return
	demo = packed.instantiate()
	root.add_child(demo)
	overlay = demo.get_node("CounterCatsOverlay")
	level = demo.get_node("MainLevel3D")
	overlay.connect("closed", _on_closed)

func _process(_delta: float) -> bool:
	frame += 1
	match stage:
		"boot":
			if frame > 30:
				_next_run()
		"play":
			_play()
		"after":
			wait -= 1
			if wait <= 0:
				_check_after()
				_next_run()
		"done":
			return true
	return stage == "done"

func _fail(msg: String) -> void:
	fails.append("[%s] %s" % [run.get("name", "?"), msg])
	push_error("PROBE FAIL [%s] %s" % [run.get("name", "?"), msg])

func _next_run() -> void:
	_release_all()
	run_i += 1
	if run_i >= runs.size():
		_finish()
		return
	run = runs[run_i]
	closed_result = {}
	closed_report = {}
	round_frames = 0
	pet_seen = false
	tele_start = {}
	parked_done = false
	leave_armed = false
	freed = false
	result_frames = 0
	last_step = -99
	if bool(run.get("fizz", false)):
		demo.call("_on_fizz")
	var opts := {"recipe_id": run["recipe_id"], "chaos": run["chaos"], "leniency": float(run.get("leniency", 1.0)),
		"toggle": bool(run.get("toggle", false)), "preferred_cat": 0}
	if bool(run.get("bond", false)):
		var cats: Array = demo.call("live_cats")
		if not cats.is_empty():
			var c: Object = cats[0]
			if c.has_method("add_trust"):
				c.call("add_trust", maxf(0.0, 75.0 - float(c.get("trust"))))
			c.set("overstimulation", 0.0)
			opts["preferred_cat"] = c.get_instance_id()
	var ctx: Dictionary = demo.call("build_context", opts)
	ctx["seed"] = int(run["seed"])
	if run.has("force"):
		ctx["force_events"] = (run["force"] as Array).duplicate()
	money_before = int(level.get("money"))
	applied_before = int(overlay.get("rewards_applied_count"))
	if get_root().get_tree().paused:
		_fail("tree already paused before open")
	overlay.call("open", ctx)
	cats_before = {}
	for ci in ctx.get("cats", []):
		var obj: Object = instance_from_id(int(ci["node_id"]))
		if obj != null:
			cats_before[int(ci["node_id"])] = {"o": float(obj.get("overstimulation")), "t": float(obj.get("trust")), "name": ci["name"]}
	if not paused:
		_fail("tree not paused after open")
	if bool(run.get("bond", false)):
		var hl: bool = false
		for c in overlay.get("game").get("cats"):
			hl = hl or bool(c.get("info").get("helper", false))
		if not hl:
			_fail("bonded cat did not become a helper")
	stage = "play"

# ------------------------------------------------------------------ input helpers

func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	root.push_input(ev)
	if pressed:
		held[code] = true
	else:
		held.erase(code)

func _tap(code: Key) -> void:
	_key(code, true)
	_key(code, false)

func _mouse(gp: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	var sp: Vector2 = overlay.call("game_to_screen", gp)
	ev.position = sp
	ev.global_position = sp
	root.push_input(ev, true)
	mouse_down = pressed

func _release_all() -> void:
	for k in held.keys():
		_key(k, false)
	held.clear()

func _primary_down() -> void:
	if bool(run.get("mouse", false)):
		_mouse(Vector2(150, 60), true)
	else:
		_key(KEY_SPACE, true)

func _primary_up() -> void:
	if bool(run.get("mouse", false)):
		_mouse(Vector2(150, 60), false)
	else:
		_key(KEY_SPACE, false)

func _primary_tap() -> void:
	_primary_down()
	_primary_up()

# ------------------------------------------------------------------ bot

func _play() -> void:
	round_frames += 1
	if round_frames > MAX_ROUND_FRAMES:
		var g0: Node = overlay.get("game")
		_fail("softlock: round did not finish in %d frames; state=%s held=%s" % [MAX_ROUND_FRAMES, str(g0.call("get_debug_state")) if g0 != null else "-", str(held.keys())])
		_force_close()
		return
	if not bool(overlay.get("is_open")):
		if bool(overlay.get("is_parked")):
			# parked: cafe should be running; resume after a short while
			if paused:
				_fail("tree still paused while parked")
			wait += 1
			if wait > 30:
				wait = 0
				overlay.call("open", {})
				if not paused:
					_fail("tree not paused after resume")
			return
		if not closed_result.is_empty():
			stage = "after"
			wait = 60
		return
	if bool(overlay.call("is_result_showing")):
		result_frames += 1
		if result_frames == 20:
			_tap(KEY_ENTER)
		return
	var game: Node = overlay.get("game")
	var s: Dictionary = game.call("get_debug_state")
	var skill: String = str(run.get("skill", "good"))
	# like a player: let go of everything when a new step starts
	if int(s["step_i"]) != last_step:
		last_step = int(s["step_i"])
		if int(s["pet_cat"]) < 0:
			_release_all()
			if mouse_down:
				_mouse(Vector2(0, 0), false)
	# telegraph timing check
	var ev: Dictionary = s.get("event", {})
	if not ev.is_empty():
		var key: String = "%s@%d" % [ev.get("type", ""), int(ev.get("cat", 0))]
		var ph: String = str(ev.get("phase", ""))
		if ph == "telegraph" and not tele_start.has(key):
			tele_start[key] = float(s["elapsed"])
		elif ph == "active" and tele_start.has(key) and not tele_start.has(key + ":checked"):
			tele_start[key + ":checked"] = true
			var lead: float = float(s["elapsed"]) - float(tele_start[key])
			if lead < 0.95:
				_fail("event %s telegraphed only %.2fs ahead" % [key, lead])
	# freed-cat run: free the real cat mid-round (tree paused, freed at frame end)
	if bool(run.get("free_cat", false)) and not freed and int(s["step_i"]) >= 1:
		freed = true
		for nid in cats_before.keys():
			var obj: Object = instance_from_id(int(nid))
			if obj != null:
				(obj as Node).queue_free()
	# park / leave runs
	if bool(run.get("park", false)) and not parked_done and int(s["step_i"]) >= 1 and str(s["phase"]) == "step":
		parked_done = true
		_release_all()
		_tap(KEY_ESCAPE)
		if not bool(overlay.call("is_park_prompt_open")):
			_fail("Esc did not open the park prompt")
		_tap(KEY_P)
		if bool(overlay.get("is_open")) or not bool(overlay.get("is_parked")):
			_fail("park did not park")
		wait = 0
		return
	if bool(run.get("leave", false)) and not leave_armed and pet_seen and int(s["pet_cat"]) < 0:
		leave_armed = true
		_release_all()
		_tap(KEY_ESCAPE)
		_tap(KEY_L)
		return
	# pets (good skill), also force one pet for the leave run
	var pet_i: int = int(s["pet_cat"])
	if held.has(KEY_P):
		if pet_i < 0 and pet_seen:
			_key(KEY_P, false)
		elif pet_i >= 0:
			pet_seen = true
		return
	if mouse_down and pet_i >= 0:
		pet_seen = true
		return
	if mouse_down and pet_i < 0 and pet_seen and pet_mouse:
		pet_mouse = false
		_mouse(Vector2(0, 0), false)
		return
	var want_pet: bool = skill == "good" and not ev.is_empty() and str(ev.get("phase", "")) == "active" and str(ev.get("type", "")) == "loaf"
	if bool(run.get("leave", false)) and not pet_seen and int(s["step_i"]) >= 0:
		want_pet = true
	if bool(run.get("pet_spam", false)) and str(s["phase"]) == "step":
		var n: int = 0
		for st in game.get("cat_stats"):
			n += int(st["pets"])
		want_pet = n < 4
	if want_pet and pet_i < 0:
		if bool(run.get("mouse", false)):
			var cats: Array = game.get("cats")
			var ci: int = int(ev.get("cat", 0)) if not ev.is_empty() else 0
			_primary_up_if_held()
			if mouse_down:
				_mouse(Vector2(0, 0), false)
			pet_mouse = true
			_mouse((cats[ci] as Node2D).position + Vector2(0, -16), true)
			if bool(run.get("toggle", false)):
				_mouse(Vector2(0, 0), false)
		else:
			_primary_up_if_held()
			_key(KEY_P, true)
			if bool(run.get("toggle", false)):
				_key(KEY_P, false)
		pet_seen = true
		return
	if pet_i >= 0:
		return
	# assist / sniff
	if skill == "good" and not ev.is_empty() and str(ev.get("phase", "")) == "active":
		if str(ev.get("type", "")) == "assist":
			_tap(KEY_A)
			return
		if str(ev.get("type", "")) == "sniff":
			_tap(KEY_SPACE)
			return
	match str(s["phase"]):
		"bat_wait":
			var bat: Dictionary = s.get("bat", {})
			if skill == "good" and not bat.is_empty() and str(bat.get("state", "")) == "slide":
				if bool(run.get("mouse", false)):
					_mouse(bat["pos"], true)
					_mouse(bat["pos"], false)
				else:
					_tap(KEY_SPACE)
		"step":
			_step_bot(s, skill)

func _primary_up_if_held() -> void:
	if held.has(KEY_SPACE):
		_key(KEY_SPACE, false)

func _step_bot(s: Dictionary, skill: String) -> void:
	var toggle: bool = bool(run.get("toggle", false))
	match str(s["type"]):
		"ring":
			var err: float = float(s.get("ring_err", 0.0))
			if skill == "good":
				if absf(err) <= 0.017:
					_primary_tap()
			else:
				if err < -0.6 and randf() < 0.05:
					_primary_tap()
		"pour":
			var lvl: float = float(s.get("pour_level", 0.0))
			var tgt: float = float(s.get("pour_target", 0.7))
			var pouring: bool = bool(s.get("pouring", false))
			var stop_at: float = tgt - 0.004 if skill == "good" else 1.5
			if not pouring:
				if toggle:
					_primary_tap()
				elif not held.has(KEY_SPACE) and not mouse_down:
					_primary_down()
			elif lvl >= stop_at:
				if toggle:
					_primary_tap()
				else:
					_primary_up()
		"drop":
			if bool(s.get("drop_falling", false)):
				return
			if skill == "good":
				if absf(float(s.get("drop_off", 99.0))) <= 1.0:
					_primary_tap()
			elif randf() < 0.1:
				_primary_tap()

func _force_close() -> void:
	_release_all()
	if bool(overlay.get("is_open")):
		overlay.call("leave")
	stage = "after"
	wait = 10

# ------------------------------------------------------------------ checks

func _on_closed(result: Dictionary, report: Dictionary) -> void:
	closed_result = result
	closed_report = report
	money_at_close = int(level.get("money"))
	if paused:
		_fail("tree still paused right after close")

func _check_after() -> void:
	var name: String = str(run.get("name", ""))
	if closed_result.is_empty():
		_fail("no closed signal")
		return
	if paused:
		_fail("tree paused after round")
	var applied: int = int(overlay.get("rewards_applied_count")) - applied_before
	if applied != 1:
		_fail("rewards applied %d times (want 1)" % applied)
	var left: bool = bool(closed_result.get("left", false))
	var want_money: int = 0 if left else int(closed_result.get("money", 0))
	if money_at_close - money_before != want_money:
		_fail("money delta %d != %d" % [money_at_close - money_before, want_money])
	if not left:
		var g: String = str(closed_result.get("grade", ""))
		if not g in ["S", "A", "B", "C"]:
			_fail("bad grade '%s'" % g)
		if want_money != R.money_for(g, R.recipe_by_id(str(closed_result["recipe_id"]))["price_mult"]):
			_fail("money %d does not match grade %s" % [want_money, g])
		var evs: Array = closed_result.get("events", [])
		if evs.size() > R.CHAOS_CAP[int(run["chaos"])]:
			_fail("%d events > cap %d" % [evs.size(), R.CHAOS_CAP[int(run["chaos"])]])
		var prev_at: float = -100.0
		for e in evs:
			if float(e["at"]) < 4.0 - 0.01:
				_fail("event in the first 4 s (%.2f)" % float(e["at"]))
			if float(e["at"]) - prev_at < 5.0 - 0.01:
				_fail("events closer than 5 s")
			prev_at = float(e["at"])
	# real-cat deltas within caps
	for c in closed_report.get("cats", []):
		if not bool(c.get("applied", false)):
			if not bool(run.get("free_cat", false)):
				_fail("cat %s delta not applied" % c.get("name", "?"))
			continue
		var od: float = float(c["overstim_after"]) - float(c["overstim_before"])
		var td: float = float(c["trust_after"]) - float(c["trust_before"])
		if od < R.CAP_OVERSTIM - 0.001 or od > 0.001:
			_fail("overstim delta %.2f outside [%.0f, 0]" % [od, R.CAP_OVERSTIM])
		if td < -0.001 or td > R.CAP_TRUST + 0.001:
			_fail("trust delta %.2f outside [0, %.0f]" % [td, R.CAP_TRUST])
	# cross-check against the values captured at open (cafe was paused in between)
	for nid in cats_before.keys():
		var obj: Object = instance_from_id(int(nid))
		if obj == null or not is_instance_valid(obj):
			continue
		for c in closed_report.get("cats", []):
			if str(c.get("name", "")) == str(cats_before[nid]["name"]) and bool(c.get("applied", false)):
				var od2: float = float(c["overstim_after"]) - float(cats_before[nid]["o"])
				var td2: float = float(c["trust_after"]) - float(cats_before[nid]["t"])
				if od2 < R.CAP_OVERSTIM - 0.001 or od2 > 0.001 or td2 < -0.001 or td2 > R.CAP_TRUST + 0.001:
					_fail("live cat change since open out of caps (o %.2f, t %.2f)" % [od2, td2])
	var pets_total: int = 0
	for c in closed_result.get("cats", []):
		pets_total += int(c.get("pets", 0))
	if str(run.get("skill", "")) == "bad" and pets_total > 0:
		_fail("bad bot should not pet")
	if bool(run.get("pet_spam", false)):
		if pets_total < 3:
			_fail("pet spam only got %d pets" % pets_total)
		for c in closed_report.get("cats", []):
			if bool(c.get("applied", false)) and float(c["overstim_before"]) >= 20.0:
				if absf((float(c["overstim_after"]) - float(c["overstim_before"])) - R.CAP_OVERSTIM) > 0.01:
					_fail("pet spam overstim not capped at %.0f" % R.CAP_OVERSTIM)
	if bool(run.get("leave", false)) and (not left or pets_total < 1):
		_fail("leave run: left=%s pets=%d" % [left, pets_total])
	if run.has("force") and not left:
		var got: Array = (closed_result.get("events", []) as Array).map(func(e): return e["type"])
		if got != run["force"]:
			_fail("forced events %s, got %s" % [str(run["force"]), str(got)])
		if str(run.get("skill", "")) == "good" and "bat" in got and int(closed_result.get("catches", 0)) < 1:
			_fail("good bot did not catch the bat")
		if "sniff" in got and (str(run.get("skill", "")) == "bad") != bool(closed_result.get("sticker", false)):
			_fail("sniff outcome wrong (sticker=%s)" % closed_result.get("sticker", false))
	var line: String = "%-28s grade=%s score=%5.1f time=%5.1fs money=%d pets=%d events=%s" % [name, closed_result.get("grade", "-"),
		float(closed_result.get("score", 0.0)), float(closed_result.get("elapsed", 0.0)), want_money, pets_total,
		str((closed_result.get("events", []) as Array).map(func(e): return e["type"]))]
	for c in closed_report.get("cats", []):
		if bool(c.get("applied", false)):
			line += "  %s o %.1f->%.1f t %.1f->%.1f" % [c["name"], c["overstim_before"], c["overstim_after"], c["trust_before"], c["trust_after"]]
		else:
			line += "  %s (not applied)" % c.get("name", "?")
	log_lines.append(line)
	print("probe: " + line)

func _finish() -> void:
	stage = "done"
	# good runs should usually beat bad runs
	print("probe: %d runs, %d failures" % [runs.size(), fails.size()])
	for f in fails:
		print("  FAIL " + f)
	quit(1 if not fails.is_empty() else 0)
