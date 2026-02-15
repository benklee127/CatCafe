extends Node

const SAVE_PATH := "user://run_state.json"
const CURRENT_VERSION := 1

func save_run_state(state: Dictionary) -> bool:
	state["save_version"] = CURRENT_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Unable to open save file for write")
		return false
	f.store_string(JSON.stringify(state, "\t"))
	return true

func load_run_state() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save file parse failed")
		return {}
	return _migrate(parsed)

func _migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("save_version", 0))
	if version == CURRENT_VERSION:
		return raw
	if version == 0:
		raw["save_version"] = 1
		if not raw.has("unlocked_content"):
			raw["unlocked_content"] = ["basic_layout"]
		return raw
	push_warning("Unknown save version %d, attempting compatibility load" % version)
	raw["save_version"] = CURRENT_VERSION
	if not raw.has("unlocked_content"):
		raw["unlocked_content"] = ["basic_layout"]
	return raw
