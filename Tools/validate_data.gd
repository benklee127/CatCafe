extends SceneTree

## Headless data validator. Exits 0 when all data is clean, 1 on any error.
## Usage: godot --headless --path . --script res://Tools/validate_data.gd

const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")

func _init() -> void:
	var loader = DataLoaderScript.new()
	var payload: Dictionary = loader.load_all_data()
	loader.validate_run_state_template()
	var errors: Array[String] = loader.last_errors.duplicate()
	var warnings: Array[String] = loader.last_warnings.duplicate()
	loader.free()

	if payload.is_empty():
		errors.append("no payload")
	for w in warnings:
		print("WARN  %s" % w)
	for e in errors:
		printerr("FAIL  %s" % e)
	if errors.is_empty():
		print("Data validation completed: 0 errors, %d warnings." % warnings.size())
		quit(0)
	else:
		printerr("Data validation FAILED: %d errors, %d warnings." % [errors.size(), warnings.size()])
		quit(1)
