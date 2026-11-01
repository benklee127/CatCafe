extends SceneTree

## Probe for the Test Kitchen demo glue (Scenes/Minigames/CookingDemo.tscn):
## live cafe background, launcher, pay-on-serve into the level, order queue, parking, pause state,
## and KitchenArt coverage (every recipe has a dish sprite; every verb has an icon).
## Run: godot --headless --path . --fixed-fps 60 --script res://Tools/probe_cooking_demo.gd
## Exit code 0 = pass.

const DEMO := "res://Scenes/Minigames/CookingDemo.tscn"
const DEBUG_STEP := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"
const KitchenArt = preload("res://Scripts/minigame/cooking/KitchenArt.gd")
const StepRegistry = preload("res://Scripts/minigame/cooking/StepRegistry.gd")

var _pass: int = 0
var _fail: int = 0
var _demo: Node
var _finished_result: Dictionary = {}


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


func _run() -> void:
	_demo = (load(DEMO) as PackedScene).instantiate()
	root.add_child(_demo)
	await _frames(5)
	var host: Node = _demo.get("host")
	var level: Node = _demo.get("level")
	_check(level != null and level.has_method("add_money"), "cafe level instanced as the background")
	_check(host != null and host.has_method("open"), "host present")
	_check(int((_demo.get("recipes") as Array).size()) == 10, "launcher lists all 10 recipes")
	var launcher: Node = _demo.get("_launcher")
	_check(launcher is CanvasLayer and (launcher as CanvasLayer).process_mode == Node.PROCESS_MODE_ALWAYS, "launcher is its own always-processing CanvasLayer")
	var list_rows: int = 0
	for n in launcher.find_children("Recipe_*", "Button", true, false):
		list_rows += 1
	_check(list_rows == 10, "10 recipe rows in the launcher (got %d)" % list_rows)

	# KitchenArt coverage
	for r in (_demo.get("recipes") as Array):
		for s in (r as Dictionary).get("steps", []):
			_check(KitchenArt.has_icon(String((s as Dictionary).get("type", ""))), "icon for verb %s" % String((s as Dictionary).get("type", "")))
	for t in StepRegistry.known_types():
		_check(KitchenArt.has_icon(String(t)), "icon for registry verb %s" % String(t))
	var info: Dictionary = KitchenArt.dish_info([{"type": "trace", "accuracy": 1.0, "extra": {"art": [{"pts": PackedVector2Array([Vector2(0, 0), Vector2(0.5, 0.5)]), "ink2": false}], "ink": "7a4e33"}}, {"type": "stop_ring", "accuracy": 0.9, "extra": {"brown": 0.6}}], 0.8)
	_check(bool(info["great"]) and (info["art"] as Array).size() == 1 and (info["browns"] as Array).size() == 1, "dish_info collects great / art / browns")
	_check(not bool(KitchenArt.dish_info([], 0.5)["great"]), "homely look below 0.75 precision")

	# 1) Pay on serve: money lands in the cafe after unpause.
	host.connect("finished", func(_c: Dictionary, r: Dictionary) -> void: _finished_result = r)
	var m0: int = int(level.get("money"))
	var ctx: Dictionary = _demo.call("make_context", "catpuccino", "to_go")
	ctx["skip_intro"] = true
	ctx["pace"] = 0.05
	ctx["step_override"] = {"script": DEBUG_STEP, "accuracy": 1.0, "time": 1.0}
	_demo.call("cook", "catpuccino", ctx)
	_check(bool(host.call("is_open")) and paused, "cooking opens the host and pauses the cafe")
	var g: Node = host.call("get_game")
	for i in range(240):
		if g != null and bool(g.call("is_ready_to_serve")):
			break
		await process_frame
	_check(bool(g.call("press_serve")), "serve bell rings")
	await _frames(2)
	_check(bool(host.call("is_result_showing")), "result card shows")
	_check(host.find_child("Dish", true, false) != null, "result card has the dish sprite")
	host.call("choose_result", false)
	await _frames(2)
	_check(not paused, "cafe unpaused after Back to cafe")
	var paid: int = int(_finished_result.get("money", -1))
	_check(paid > 0 and int(level.get("money")) == m0 + paid, "level.add_money got +$%d (money %d -> %d)" % [paid, m0, int(level.get("money"))])
	_check(String(_finished_result.get("grade", "")) == "S", "perfect instant cook grades S")
	_check(int(_demo.get("served")) == 1, "served counter")

	# 2) Order queue: 1 open + 2 pending; Next order walks the queue.
	await _frames(20)
	_demo.call("start_queue")
	await _frames(2)
	_check(bool(host.call("is_open")) and (_demo.get("pending") as Array).size() == 2, "queue opens one ticket with two pending")
	_check(bool((host.get("_context") as Dictionary).get("has_next_order", false)), "open ticket knows another order waits")
	host.call("close")
	await _frames(20)
	_check(not paused and (_demo.get("pending") as Array).size() == 2, "closing keeps the pending tickets")
	_demo.call("cook_next")
	await _frames(2)
	_check((_demo.get("pending") as Array).size() == 1, "cook_next pops a ticket")

	# 3) Park: the order goes to the front of pending with its seed.
	var seed_before: int = int((host.get("_context") as Dictionary).get("seed", -1))
	host.call("request_park")
	host.call("confirm_park")
	await _frames(2)
	var front: Dictionary = (_demo.get("pending") as Array)[0]
	_check(bool(front.get("parked", false)) and int(front.get("seed", -2)) == seed_before, "parked order waits first with its seed")
	_check(not paused, "cafe unpaused after parking")

	# 4) Next order > from the result card opens the next ticket.
	await _frames(20)
	var n_before: int = (_demo.get("pending") as Array).size()
	var ctx2: Dictionary = _demo.call("make_context", "paw_print_cookies", "")
	ctx2["skip_intro"] = true
	ctx2["pace"] = 0.05
	ctx2["step_override"] = {"script": DEBUG_STEP, "accuracy": 0.9, "time": 1.0}
	_demo.call("cook", "paw_print_cookies", ctx2)
	g = host.call("get_game")
	for i in range(240):
		if bool(g.call("is_ready_to_serve")):
			break
		await process_frame
	g.call("press_serve")
	await _frames(2)
	host.call("choose_result", true)
	await _frames(3)
	_check(bool(host.call("is_open")) and (_demo.get("pending") as Array).size() == n_before - 1, "Next order > opens the next pending ticket")
	host.call("close")
	await _frames(20)
	_check(not paused, "unpaused at the end")

	print("probe_cooking_demo: %d passed, %d failed" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
