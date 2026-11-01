extends SceneTree

## Windowed screenshot tour of the apartment (not headless):
##   godot --path . --script res://Tools/probe_apartment_shots.gd -- <out_dir> [seed]
## Saves overview.png, default.png, cat_corner.png, hover.png, card.png, kitchen.png.

var out_dir: String = "user://apartment_shots"
var apt: Node3D

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 1:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	apt = load("res://Scenes/Environments/Apartment/Apartment.tscn").instantiate()
	apt.set("allow_scene_change", false)
	apt.set("cat_seed", int(args[1]) if args.size() >= 2 else 1234)
	root.add_child(apt)
	_run.call_deferred()

func _wait(n: int) -> void:
	for _i in range(n):
		await process_frame

func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = root.get_viewport().get_texture().get_image()
	var p: String = out_dir.path_join(file)
	img.save_png(p)
	print("saved ", p)

func _move(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)

func _run() -> void:
	await _wait(90)
	var rig: Node = apt.get("camera_rig")
	var cam: Camera3D = apt.call("get_camera")
	var pts: Dictionary = apt.get("builder").get("points")
	_move(Vector2(5, 5))
	await _wait(5)
	await _shot("default.png")
	rig.call("focus_on", Vector3(0, 0.3, 0), rig.call("get_fit_size"))
	await _wait(10)
	await _shot("overview.png")
	# Send a cat to the nest so the corner has life in it.
	apt.get("director").call("bond")
	await _wait(240)
	rig.call("focus_on", Vector3(3.0, 0.3, 1.4), 5.6)
	await _wait(10)
	await _shot("cat_corner.png")
	rig.call("focus_on", Vector3(-1.5, 0.5, -1.5), 8.0)
	await _wait(10)
	var bed: Node = apt.get("hotspots")["bed"]
	_move(cam.unproject_position(bed.call("get_focus_point")))
	await _wait(12)
	await _shot("hover.png")
	var feed: Node = apt.get("hotspots")["feed"]
	rig.call("focus_on", Vector3(2.8, 0.5, -1.6), 7.5)
	await _wait(10)
	var fp: Vector2 = cam.unproject_position(feed.call("get_focus_point"))
	_move(fp)
	await _wait(5)
	feed.call("activate")
	await _wait(30)
	await _shot("card.png")
	apt.get("hud").call("press_action", "feed")
	_move(Vector2(5, 5))
	await _wait(300)
	await _shot("kitchen.png")
	quit(0)
