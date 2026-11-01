extends SceneTree

# Usage: godot --path . --script res://Tools/capture_screenshot.gd -- <scene_path> <out_png> [frames]
# Boots a scene windowed, waits N frames, saves a viewport screenshot, quits.

var _frames_left: int = 120
var _out_path: String = "user://screenshot.png"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	if args.size() >= 1:
		scene_path = args[0]
	if args.size() >= 2:
		_out_path = args[1]
	if args.size() >= 3:
		_frames_left = int(args[2])
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Could not load scene: %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())

func _process(_delta: float) -> bool:
	_frames_left -= 1
	if _frames_left > 0:
		return false
	var img: Image = root.get_viewport().get_texture().get_image()
	var err: int = img.save_png(_out_path)
	print("Saved screenshot to %s (err=%d)" % [_out_path, err])
	return true
