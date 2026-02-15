extends SceneTree

const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")

func _init() -> void:
	var loader = DataLoaderScript.new()
	var payload := loader.load_all_data()
	if payload.is_empty():
		push_error("Data validation failed: no payload")
		quit(1)
	print("Data validation completed.")
	quit()
