extends SceneTree

## Headless core-loop probe (Track C, C9). Uses only the section 1 contract names from
## the implementation plan, each guarded with has_method / `in` checks, so it reports
## FAIL rather than crashing while other tracks are still mid-work.
##
## Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 10 --script res://Tools/probe_core_loop.gd
## Optional user args (after `--`): --seed=N  --trials=N  --soak-frames=N  --skip=cat2d,rest,soak,slots
##
## Checks:
##   cat2d : instantiating Cat2D.tscn logs 0 `det == 0` errors and 0 "Bone2D" warnings.
##   rest  : a cat forced into REST at rest cell (2,2) is back on the cafe floor within
##           15 s (sim time), for every trial.
##   soak  : over N frames with patrons (overstim bumped every 300 frames to force
##           retreats) there are 0 retreating->interacting and 0 rest->interacting
##           transitions, and no cat stays in the rest area for more than 60 s at a stretch.
##   slots : every decor id placed at (14,12) on an empty floor at rotations 0/90/180/270
##           exposes only slots that are walkable and reachable (unwalkable_slots=[]).
## Exit code: 0 when every check passes, 1 otherwise.
##
## The probe never touches the player's save: it points any SaveSystem node at a probe
## file and restores user://run_state.json (+ .bak/.tmp) byte for byte on exit.

const MAIN_LEVEL_SCENE := "res://Scenes/Prototype3D/MainLevel3D.tscn"
const CAT2D_SCENE := "res://Scenes/Prototype3D/Cat2D.tscn"
const DATA_LOADER_SCRIPT := "res://Scripts/data/DataLoader.gd"
const PROBE_SAVE_PATH := "user://probe_core_loop_run_state.json"
const USER_SAVE_FILES: Array[String] = [
	"user://run_state.json", "user://run_state.json.bak", "user://run_state.json.tmp"
]

const REST_FORCE_CELL := Vector2i(2, 2)
const REST_RETURN_LIMIT_SEC := 15.0
const REST_STUCK_LIMIT_SEC := 60.0
const SOAK_BUMP_EVERY_FRAMES := 300
const SLOT_ANCHOR := Vector2i(14, 12)
const ROTATIONS: Array[int] = [0, 90, 180, 270]
const MAX_FRAMES_GUARD := 20000

const ST_INTERACTING := &"interacting"
const ST_RETREATING := &"retreating"
const ST_REST := &"rest"
const ST_RETURNING := &"returning"

## Counts engine errors/warnings while the probe runs (Godot 4.5+ Logger API).
class ErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var errors: Array[String] = []
	var warnings: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		var text := "%s %s (%s:%d %s)" % [code, rationale, file, line, function]
		_mutex.lock()
		if error_type == ERROR_TYPE_WARNING:
			warnings.append(text)
		else:
			errors.append(text)
		_mutex.unlock()

	func snapshot() -> Dictionary:
		_mutex.lock()
		var out := {"errors": errors.duplicate(), "warnings": warnings.duplicate()}
		_mutex.unlock()
		return out

## Accumulates simulated time (physics delta), independent of wall-clock speed.
class SimClock extends Node:
	var t: float = 0.0

	func _physics_process(delta: float) -> void:
		t += delta

var _logger: ErrorCounter
var _clock: SimClock
var _seed: int = 4242
var _trials: int = 20
var _soak_frames: int = 3000
var _skip: Array[String] = []
var _saved_user_files: Dictionary = {}
var _failures: Array[String] = []
var _results: Dictionary = {}
var _transitions: Dictionary = {}

func _initialize() -> void:
	_parse_args()
	_logger = ErrorCounter.new()
	OS.add_logger(_logger)
	_backup_user_save()
	_clock = SimClock.new()
	root.add_child(_clock)
	_run.call_deferred()

func _run() -> void:
	if not _skip.has("cat2d"):
		await _check_cat2d()
	if not _skip.has("rest") or not _skip.has("soak"):
		await _check_rest_and_soak()
	if not _skip.has("slots"):
		await _check_slots()
	_finish()

# ------------------------------------------------------------------ cat2d

func _check_cat2d() -> void:
	var before: Dictionary = _logger.snapshot()
	if not ResourceLoader.exists(CAT2D_SCENE):
		_fail("cat2d: %s missing" % CAT2D_SCENE)
		return
	var packed: PackedScene = load(CAT2D_SCENE) as PackedScene
	if packed == null:
		_fail("cat2d: could not load %s" % CAT2D_SCENE)
		return
	var cat2d: Node = packed.instantiate()
	root.add_child(cat2d)
	if cat2d.has_method("apply_genome"):
		cat2d.call("apply_genome", {"coat": "tuxedo", "fur_primary": "#ff0000"})
	await _frames(15)
	cat2d.queue_free()
	await _frames(2)
	var after: Dictionary = _logger.snapshot()
	var det_errors: int = _count_new(before.errors, after.errors, "det == 0")
	var bone_warnings: int = _count_new(before.warnings, after.warnings, "Bone2D")
	var other_errors: int = after.errors.size() - before.errors.size() - det_errors
	_results["cat2d"] = {"det_errors": det_errors, "bone2d_warnings": bone_warnings, "other_errors": other_errors}
	if det_errors > 0:
		_fail("cat2d: %d det==0 errors" % det_errors)
	if bone_warnings > 0:
		_fail("cat2d: %d Bone2D warnings" % bone_warnings)
	if other_errors > 0:
		_fail("cat2d: %d other errors while instancing Cat2D" % other_errors)

# ------------------------------------------------------------------ rest + soak

func _check_rest_and_soak() -> void:
	var level: Node = await _spawn_level({})
	if level == null:
		return
	await _frames(20)
	var cats: Array = _cats_of(level)
	if cats.is_empty():
		_fail("rest: no cats in group \"cats\" under the level")
		await _free_level(level)
		return
	var use_signal: bool = true
	for cat in cats:
		if not (cat as Object).has_signal("state_changed"):
			use_signal = false
	if use_signal:
		for cat in cats:
			(cat as Object).connect("state_changed", _on_cat_state_changed)
	else:
		_note("cats have no state_changed signal; polling state once per frame")

	if not _skip.has("rest"):
		await _rest_trials(level, cats, use_signal)
	if not _skip.has("soak"):
		await _soak(level, cats, use_signal)
	await _free_level(level)

func _rest_trials(level: Node, cats: Array, use_signal: bool) -> void:
	for method in ["is_in_rest_area", "map_to_world"]:
		if not level.has_method(method):
			_fail("rest: level lacks %s" % method)
			return
	var force_cell: Vector2i = REST_FORCE_CELL
	if not bool(level.call("is_in_rest_area", force_cell)):
		var rr: Variant = level.get("rest_area_rect")
		if rr is Rect2i:
			force_cell = (rr as Rect2i).get_center()
	var done: int = 0
	var passed: int = 0
	var worst: float = 0.0
	var stuck: Array[String] = []
	var poll_prev: Dictionary = {}
	while done < _trials:
		var batch: Array = []
		for cat in cats:
			if done + batch.size() >= _trials:
				break
			if is_instance_valid(cat):
				batch.append(cat)
		if batch.is_empty():
			_fail("rest: cats were freed during the trials")
			return
		for cat in batch:
			_force_rest(level, cat, force_cell)
		var t0: float = _clock.t
		var returned: Dictionary = {}
		var frames: int = 0
		while returned.size() < batch.size() and _clock.t - t0 <= REST_RETURN_LIMIT_SEC and frames < MAX_FRAMES_GUARD:
			await _frames(1)
			frames += 1
			if not use_signal:
				_poll_transitions(cats, poll_prev)
			for cat in batch:
				if returned.has(cat) or not is_instance_valid(cat):
					continue
				var g: Variant = cat.get("grid_position")
				if g is Vector2i and not bool(level.call("is_in_rest_area", g)):
					returned[cat] = _clock.t - t0
		for cat in batch:
			done += 1
			if returned.has(cat):
				passed += 1
				worst = maxf(worst, float(returned[cat]))
			else:
				stuck.append("%s state=%s grid=%s" % [_cat_name(cat), str(cat.get("state")), str(cat.get("grid_position"))])
		await _sim_seconds(1.0, cats, use_signal, poll_prev)
	_results["rest"] = {"trials": done, "returned": passed, "worst_return_sec": snappedf(worst, 0.01), "force_cell": str(force_cell), "stuck": stuck}
	if passed < done:
		_fail("rest: %d/%d forced-REST cats did not reach the cafe floor within %.0f s: %s" % [done - passed, done, REST_RETURN_LIMIT_SEC, ", ".join(stuck)])

func _force_rest(level: Node, cat: Node, cell: Vector2i) -> void:
	var y_off: float = 0.0
	var yo: Variant = level.get("actor_y_offset")
	if yo != null:
		y_off = float(yo)
	if cat is Node3D:
		(cat as Node3D).global_position = (level.call("map_to_world", cell) as Vector3) + Vector3(0.0, y_off, 0.0)
	if cat is CharacterBody3D:
		(cat as CharacterBody3D).velocity = Vector3.ZERO
	cat.set("grid_position", cell)
	var p: Variant = cat.get("path")
	if p is Array:
		(p as Array).clear()
	var threshold: Variant = cat.get("overstim_threshold")
	cat.set("overstimulation", float(threshold) if threshold != null else 100.0)
	var rest_const: Variant = cat.get("REST")
	cat.set("state", rest_const if rest_const != null else ST_REST)

func _soak(level: Node, cats: Array, use_signal: bool) -> void:
	_transitions.clear()
	var poll_prev: Dictionary = {}
	var in_rest_since: Dictionary = {}
	var longest_rest: float = 0.0
	var stuck_cats: Dictionary = {}
	var retreats_seen: int = 0
	for frame in range(_soak_frames):
		if frame % SOAK_BUMP_EVERY_FRAMES == SOAK_BUMP_EVERY_FRAMES - 1:
			for cat in cats:
				if is_instance_valid(cat) and _state_of(cat) not in [ST_RETREATING, ST_REST, ST_RETURNING]:
					var threshold: Variant = cat.get("overstim_threshold")
					cat.set("overstimulation", float(threshold) if threshold != null else 100.0)
		await _frames(1)
		if not use_signal:
			_poll_transitions(cats, poll_prev)
		for cat in cats:
			if not is_instance_valid(cat):
				continue
			var g: Variant = cat.get("grid_position")
			var in_rest: bool = g is Vector2i and bool(level.call("is_in_rest_area", g))
			if in_rest:
				if not in_rest_since.has(cat):
					in_rest_since[cat] = _clock.t
				var span: float = _clock.t - float(in_rest_since[cat])
				longest_rest = maxf(longest_rest, span)
				if span > REST_STUCK_LIMIT_SEC:
					stuck_cats[_cat_name(cat)] = true
			else:
				in_rest_since.erase(cat)
	for key in _transitions.keys():
		if String(key).ends_with("->" + String(ST_RETREATING)):
			retreats_seen += int(_transitions[key])
	var retreat_to_interact: int = int(_transitions.get("retreating->interacting", 0))
	var rest_to_interact: int = int(_transitions.get("rest->interacting", 0))
	var returning_to_interact: int = int(_transitions.get("returning->interacting", 0))
	_results["soak"] = {
		"frames": _soak_frames,
		"sim_sec": snappedf(_clock.t, 0.1),
		"retreats": retreats_seen,
		"retreating->interacting": retreat_to_interact,
		"rest->interacting": rest_to_interact,
		"returning->interacting": returning_to_interact,
		"longest_rest_area_stay_sec": snappedf(longest_rest, 0.1),
		"transitions": _transitions.duplicate()
	}
	if retreat_to_interact > 0:
		_fail("soak: %d retreating->interacting transitions (expected 0)" % retreat_to_interact)
	if rest_to_interact > 0:
		_fail("soak: %d rest->interacting transitions (expected 0)" % rest_to_interact)
	if not stuck_cats.is_empty():
		_fail("soak: cats stayed in the rest area > %.0f s: %s" % [REST_STUCK_LIMIT_SEC, ", ".join(stuck_cats.keys())])
	if retreats_seen == 0:
		_note("soak: no retreats observed, so the retreat checks were not exercised")

func _on_cat_state_changed(_cat, old_state: StringName, new_state: StringName) -> void:
	var key := "%s->%s" % [String(old_state), String(new_state)]
	_transitions[key] = int(_transitions.get(key, 0)) + 1

func _poll_transitions(cats: Array, prev: Dictionary) -> void:
	for cat in cats:
		if not is_instance_valid(cat):
			continue
		var s: StringName = _state_of(cat)
		if prev.has(cat) and prev[cat] != s:
			_on_cat_state_changed(cat, prev[cat], s)
		prev[cat] = s

# ------------------------------------------------------------------ slots

func _check_slots() -> void:
	var overrides := {"place_starter_layout": false, "cats_to_spawn": 0, "patrons_to_spawn": 0}
	var level: Node = await _spawn_level(overrides)
	if level == null:
		return
	for method in ["place_decor", "has_slot", "get_slot_grid", "is_walkable", "build_path"]:
		if not level.has_method(method):
			_fail("slots: level lacks %s" % method)
			await _free_level(level)
			return
	var decor_ids: Array = _decor_ids(level)
	if decor_ids.is_empty():
		_fail("slots: no decor ids found")
		await _free_level(level)
		return
	var unwalkable: Array[String] = []
	var unreachable: Array[String] = []
	var place_failed: Array[String] = []
	var skipped: Array[String] = []
	var checked_slots: int = 0
	var max_slot_id: int = 64
	for decor_id in decor_ids:
		for rot in ROTATIONS:
			var tag := "%s@%d" % [decor_id, rot]
			var before: Dictionary = _slot_ids(level, max_slot_id)
			var placed: bool = bool(level.call("place_decor", SLOT_ANCHOR, decor_id, rot))
			if not placed:
				var reason: String = ""
				if level.has_method("get_place_block_reason"):
					reason = String(level.call("get_place_block_reason", SLOT_ANCHOR, decor_id, rot))
				if reason.contains("rotation"):
					skipped.append("%s (%s)" % [tag, reason])
				else:
					place_failed.append("%s (%s)" % [tag, reason if reason != "" else "place_decor returned false"])
				continue
			var after: Dictionary = _slot_ids(level, max_slot_id + 64)
			var refs: Array[Vector2i] = _reference_cells(level)
			for sid in after.keys():
				max_slot_id = maxi(max_slot_id, int(sid))
				if before.has(sid):
					continue
				checked_slots += 1
				var cell: Vector2i = after[sid]
				if not bool(level.call("is_walkable", cell, false)):
					unwalkable.append("%s slot %d at %s" % [tag, int(sid), str(cell)])
					continue
				var reached: bool = false
				for ref in refs:
					if ref == cell or not (level.call("build_path", ref, cell, false) as Array).is_empty():
						reached = true
						break
				if not reached:
					unreachable.append("%s slot %d at %s" % [tag, int(sid), str(cell)])
			# Clear the floor for the next placement; rebuild the level if removal is unsupported.
			var removed: bool = level.has_method("remove_decor") and bool(level.call("remove_decor", SLOT_ANCHOR))
			if not removed or _slot_ids(level, max_slot_id + 64).size() > before.size():
				await _free_level(level)
				level = await _spawn_level(overrides)
				if level == null:
					return
	_results["slots"] = {
		"decor_ids": decor_ids.size(), "slots_checked": checked_slots,
		"unwalkable_slots": unwalkable, "unreachable_slots": unreachable,
		"place_failed": place_failed, "rotation_not_allowed": skipped
	}
	print("[probe] unwalkable_slots=%s" % str(unwalkable))
	if not unwalkable.is_empty():
		_fail("slots: %d unwalkable slots" % unwalkable.size())
	if not unreachable.is_empty():
		_fail("slots: %d unreachable slots" % unreachable.size())
	if not place_failed.is_empty():
		_fail("slots: %d placements at %s failed on an empty floor: %s" % [place_failed.size(), str(SLOT_ANCHOR), ", ".join(place_failed)])
	if checked_slots == 0:
		_fail("slots: no slots were registered by any decor")
	await _free_level(level)

func _slot_ids(level: Node, scan_to: int) -> Dictionary:
	var out: Dictionary = {}
	for sid in range(0, scan_to + 1):
		if bool(level.call("has_slot", sid)):
			out[sid] = level.call("get_slot_grid", sid)
	return out

func _reference_cells(level: Node) -> Array[Vector2i]:
	var refs: Array[Vector2i] = []
	var entrance: Variant = level.get("entrance_cell")
	if entrance is Vector2i and bool(level.call("is_walkable", entrance, false)):
		refs.append(entrance)
	if level.has_method("random_cafe_cell"):
		for _i in range(3):
			var c: Variant = level.call("random_cafe_cell")
			if c is Vector2i and bool(level.call("is_walkable", c, false)):
				refs.append(c)
	return refs

func _decor_ids(level: Node) -> Array:
	if level.has_method("get_available_decor_ids"):
		var ids: Array = level.call("get_available_decor_ids")
		if not ids.is_empty():
			return ids
	var loader: Node = (load(DATA_LOADER_SCRIPT) as GDScript).new()
	var data: Dictionary = loader.call("load_all_data")
	loader.free()
	var out: Array = []
	for entry in data.get("decor", []):
		if entry is Dictionary and (entry as Dictionary).has("id"):
			out.append(String(entry["id"]))
	return out

# ------------------------------------------------------------------ level helpers

func _spawn_level(overrides: Dictionary) -> Node:
	var packed: PackedScene = load(MAIN_LEVEL_SCENE) as PackedScene
	if packed == null:
		_fail("could not load %s" % MAIN_LEVEL_SCENE)
		return null
	var level: Node = packed.instantiate()
	if "run_seed" in level:
		level.set("run_seed", _seed)
	for key in overrides.keys():
		if key in level:
			level.set(key, overrides[key])
	var save_node: Node = level.get_node_or_null("SaveSystem")
	if save_node != null and "save_path" in save_node:
		save_node.set("save_path", PROBE_SAVE_PATH)
	root.add_child(level)
	await _frames(2)
	return level

func _free_level(level: Node) -> void:
	if is_instance_valid(level):
		level.queue_free()
	await _frames(2)

func _cats_of(level: Node) -> Array:
	var out: Array = []
	for n in get_nodes_in_group("cats"):
		if level.is_ancestor_of(n):
			out.append(n)
	return out

func _state_of(cat: Object) -> StringName:
	var s: Variant = cat.get("state")
	return StringName(str(s)) if s != null else &""

func _cat_name(cat: Object) -> String:
	var id: Variant = cat.get("cat_id")
	if id != null and String(id) != "":
		return String(id)
	return String((cat as Node).name)

func _frames(n: int) -> void:
	for _i in range(n):
		await process_frame

func _sim_seconds(sec: float, cats: Array, use_signal: bool, poll_prev: Dictionary) -> void:
	var t0: float = _clock.t
	var guard: int = 0
	while _clock.t - t0 < sec and guard < MAX_FRAMES_GUARD:
		await process_frame
		guard += 1
		if not use_signal:
			_poll_transitions(cats, poll_prev)

# ------------------------------------------------------------------ misc

func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var a: String = String(arg)
		if a.begins_with("--seed="):
			_seed = int(a.get_slice("=", 1))
		elif a.begins_with("--trials="):
			_trials = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--soak-frames="):
			_soak_frames = maxi(0, int(a.get_slice("=", 1)))
		elif a.begins_with("--skip="):
			for part in a.get_slice("=", 1).split(",", false):
				_skip.append(part.strip_edges())

func _count_new(before: Array, after: Array, needle: String) -> int:
	var n: int = 0
	for i in range(before.size(), after.size()):
		if String(after[i]).contains(needle):
			n += 1
	return n

func _fail(msg: String) -> void:
	_failures.append(msg)
	print("[probe] FAIL ", msg)

func _note(msg: String) -> void:
	print("[probe] note: ", msg)

func _backup_user_save() -> void:
	for path in USER_SAVE_FILES:
		if FileAccess.file_exists(path):
			_saved_user_files[path] = FileAccess.get_file_as_bytes(path)
		else:
			_saved_user_files[path] = null

func _restore_user_save() -> void:
	for path in _saved_user_files.keys():
		var original: Variant = _saved_user_files[path]
		if original == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			continue
		var current: PackedByteArray = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
		if current != original:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(original)
				f.close()
	for suffix in ["", ".bak", ".tmp"]:
		var probe_file: String = PROBE_SAVE_PATH + suffix
		if FileAccess.file_exists(probe_file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_file))

func _finish() -> void:
	_restore_user_save()
	var log_snap: Dictionary = _logger.snapshot()
	_results["engine_errors_total"] = log_snap.errors.size()
	_results["engine_warnings_total"] = log_snap.warnings.size()
	OS.remove_logger(_logger)
	var ok: bool = _failures.is_empty()
	print("[probe] RESULT ", JSON.stringify({"ok": ok, "seed": _seed, "failures": _failures, "results": _results}))
	print("[probe] %s (%d failure(s))" % ["PASS" if ok else "FAIL", _failures.size()])
	if is_instance_valid(_clock):
		_clock.queue_free()
	quit(0 if ok else 1)
