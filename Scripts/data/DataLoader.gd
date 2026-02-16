extends Node

const SchemaValidatorScript := preload("res://Scripts/data/SchemaValidator.gd")

var _validator = SchemaValidatorScript.new()

func load_all_data() -> Dictionary:
	var out := {
		"traits": _load_json("res://Data/traits.json"),
		"patron_archetypes": _load_json("res://Data/patron_archetypes.json"),
		"decor": _load_json("res://Data/decor.json"),
		"decor_ui": _load_json("res://Data/decor_ui.json"),
		"decor_mesh_map": _load_json("res://Data/decor_mesh_map.json"),
		"rooms": _load_json("res://Data/rooms.json"),
		"balance_config": _load_json("res://Data/balance_config.json"),
		"cat_visual_pool": _load_json("res://Data/cat_visual_pool.json")
	}
	_validate_loaded_data(out)
	return out

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Data file missing: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("Failed to parse JSON: %s" % path)
		return {}
	return parsed

func _validate_loaded_data(data: Dictionary) -> void:
	var checks := [
		_validator.validate_array_of_dict(data.get("traits", []), ["id", "display_name", "overstim_rate_mult", "trust_gain_mult", "adoption_match_tags"], "traits"),
		_validator.validate_array_of_dict(data.get("patron_archetypes", []), ["id", "display_name", "overstim_impact", "spend_rate", "visit_duration_sec", "tags"], "patron_archetypes"),
		_validator.validate_array_of_dict(data.get("decor", []), ["id", "category", "buffs", "aura_radius", "stack_rule", "placement"], "decor"),
		_validator.validate_array_of_dict(data.get("decor_ui", []), ["id", "name", "color", "durability"], "decor_ui"),
		_validator.validate_array_of_dict(data.get("decor_mesh_map", []), ["decor_id", "mesh_scene", "footprint", "pivot_offset", "rotations", "slot_markers"], "decor_mesh_map"),
		_validator.validate_array_of_dict(data.get("rooms", []), ["id", "tile_width", "tile_height", "rest_area_tile", "patron_spawns", "cat_spawns"], "rooms")
	]
	for check in checks:
		if not bool(check.get("ok", false)):
			push_error(str(check.get("error", "Unknown schema validation error")))
