extends CanvasLayer

## Text debug HUD shared by the legacy prototypes (and usable from 3D).
## Works with CatAgent (int enum state, `overstim`) and MainLevelCat / MainLevelCat3D
## (StringName state, `overstimulation`). Call render_debug at ~4 Hz; it throttles itself.

const REFRESH_INTERVAL_SEC := 0.25
const LEGACY_STATE_NAMES: Array[String] = ["WANDER", "RETREAT", "REST"]
const UNAVAILABLE_STATES: Array[String] = ["retreat", "retreating", "rest", "returning"]

var label: Label
var _refresh_timer: float = 0.0

func _ready() -> void:
	label = Label.new()
	label.position = Vector2(16, 12)
	label.size = Vector2(760, 520)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

func _process(delta: float) -> void:
	_refresh_timer = maxf(0.0, _refresh_timer - delta)

func render_debug(cats: Array, patrons: Array, run_state: Dictionary = {}) -> void:
	if label == null or _refresh_timer > 0.0:
		return
	_refresh_timer = REFRESH_INTERVAL_SEC
	var lines: Array[String] = []
	lines.append("CAT CAFE DEBUG HUD")
	if not run_state.is_empty():
		lines.append("Day %d | Money %d | Reputation %d" % [
			int(run_state.get("day", 1)), int(run_state.get("money", 0)), int(run_state.get("reputation", 0))
		])
	var on_floor: int = 0
	for c in cats:
		if is_instance_valid(c) and _is_available(c):
			on_floor += 1
	lines.append("Cats: %d (on floor %d, resting %d) | Patrons: %d" % [cats.size(), on_floor, cats.size() - on_floor, patrons.size()])
	if not cats.is_empty() and on_floor == 0:
		lines.append("!! CAT DROUGHT: every cat is resting")
	for c in cats:
		if not is_instance_valid(c):
			continue
		lines.append("%s | overstim %.1f | state %s" % [c.name, _overstim_of(c), _state_name(c.get("state"))])
	label.text = "\n".join(lines)

func _overstim_of(c: Object) -> float:
	var v: Variant = c.get("overstimulation")
	if v == null:
		v = c.get("overstim")
	return float(v) if v != null else 0.0

func _is_available(c: Object) -> bool:
	if c.has_method("is_available_on_floor"):
		return bool(c.call("is_available_on_floor"))
	return not UNAVAILABLE_STATES.has(_state_name(c.get("state")).to_lower())

func _state_name(state_value: Variant) -> String:
	match typeof(state_value):
		TYPE_INT:
			var idx: int = int(state_value)
			if idx >= 0 and idx < LEGACY_STATE_NAMES.size():
				return LEGACY_STATE_NAMES[idx]
			return "UNKNOWN"
		TYPE_STRING_NAME, TYPE_STRING:
			return String(state_value).to_upper()
		_:
			return "UNKNOWN"
