extends Node

## One-slot run-state save (contract 1.1).
## save_run_state(state) -> bool : atomic write (tmp -> keep .bak -> rename); never mutates `state`.
## load_run_state() -> Dictionary : migrated + backfilled from run_state_template.json; {} if none,
##                                   unreadable, or written by a newer build (future save_version).
## has_save() -> bool

const SAVE_PATH := "user://run_state.json"
const TEMPLATE_PATH := "res://Data/run_state_template.json"
const CURRENT_VERSION := 1

## Save slot path; the .tmp and .bak siblings are derived from it. Overridable for tests.
@export var save_path: String = SAVE_PATH

## Keys coerced to int after load (JSON numbers come back as floats).
const INT_KEYS: Array[String] = ["save_version", "day", "money", "reputation", "active_cats", "active_patrons", "adoptions_total", "run_seed"]

## Fallback used if the template file is missing or broken.
const DEFAULT_TEMPLATE := {
	"save_version": CURRENT_VERSION,
	"day": 1,
	"time_of_day": "morning",
	"money": 100,
	"reputation": 0,
	"active_cats": 0,
	"active_patrons": 0,
	"adoptions_total": 0,
	"placed_decor": [],
	"cats": [],
	"run_seed": 0,
	"unlocked_content": ["basic_layout"]
}

func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_bak_path())

func save_run_state(state: Dictionary) -> bool:
	var out: Dictionary = state.duplicate(true)
	out["save_version"] = CURRENT_VERSION
	var text := JSON.stringify(out, "\t")

	var f := FileAccess.open(_tmp_path(), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: unable to open %s for write (%s)" % [_tmp_path(), error_string(FileAccess.get_open_error())])
		return false
	var stored := f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if not stored or (write_err != OK and write_err != ERR_FILE_EOF):
		push_error("SaveSystem: failed writing %s (%s)" % [_tmp_path(), error_string(write_err)])
		DirAccess.remove_absolute(_abs(_tmp_path()))
		return false

	# Keep the previous good save as .bak, then move the new file into place.
	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(_bak_path()):
			DirAccess.remove_absolute(_abs(_bak_path()))
		var bak_err := DirAccess.rename_absolute(_abs(save_path), _abs(_bak_path()))
		if bak_err != OK:
			push_warning("SaveSystem: could not keep backup (%s)" % error_string(bak_err))
			DirAccess.remove_absolute(_abs(save_path))
	var mv_err := DirAccess.rename_absolute(_abs(_tmp_path()), _abs(save_path))
	if mv_err != OK:
		push_error("SaveSystem: failed to move save into place (%s)" % error_string(mv_err))
		return false
	return true

func load_run_state() -> Dictionary:
	if not has_save():
		return {}
	var raw: Variant = _read_json(save_path)
	if typeof(raw) != TYPE_DICTIONARY:
		if FileAccess.file_exists(save_path):
			push_warning("SaveSystem: save unreadable, trying backup")
		raw = _read_json(_bak_path())
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("SaveSystem: save file and backup could not be parsed")
			return {}
	return _migrate(raw)

## Returns a fresh copy of the run-state template (for a new run).
func new_run_state() -> Dictionary:
	return _load_template()

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("SaveSystem: parse error %s:%d %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _load_template() -> Dictionary:
	var template: Dictionary = DEFAULT_TEMPLATE.duplicate(true)
	if FileAccess.file_exists(TEMPLATE_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATE_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			template = parsed
		else:
			push_warning("SaveSystem: run_state_template.json unreadable, using built-in defaults")
	_coerce_ints(template)
	return template

func _migrate(raw: Dictionary) -> Dictionary:
	var version := int(raw.get("save_version", 0))
	if version > CURRENT_VERSION:
		push_error("SaveSystem: save_version %d is newer than supported %d; refusing to load (file left untouched)" % [version, CURRENT_VERSION])
		return {}
	var out: Dictionary = raw.duplicate(true)
	# Version steps go here (0 -> 1 only needs backfill).
	out["save_version"] = CURRENT_VERSION
	var template := _load_template()
	for key in template.keys():
		if not out.has(key):
			var v: Variant = template[key]
			out[key] = v.duplicate(true) if (typeof(v) == TYPE_ARRAY or typeof(v) == TYPE_DICTIONARY) else v
	_coerce_ints(out)
	_coerce_placed_decor(out)
	return out

func _coerce_ints(state: Dictionary) -> void:
	for key in INT_KEYS:
		if state.has(key) and (typeof(state[key]) == TYPE_FLOAT or typeof(state[key]) == TYPE_INT):
			state[key] = int(state[key])

func _coerce_placed_decor(state: Dictionary) -> void:
	if typeof(state.get("placed_decor")) != TYPE_ARRAY:
		state["placed_decor"] = []
		return
	for entry in state["placed_decor"]:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if entry.has("rotation") and (typeof(entry["rotation"]) == TYPE_FLOAT or typeof(entry["rotation"]) == TYPE_INT):
			entry["rotation"] = int(entry["rotation"])
		if typeof(entry.get("anchor")) == TYPE_ARRAY:
			var a: Array = entry["anchor"]
			for i in a.size():
				if typeof(a[i]) == TYPE_FLOAT:
					a[i] = int(a[i])

func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)

func _tmp_path() -> String:
	return save_path + ".tmp"

func _bak_path() -> String:
	return save_path + ".bak"
