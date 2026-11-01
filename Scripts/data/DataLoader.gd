extends Node

## Loads every Data/*.json file, validates it against Data/schemas/*.schema.json and runs
## cross-reference checks. Problems are pushed as errors/warnings and kept in
## `last_errors` / `last_warnings` so tools (Tools/validate_data.gd) can fail on them.

const SchemaValidatorScript := preload("res://Scripts/data/SchemaValidator.gd")
const CatPixelFaceScript := preload("res://Scripts/prototype3d/CatPixelFace.gd")
const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")

const RUN_STATE_TEMPLATE_PATH := "res://Data/run_state_template.json"

## key -> {path, schema (item schema for arrays), type, optional}
## type: TYPE_ARRAY, TYPE_DICTIONARY, or TYPE_NIL (array, or object wrapping an "entries" array).
const DATA_FILES := {
	"traits": {"path": "res://Data/traits.json", "schema": "TraitDefinition.schema.json", "type": TYPE_ARRAY},
	"patron_archetypes": {"path": "res://Data/patron_archetypes.json", "schema": "PatronArchetypeDefinition.schema.json", "type": TYPE_ARRAY},
	"decor": {"path": "res://Data/decor.json", "schema": "DecorDefinition.schema.json", "type": TYPE_ARRAY},
	"decor_ui": {"path": "res://Data/decor_ui.json", "schema": "DecorUi.schema.json", "type": TYPE_ARRAY},
	"decor_mesh_map": {"path": "res://Data/decor_mesh_map.json", "schema": "DecorMeshMap.schema.json", "type": TYPE_NIL},
	"rooms": {"path": "res://Data/rooms.json", "schema": "RoomDefinition.schema.json", "type": TYPE_ARRAY},
	"balance_config": {"path": "res://Data/balance_config.json", "schema": "BalanceConfig.schema.json", "type": TYPE_DICTIONARY},
	"cat_visual_pool": {"path": "res://Data/cat_visual_pool.json", "schema": "CatVisualPool.schema.json", "type": TYPE_ARRAY},
	"rescue_sources": {"path": "res://Data/rescue_sources.json", "schema": "RescueSource.schema.json", "type": TYPE_ARRAY, "optional": true},
	"cat_eye_shapes": {"path": "res://Data/cat_eye_shapes.json", "schema": "CatEyeShapes.schema.json", "type": TYPE_DICTIONARY, "optional": true}
}

var last_errors: Array[String] = []
var last_warnings: Array[String] = []

var _validator = SchemaValidatorScript.new()

func load_all_data() -> Dictionary:
	last_errors.clear()
	last_warnings.clear()
	var out := {}
	for key in DATA_FILES.keys():
		var spec: Dictionary = DATA_FILES[key]
		out[key] = _load_json(str(spec["path"]), int(spec["type"]), bool(spec.get("optional", false)))
	_validate_loaded_data(out)
	return out

## Validates a run-state dictionary (e.g. the template or a migrated save) against RunState.schema.json.
## Returns the list of errors (empty when valid). Does not touch last_errors.
func validate_run_state(state: Variant) -> Array[String]:
	var res: Dictionary = _validator.validate_with_file(state, "RunState.schema.json", "run_state")
	var errs: Array[String] = []
	for e in res.get("errors", []):
		errs.append(str(e))
	return errs

## Loads and validates Data/run_state_template.json. Errors are added to last_errors.
func validate_run_state_template() -> bool:
	var template: Variant = _load_json(RUN_STATE_TEMPLATE_PATH, TYPE_DICTIONARY, false)
	var errs := validate_run_state(template)
	for e in errs:
		_error("run_state_template: %s" % e)
	return errs.is_empty()

## Returns a typed empty value: [] for arrays, {} for objects.
func _empty_for(expected_type: int) -> Variant:
	if expected_type == TYPE_DICTIONARY:
		return {}
	return []

func _load_json(path: String, expected_type: int = TYPE_NIL, optional: bool = false) -> Variant:
	if not FileAccess.file_exists(path):
		if optional:
			_warn("Optional data file missing: %s" % path)
		else:
			_error("Data file missing: %s" % path)
		return _empty_for(expected_type)
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_error("Failed to parse JSON %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return _empty_for(expected_type)
	var parsed: Variant = json.data
	if expected_type == TYPE_NIL:
		if typeof(parsed) != TYPE_ARRAY and typeof(parsed) != TYPE_DICTIONARY:
			_error("%s must be a JSON array or object" % path)
			return []
		return parsed
	if typeof(parsed) != expected_type:
		_error("%s must be a JSON %s" % [path, "array" if expected_type == TYPE_ARRAY else "object"])
		return _empty_for(expected_type)
	return parsed

func _error(msg: String) -> void:
	last_errors.append(msg)
	push_error(msg)

func _warn(msg: String) -> void:
	last_warnings.append(msg)
	push_warning(msg)

func _report(res: Dictionary) -> void:
	for e in res.get("errors", []):
		_error(str(e))

## Accepts either a plain array of entries or an object wrapping them under "entries"
## (or the first array-of-objects value). Used for decor_mesh_map.
static func entries_of(value: Variant) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	if typeof(value) == TYPE_DICTIONARY:
		if typeof(value.get("entries", null)) == TYPE_ARRAY:
			return value["entries"]
		for k in value.keys():
			if typeof(value[k]) == TYPE_ARRAY:
				return value[k]
	return []

func _validate_loaded_data(data: Dictionary) -> void:
	# 1. Schema checks (required keys and types come from Data/schemas).
	for key in DATA_FILES.keys():
		var spec: Dictionary = DATA_FILES[key]
		var value: Variant = data.get(key)
		var schema_file := str(spec["schema"])
		match int(spec["type"]):
			TYPE_ARRAY:
				_report(_validator.validate_array_with_file(value, schema_file, key))
			TYPE_DICTIONARY:
				_report(_validator.validate_with_file(value, schema_file, key))
			_:
				_report(_validator.validate_array_with_file(entries_of(value), schema_file, key))

	# 2. Semantic and cross-reference checks.
	_check_unique_ids(data.get("traits", []), "id", "traits")
	_check_unique_ids(data.get("patron_archetypes", []), "id", "patron_archetypes")
	_check_unique_ids(data.get("decor", []), "id", "decor")
	_check_unique_ids(data.get("decor_ui", []), "id", "decor_ui")
	_check_unique_ids(entries_of(data.get("decor_mesh_map", [])), "decor_id", "decor_mesh_map")
	_check_unique_ids(data.get("rooms", []), "id", "rooms")
	_check_unique_ids(data.get("rescue_sources", []), "id", "rescue_sources")
	_check_decor_cross_refs(data)
	_check_balance(data.get("balance_config", {}))
	_check_rooms(data.get("rooms", []))
	_check_visual_pool(data.get("cat_visual_pool", []))
	_check_eye_shapes(data.get("cat_eye_shapes", {}), data.get("traits", []))
	_check_rescue_sources(data.get("rescue_sources", []), data.get("traits", []))
	_check_tag_overlap(data.get("traits", []), data.get("patron_archetypes", []))

func _ids_of(records: Variant, id_key: String) -> Dictionary:
	var ids := {}
	if typeof(records) != TYPE_ARRAY:
		return ids
	for r in records:
		if typeof(r) == TYPE_DICTIONARY and r.has(id_key):
			ids[str(r[id_key])] = r
	return ids

func _check_unique_ids(records: Variant, id_key: String, label: String) -> void:
	if typeof(records) != TYPE_ARRAY:
		return
	var seen := {}
	for r in records:
		if typeof(r) != TYPE_DICTIONARY or not r.has(id_key):
			continue
		var id := str(r[id_key])
		if seen.has(id):
			_error("%s: duplicate %s '%s'" % [label, id_key, id])
		seen[id] = true

func _check_decor_cross_refs(data: Dictionary) -> void:
	var decor_ids := _ids_of(data.get("decor", []), "id")
	var ui_ids := _ids_of(data.get("decor_ui", []), "id")
	var mesh_ids := _ids_of(entries_of(data.get("decor_mesh_map", [])), "decor_id")
	for id in decor_ids.keys():
		if not ui_ids.has(id):
			_error("decor '%s' has no decor_ui entry" % id)
		if not mesh_ids.has(id):
			_error("decor '%s' has no decor_mesh_map entry" % id)
	for id in ui_ids.keys():
		if not decor_ids.has(id):
			_warn("decor_ui '%s' has no decor.json definition (orphan id)" % id)
	for id in mesh_ids.keys():
		if not decor_ids.has(id):
			_warn("decor_mesh_map '%s' has no decor.json definition (orphan id)" % id)
		var entry: Dictionary = mesh_ids[id]
		var scene_path := str(entry.get("mesh_scene", ""))
		if scene_path.is_empty():
			continue
		if not ResourceLoader.exists(scene_path) and not FileAccess.file_exists(scene_path):
			_error("decor_mesh_map '%s': mesh_scene not found: %s" % [id, scene_path])

func _check_balance(balance: Variant) -> void:
	if typeof(balance) != TYPE_DICTIONARY:
		return
	var overstim: Dictionary = balance.get("overstim", {}) if typeof(balance.get("overstim")) == TYPE_DICTIONARY else {}
	var trust: Dictionary = balance.get("trust", {}) if typeof(balance.get("trust")) == TYPE_DICTIONARY else {}
	var population: Dictionary = balance.get("population", {}) if typeof(balance.get("population")) == TYPE_DICTIONARY else {}

	if overstim.has("trait_mult_min") and overstim.has("trait_mult_max"):
		if float(overstim["trait_mult_min"]) > float(overstim["trait_mult_max"]):
			_error("balance_config.overstim: trait_mult_min > trait_mult_max")
	if overstim.has("rest_release_threshold") and overstim.has("retreat_threshold"):
		if float(overstim["rest_release_threshold"]) >= float(overstim["retreat_threshold"]):
			_error("balance_config.overstim: rest_release_threshold must be below retreat_threshold")
	if population.has("patron_target_count") and population.has("patron_max_count"):
		if int(population["patron_target_count"]) > int(population["patron_max_count"]):
			_error("balance_config.population: patron_target_count > patron_max_count")

	var states: Variant = trust.get("states")
	if typeof(states) == TYPE_ARRAY and not states.is_empty():
		var prev := -INF
		for i in states.size():
			var s: Variant = states[i]
			if typeof(s) != TYPE_DICTIONARY or not _is_number(s.get("min")):
				continue
			var m := float(s["min"])
			if m <= prev:
				_error("balance_config.trust.states[%d]: min %s must be greater than the previous state's min" % [i, str(s["min"])])
			prev = m
		var first: Variant = states[0]
		if typeof(first) == TYPE_DICTIONARY and _is_number(first.get("min")) and float(first["min"]) != 0.0:
			_warn("balance_config.trust.states[0].min should be 0")
		var last: Variant = states[states.size() - 1]
		if typeof(last) == TYPE_DICTIONARY and _is_number(last.get("min")) and _is_number(trust.get("ready_threshold")):
			if not is_equal_approx(float(last["min"]), float(trust["ready_threshold"])):
				_error("balance_config.trust.states: last min (%s) must equal ready_threshold (%s)" % [str(last["min"]), str(trust["ready_threshold"])])
	if _is_number(trust.get("start")) and _is_number(trust.get("ready_threshold")):
		if float(trust["start"]) > float(trust["ready_threshold"]):
			_error("balance_config.trust.start exceeds ready_threshold")

func _rect_has(rect: Dictionary, cell: Dictionary) -> bool:
	var x := int(cell.get("x", 0))
	var y := int(cell.get("y", 0))
	var rx := int(rect.get("x", 0))
	var ry := int(rect.get("y", 0))
	return x >= rx and y >= ry and x < rx + int(rect.get("w", 0)) and y < ry + int(rect.get("h", 0))

func _check_rooms(rooms: Variant) -> void:
	if typeof(rooms) != TYPE_ARRAY:
		return
	if rooms.is_empty():
		_error("rooms: at least one room is required")
	for i in rooms.size():
		var room: Variant = rooms[i]
		if typeof(room) != TYPE_DICTIONARY:
			continue
		var label := "rooms[%d]" % i
		var floor_rect: Variant = room.get("cafe_floor_rect")
		var rest_rect: Variant = room.get("rest_area_rect")
		if typeof(floor_rect) != TYPE_DICTIONARY or typeof(rest_rect) != TYPE_DICTIONARY:
			continue  # Schema check already reported the old/invalid shape.
		var rest_corner := {"x": int(rest_rect.get("x", 0)) + int(rest_rect.get("w", 0)) - 1, "y": int(rest_rect.get("y", 0)) + int(rest_rect.get("h", 0)) - 1}
		if not _rect_has(floor_rect, rest_rect) or not _rect_has(floor_rect, rest_corner):
			_error("%s: rest_area_rect must lie inside cafe_floor_rect" % label)
		for list_key in ["patron_spawns", "cat_spawns"]:
			var cells: Variant = room.get(list_key, [])
			if typeof(cells) != TYPE_ARRAY:
				continue
			for j in cells.size():
				if typeof(cells[j]) != TYPE_DICTIONARY:
					continue
				if not _rect_has(floor_rect, cells[j]):
					_error("%s.%s[%d] is outside cafe_floor_rect" % [label, list_key, j])
				elif _rect_has(rest_rect, cells[j]):
					_error("%s.%s[%d] is inside the rest area" % [label, list_key, j])
		var entrance: Variant = room.get("entrance_cell")
		if typeof(entrance) == TYPE_DICTIONARY and not _rect_has(floor_rect, entrance):
			_error("%s.entrance_cell is outside cafe_floor_rect" % label)
		var doors: Variant = room.get("rest_door_cells", [])
		if typeof(doors) == TYPE_ARRAY:
			for j in doors.size():
				var d: Variant = doors[j]
				if typeof(d) != TYPE_DICTIONARY:
					continue
				if not _rect_has(floor_rect, d) or _rect_has(rest_rect, d):
					_error("%s.rest_door_cells[%d] must be a cafe cell outside the rest area" % [label, j])
					continue
				var dx := int(d.get("x", 0))
				var dy := int(d.get("y", 0))
				var adjacent := false
				for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _rect_has(rest_rect, {"x": dx + off.x, "y": dy + off.y}):
						adjacent = true
						break
				if not adjacent:
					_error("%s.rest_door_cells[%d] is not adjacent to the rest area edge" % [label, j])

func _check_visual_pool(pool: Variant) -> void:
	if typeof(pool) != TYPE_ARRAY:
		return
	if pool.is_empty():
		_error("cat_visual_pool: at least one entry is required")
		return
	var has_common := false
	for entry in pool:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("rarity", "common")) == "common":
			has_common = true
		if typeof(entry) == TYPE_DICTIONARY and typeof(entry.get("proportions")) == TYPE_DICTIONARY:
			for part in entry["proportions"].keys():
				var r: Variant = entry["proportions"][part]
				if typeof(r) == TYPE_ARRAY and r.size() == 2 and _is_number(r[0]) and _is_number(r[1]) and float(r[0]) > float(r[1]):
					_error("cat_visual_pool: proportions.%s range min > max for coat '%s'" % [part, str(entry.get("coat", "?"))])
	if not has_common:
		_error("cat_visual_pool: needs at least one common entry")

# Eye shape weights: shape lists agree (stamps / genome / data), the base odds
# can pick something, trait_bias keys are real trait ids, stamps are valid.
func _check_eye_shapes(cfg: Variant, traits: Variant) -> void:
	var stamp_shapes: Array = CatPixelFaceScript.EYE_SHAPES
	if Array(CatGenomeScript.EYE_SHAPES) != Array(stamp_shapes):
		_error("CatGenome.EYE_SHAPES %s != CatPixelFace.EYE_SHAPES %s" % [str(CatGenomeScript.EYE_SHAPES), str(stamp_shapes)])
	for pr in CatPixelFaceScript.validate():
		_error("CatPixelFace: %s" % pr)
	if typeof(cfg) != TYPE_DICTIONARY or (cfg as Dictionary).is_empty():
		return
	var base: Variant = cfg.get("base", {})
	if typeof(base) == TYPE_DICTIONARY:
		var total := 0.0
		for shape in stamp_shapes:
			if not base.has(shape):
				_warn("cat_eye_shapes: base has no weight for '%s' (never picked)" % shape)
			elif _is_number(base[shape]):
				total += float(base[shape])
		if total <= 0.0:
			_error("cat_eye_shapes: base weights sum to 0")
	var tb: Variant = cfg.get("trait_bias", {})
	if typeof(tb) == TYPE_DICTIONARY:
		var ids := _ids_of(traits, "id")
		for tid in tb.keys():
			if not ids.has(str(tid)):
				_error("cat_eye_shapes: trait_bias '%s' is not a trait id" % str(tid))

func _check_rescue_sources(sources: Variant, traits: Variant) -> void:
	if typeof(sources) != TYPE_ARRAY:
		return
	var trait_ids := _ids_of(traits, "id")
	for s in sources:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var id := str(s.get("id", "?"))
		var it: Variant = s.get("initial_trust")
		if typeof(it) == TYPE_ARRAY and it.size() == 2 and _is_number(it[0]) and _is_number(it[1]) and float(it[0]) > float(it[1]):
			_error("rescue_sources '%s': initial_trust min > max" % id)
		var rw: Variant = s.get("rarity_weights")
		if typeof(rw) == TYPE_DICTIONARY:
			var total := 0.0
			for k in rw.keys():
				if _is_number(rw[k]):
					total += float(rw[k])
			if total <= 0.0:
				_error("rescue_sources '%s': rarity_weights must sum to more than 0" % id)
		var bias: Variant = s.get("trait_bias")
		if typeof(bias) == TYPE_DICTIONARY:
			for t in bias.keys():
				if not trait_ids.has(str(t)):
					_error("rescue_sources '%s': trait_bias references unknown trait '%s'" % [id, str(t)])

func _check_tag_overlap(traits: Variant, archetypes: Variant) -> void:
	if typeof(traits) != TYPE_ARRAY or typeof(archetypes) != TYPE_ARRAY:
		return
	var patron_tags := {}
	for a in archetypes:
		if typeof(a) == TYPE_DICTIONARY and typeof(a.get("tags")) == TYPE_ARRAY:
			for t in a["tags"]:
				patron_tags[str(t)] = true
	for t in traits:
		if typeof(t) != TYPE_DICTIONARY or typeof(t.get("adoption_match_tags")) != TYPE_ARRAY:
			continue
		var hit := false
		for tag in t["adoption_match_tags"]:
			if patron_tags.has(str(tag)):
				hit = true
				break
		if not hit:
			_warn("trait '%s': no adoption_match_tags overlap any patron archetype tags" % str(t.get("id", "?")))

func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
