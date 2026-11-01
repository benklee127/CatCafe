extends SceneTree

## Headless smoke test for the Purr-fect Timing art-style switch (A..F).
##   Godot_console.exe --headless --path . --script res://Tools/probe_purrfect_timing_styles.gd
## For every style: switch live through the launcher, play a few seconds of every recipe on the
## manual clock (all step types + oven + result card + pause card), and count engine errors /
## warnings. Exit code 0 = no errors, 1 = any error or failed check.

const DEMO := "res://Scenes/MinigameDemos/PurrfectTiming/PurrfectTimingDemo.tscn"
const PX := preload("res://Scripts/minigame_demos/purrfect_timing/PTPixel.gd")
const DT := 1.0 / 60.0

class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		lines.append("%s %s %s (%s:%d %s)" % ["WARNING" if error_type == ERROR_TYPE_WARNING else "ERROR", code, rationale, file, line, function])
		_mutex.unlock()

var _logger: ErrorCounter
var _fails: Array[String] = []


func _initialize() -> void:
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	_run.call_deferred()


func _run() -> void:
	var demo: Node = load(DEMO).instantiate()
	root.add_child(demo)
	for i in 10:
		await process_frame
	var ov: Node = demo.get("overlay")
	var la: Node = demo.get("launcher")
	ov.set("force_manual_clock", true)
	for letter in PX.STYLE_ORDER:
		la.call("set_art_style", letter)
		if PX.style != letter:
			_fails.append("style %s not applied" % letter)
		var g: Node = ov.get("game")
		var grouped: bool = g.get_node_or_null("FXFront") != null and (g.get("_fg") as Node).get_parent() == g.get_node("FXFront")
		var want_group: bool = bool(PX.S["halo"]) or bool(PX.S["drop_shadow"])
		if grouped != want_group:
			_fails.append("style %s: FX group wiring %s, expected %s" % [letter, grouped, want_group])
		for r in 4:
			ov.set("settings", {"leniency_idx": 2, "audio": false, "hold_toggle": false, "offset_ms": 0.0, "reduced_motion": false})
			ov.call("open_recipe", r)
			var clk: RefCounted = ov.get("clock")
			var steps: int = 0
			while str(g.get("state")) != "result" and steps < 60 * 90:
				for a in g.call("bot_query"):
					if float(clk.get("manual_t")) >= float(a["t"]):
						match str(a["kind"]):
							"press":
								g.call("input_press", float(a["t"]))
							"release":
								g.call("input_release", float(a["t"]))
							"oven":
								g.call("input_oven", float(a["t"]))
				clk.set("manual_t", float(clk.get("manual_t")) + DT)
				g.call("update")
				steps += 1
				if steps % 120 == 0:
					await process_frame
			if str(g.get("state")) != "result":
				_fails.append("style %s recipe %d did not finish" % [letter, r])
			await process_frame
			ov.call("serve")
		ov.call("open_recipe", 0)
		ov.call("toggle_pause")
		await process_frame
		ov.call("toggle_pause")
		ov.call("park")
		la.call("set_art_style", "A" if letter != "A" else "B")
		la.call("set_art_style", letter)
		ov.call("resume_parked")
		await process_frame
		ov.call("park")
		print("  style %s ok" % letter)
	la.call("set_art_style", "A")
	demo.queue_free()
	for i in 3:
		await process_frame
	for l in _logger.lines:
		print("  ", l)
	print("errors/warnings: %d   failed checks: %d" % [_logger.lines.size(), _fails.size()])
	for f in _fails:
		print("  FAIL ", f)
	quit(0 if _logger.lines.is_empty() and _fails.is_empty() else 1)
