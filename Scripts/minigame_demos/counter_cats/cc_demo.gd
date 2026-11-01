extends Node

## Counter Cats demo root. Runs the unmodified live cafe (MainLevel3D) underneath,
## plus our own launcher panel (F11) and the minigame overlay. Picks 1-2 REAL cats
## from the "cats" group (guarded reads), opens the overlay, and keeps the
## launcher in sync. Nothing here edits the cafe's scripts.

const R := preload("res://Scripts/minigame_demos/counter_cats/cc_recipes.gd")

@onready var level: Node = get_node_or_null("MainLevel3D")
@onready var launcher: CanvasLayer = get_node_or_null("CounterCatsLauncher")
@onready var overlay: CanvasLayer = get_node_or_null("CounterCatsOverlay")

var rounds_played: int = 0
var _refresh_t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if level != null:
		level.process_mode = Node.PROCESS_MODE_PAUSABLE
	overlay.set("level", level)
	launcher.connect("start_requested", _on_start)
	launcher.connect("resume_requested", _on_resume)
	launcher.connect("fizz_requested", _on_fizz)
	launcher.connect("bond_requested", _on_bond)
	overlay.connect("closed", _on_closed)
	overlay.connect("parked", _on_parked)
	launcher.call("set_shown", true)

func _process(delta: float) -> void:
	_refresh_t -= delta
	if _refresh_t <= 0.0 and launcher.call("is_shown") and not bool(overlay.get("is_open")):
		_refresh_t = 0.5
		launcher.call("set_cats", _cat_summaries())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F11:
		if not bool(overlay.get("is_open")):
			launcher.call("set_shown", not bool(launcher.call("is_shown")))
			if bool(launcher.call("is_shown")):
				launcher.call("set_cats", _cat_summaries())
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ cats

func live_cats() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for c in get_tree().get_nodes_in_group("cats"):
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion():
			out.append(c)
	return out

func _num(o: Object, prop: String, fallback: float) -> float:
	var v = o.get(prop)
	return float(v) if (v is float or v is int) else fallback

func _resting(c: Object) -> bool:
	var st = c.get("state")
	return st != null and String(st) in ["rest", "retreating"]

func cat_info(c: Object) -> Dictionary:
	var th: float = _num(c, "overstim_threshold", 100.0)
	var o: float = _num(c, "overstimulation", 0.0)
	var def = c.get("cat_def")
	var traits_v = c.get("trait_ids")
	var traits: Array = []
	if traits_v is Array:
		for t in traits_v:
			traits.append(str(t))
	var nm = c.get("display_name")
	return {
		"node_id": c.get_instance_id(),
		"name": str(nm) if nm != null and str(nm) != "" else "Cat",
		"cat_def": def if def is Dictionary else {},
		"overstim": o, "threshold": th,
		"trust": _num(c, "trust", 0.0),
		"mood": R.mood_for(o, th),
		"traits": traits,
	}

func _cat_summaries() -> Array:
	var out: Array = []
	for c in live_cats():
		var i: Dictionary = cat_info(c)
		out.append({"id": i["node_id"], "name": i["name"], "mood": i["mood"], "overstim": i["overstim"], "trust": i["trust"], "resting": _resting(c)})
	return out

## The cat that most needs a break comes to the counter (highest overstim,
## not resting); a preferred cat goes first. Up to 2.
func pick_cats(preferred_id: int) -> Array:
	var pool: Array = []
	for c in live_cats():
		if not _resting(c):
			pool.append(c)
	pool.sort_custom(func(a, b) -> bool: return _num(a, "overstimulation", 0.0) > _num(b, "overstimulation", 0.0))
	if preferred_id != 0:
		for i in range(pool.size()):
			if pool[i].get_instance_id() == preferred_id:
				var p = pool[i]
				pool.remove_at(i)
				pool.push_front(p)
				break
	var out: Array = []
	for c in pool.slice(0, 2):
		out.append(cat_info(c))
	return out

# ------------------------------------------------------------------ flow

func build_context(opts: Dictionary) -> Dictionary:
	var ctx: Dictionary = opts.duplicate()
	ctx["cats"] = pick_cats(int(opts.get("preferred_cat", 0)))
	return ctx

func start(opts: Dictionary) -> void:
	launcher.call("set_shown", false)
	overlay.call("open", build_context(opts))

func _on_start(opts: Dictionary) -> void:
	if bool(overlay.get("is_parked")):
		overlay.set("is_parked", false)
		launcher.call("set_parked", false)
	start(opts)

func _on_resume() -> void:
	launcher.call("set_shown", false)
	overlay.call("open", {})

func _on_parked() -> void:
	launcher.call("set_parked", true)
	launcher.call("set_shown", true)

func _on_closed(result: Dictionary, _report: Dictionary) -> void:
	rounds_played += 1
	launcher.call("set_parked", false)
	if bool(result.get("left", false)):
		launcher.call("set_last_result", "Left the order. No harm done.")
	else:
		var pets: PackedStringArray = []
		for c in result.get("cats", []):
			if int(c.get("pets", 0)) > 0:
				pets.append("%s x%d" % [c["name"], int(c["pets"])])
		launcher.call("set_last_result", "Last: %s - %s %s, %s, +$%d%s" % [
			result.get("recipe_name", ""), result.get("grade", ""), result.get("grade_text", ""),
			_mmss(float(result.get("elapsed", 0.0))), int(result.get("money", 0)),
			("  - petted " + ", ".join(pets)) if not pets.is_empty() else ""])
	launcher.call("set_shown", true)
	launcher.call("set_cats", _cat_summaries())

func _mmss(t: float) -> String:
	var s: int = int(floor(t))
	return "%d:%02d" % [s / 60, s % 60]

# ------------------------------------------------------------------ test helpers

func _on_fizz() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for c in live_cats():
		if _resting(c) or c.get("overstimulation") == null:
			continue
		var th: float = _num(c, "overstim_threshold", 100.0)
		c.set("overstimulation", clampf(rng.randf_range(0.45, 0.9) * th, 0.0, th * 0.95))
	launcher.call("set_cats", _cat_summaries())

func _on_bond() -> void:
	var pref: int = int(launcher.call("options").get("preferred_cat", 0))
	var target: Object = null
	for c in live_cats():
		if pref == 0 or c.get_instance_id() == pref:
			target = c
			break
	if target == null:
		return
	if target.has_method("add_trust"):
		target.call("add_trust", maxf(0.0, 75.0 - _num(target, "trust", 0.0)))
	if target.get("overstimulation") != null:
		target.set("overstimulation", 0.0)
	launcher.call("set_cats", _cat_summaries())
	launcher.call("select_cat_id", target.get_instance_id())
