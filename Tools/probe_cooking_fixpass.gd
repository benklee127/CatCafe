extends SceneTree

## Probe for the cooking fix pass: park keeps finished work (also at the Serve bell), the result
## card ignores Space and early Enter, close() during the result card still pays, demo debug keys
## don't survive a park, the ticket waits long enough to read, drag-mode PLACE works with Space
## alone, the back-burner slot hides when idle, and the pixel font measures text.
## Run: godot --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_fixpass.gd
## Exit code 0 = pass.

const DEMO := "res://Scenes/Minigames/CookingDemo.tscn"
const DEBUG_STEP := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"
const CookingGame = preload("res://Scripts/minigame/cooking/CookingGame.gd")
const PixelDraw = preload("res://Scripts/minigame/cooking/PixelDraw.gd")

var _pass: int = 0
var _fail: int = 0
var _demo: Node
var _host: Node
var _finished: Array = []
var _aborted: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", what)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(1)


func _wait(cond: Callable, max_frames: int = 400) -> bool:
	for i in range(max_frames):
		if cond.call():
			return true
		await process_frame
	return bool(cond.call())


func _instant_ctx(id: String, acc: float = 1.0) -> Dictionary:
	var ctx: Dictionary = _demo.call("make_context", id, "")
	ctx["skip_intro"] = true
	ctx["pace"] = 0.05
	ctx["step_override"] = {"script": DEBUG_STEP, "accuracy": acc, "time": 1.0}
	return ctx


func _serve_ready(id: String) -> Node:
	_demo.call("cook", id, _instant_ctx(id))
	var g: Node = _host.call("get_game")
	await _wait(func() -> bool: return g != null and bool(g.call("is_ready_to_serve")))
	return g


func _run() -> void:
	_demo = (load(DEMO) as PackedScene).instantiate()
	root.add_child(_demo)
	await _frames(5)
	_host = _demo.get("host")
	_host.connect("finished", func(_c: Dictionary, r: Dictionary) -> void: _finished.append(r))
	_host.connect("aborted", func(_c: Dictionary) -> void: _aborted += 1)
	_check((_host as CanvasLayer).layer > 12, "host layer above PlacementCursorLayer (12)")
	_check(int(_host.call("get_physical_scale")) == 3 and int(_host.call("get_play_scale")) == 3, "headless 1600x900 base -> x3")

	# Pixel font metrics are defined for style A (B-F draw bold text, which is wider by design).
	var prev_style: String = PixelDraw.style
	PixelDraw.set_style("A")
	_check(PixelDraw.text_width("A") == 5.0 and PixelDraw.text_width("AA") == 11.0, "pixel font widths (A=5, AA=11)")
	_check(PixelDraw.text_width("Hi", 16) == 2.0 * PixelDraw.text_width("Hi"), "size 16 = 2x glyphs")
	PixelDraw.set_style(prev_style)

	# 1) Park at the Serve bell keeps the dish.
	var g: Node = await _serve_ready("purrfect_matcha_latte")
	var n_steps: int = (g.get("steps") as Array).size()
	var clock0: float = float(g.get("clock"))
	_host.call("request_park")
	_check(bool(_host.call("is_park_prompt_showing")), "park prompt at the Serve bell")
	var sub: Label = _host.get("_park_sub")
	_check(sub.text.contains("%d finished" % n_steps), "park copy says the finished steps stay (%s)" % sub.text)
	_host.call("confirm_park")
	await _frames(3)
	var front: Dictionary = (_demo.get("pending") as Array)[0]
	_check(CookingGame.resume_step_count(front) == n_steps, "parked context carries all %d finished steps" % n_steps)
	_check(not front.has("step_override") and not front.has("pace") and not front.has("skip_intro") and not front.has("start_step"), "demo debug keys erased on park")
	_demo.call("_cook_pending", 0)
	await _frames(3)
	g = _host.call("get_game")
	_check(g != null and bool(g.call("is_ready_to_serve")), "resumed order is straight back at the Serve bell")
	_check(is_equal_approx(float(g.get("clock")), clock0), "clock restored on resume")
	_check(bool(g.call("press_serve")), "resumed dish serves")
	await _frames(2)
	var res: Dictionary = (_host.get("_result") as Dictionary)
	_check((res.get("steps", []) as Array).size() == n_steps and String(res.get("grade", "")) == "S", "served resumed dish keeps its S grade")

	# 2) Result card: Space does nothing, early Enter is ignored, late Enter confirms.
	await _tap(KEY_SPACE)
	_check(bool(_host.call("is_result_showing")), "Space does not dismiss the result card")
	await _tap(KEY_ENTER)
	_check(bool(_host.call("is_result_showing")), "Enter within the guard is ignored")
	await _frames(30)  # guard = 0.45 s of host time
	await _frames(2)
	var n_fin: int = _finished.size()
	await _tap(KEY_ENTER)
	await _frames(2)
	_check(not bool(_host.call("is_open")) and _finished.size() == n_fin + 1, "Enter after the guard confirms")
	await _frames(20)

	# 3) close() during the result card still pays.
	var level: Node = _demo.get("level")
	var m0: int = int(level.get("money"))
	g = await _serve_ready("catpuccino")
	g.call("press_serve")
	await _frames(2)
	var ab0: int = _aborted
	n_fin = _finished.size()
	_host.call("close")
	await _frames(3)
	_check(_aborted == ab0 and _finished.size() == n_fin + 1, "close() on the result card emits finished, not aborted")
	var paid: int = int((_finished.back() as Dictionary).get("money", 0))
	_check(paid > 0 and int(level.get("money")) == m0 + paid, "close() on the result card still pays (+$%d)" % paid)
	await _frames(20)

	# 4) Park mid-cook keeps the finished prefix.
	var ctx: Dictionary = _instant_ctx("paw_print_cookies")
	ctx["step_override"] = {"script": DEBUG_STEP, "accuracy": 1.0, "time": 1.0, "delay": [0.0, 30.0, 30.0]}
	_demo.call("cook", "paw_print_cookies", ctx)
	g = _host.call("get_game")
	await _wait(func() -> bool: return (g.get("results") as Array)[0] != null and int(g.get("cur")) == 1)
	_host.call("request_park")
	_host.call("confirm_park")
	await _frames(3)
	front = (_demo.get("pending") as Array)[0]
	_check(CookingGame.resume_step_count(front) == 1, "mid-cook park keeps 1 finished step")
	_demo.call("_cook_pending", 0)
	await _frames(3)
	g = _host.call("get_game")
	_check(int(g.get("cur")) == 1 and (g.get("results") as Array)[0] != null, "resume continues at step 2 with step 1 done")
	_host.call("close")
	await _frames(20)

	# 5) Ticket waits long enough to read (4 steps -> 3.2 s).
	_demo.call("cook", "catpuccino", _demo.call("make_context", "catpuccino", ""))
	g = _host.call("get_game")
	_check(is_equal_approx(float(g.call("ticket_sec")), 2.0 + 0.3 * float((g.get("steps") as Array).size())), "ticket_sec = 2.0 + 0.3 x steps")
	await _frames(90)
	_check(int(g.get("phase")) == 0, "still on the ticket after 1.5 s")
	await _tap(KEY_SPACE)
	_check(int(g.get("phase")) != 0, "Space starts the ticket early")
	_host.call("close")
	await _frames(20)

	# 6) Drag-mode PLACE with the keyboard only: Space picks up, Space drops.
	var mctx: Dictionary = _demo.call("make_context", "kitten_mochi", "")
	mctx["start_step"] = 2
	mctx["pace"] = 0.05
	_demo.call("cook", "kitten_mochi", mctx)
	g = _host.call("get_game")
	await _wait(func() -> bool: return int(g.get("phase")) == 2)   # ACTIVE
	var hud: Dictionary = g.call("get_hud_info")
	_check(String(hud.get("hint", "")).contains("Space"), "drag PLACE hint mentions the keyboard (%s)" % String(hud.get("hint", "")))
	var st: Node = g.get("_active")
	await _tap(KEY_SPACE)
	_check(bool(st.get("key_active")), "Space picks the item up from the tray")
	await _tap(KEY_SPACE)
	_check((st.get("placed") as Array).size() == 1, "second Space drops it")
	_host.call("close")
	await _frames(20)

	# 7) Burner slot frame hidden at the Serve bell; banner title punctuated.
	g = await _serve_ready("tuxedo_affogato")
	_check(g.get("_burner") == null, "no burner pot at the Serve bell (slot frame not drawn)")
	g.call("press_serve")
	await _frames(40)
	_host.call("choose_result", false)
	await _frames(20)
	var tctx: Dictionary = _instant_ctx("toe_bean_milk_tea")
	tctx["pace"] = 1.0
	tctx["step_override"] = {"script": DEBUG_STEP, "accuracy": 1.0, "time": 1.0, "delay": 30.0}
	_demo.call("cook", "toe_bean_milk_tea", tctx)
	g = _host.call("get_game")
	var saw_title: String = ""
	for i in range(300):
		var b: Dictionary = (g.call("get_hud_info") as Dictionary).get("banner", {})
		if String(b.get("title", "")).begins_with("BACK BURNER"):
			saw_title = String(b["title"])
			break
		await process_frame
	_check(saw_title.begins_with("BACK BURNER: "), "back burner banner uses a colon (%s)" % saw_title)
	_host.call("close")
	await _frames(20)

	print("probe_cooking_fixpass: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
