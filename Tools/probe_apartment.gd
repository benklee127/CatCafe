extends SceneTree

## Apartment probe:
##   godot --headless --path . --script res://Tools/probe_apartment.gd
## 1. Boots Scenes/Environments/Apartment/Apartment.tscn (scene changes disabled).
## 2. For every hotspot: moves the mouse onto it (hover highlight must turn on), clicks it
##    (hotspot_activated(id) must fire and the prompt card must open), then clicks the
##    card's primary button (its specific signal must fire). Door is tested for both
##    "Go to Cafe" and "Go to Town"; the HUD "Go to Cafe" button too.
## 3. Watches the foster cats for ~40 s of game time: they must move, reach the bowls after
##    feeding, sit on the bonding nest, and never stand on a blocked / off-floor cell.
## Exit code 0 = PASS.

const SCENE := "res://Scenes/Environments/Apartment/Apartment.tscn"

var apt: Node3D
var failures: Array[String] = []
var fired: Dictionary = {}
var activated: Array[String] = []
var arrivals: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _fail(msg: String) -> void:
	failures.append(msg)
	printerr("FAIL: " + msg)

func _wait(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _wait_physics(n: int) -> void:
	for _i in range(n):
		await physics_frame

func _push_motion(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m, true)

func _click(p: Vector2) -> void:
	_push_motion(p)
	await _wait(2)
	for pressed in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = pressed
		b.position = p
		b.global_position = p
		root.push_input(b, true)
		await _wait(2)

func _run() -> void:
	Engine.time_scale = 3.0
	var packed: PackedScene = load(SCENE)
	apt = packed.instantiate()
	apt.set("allow_scene_change", false)
	apt.set("cat_seed", 1234)
	root.add_child(apt)
	await _wait(20)
	await _wait_physics(4)

	for sig in ["feed_cats_requested", "plan_tomorrow_requested", "wardrobe_requested"]:
		apt.connect(sig, func(): fired[sig] = true)
	apt.connect("sleep_requested", func(d): fired["sleep_requested"] = d)
	apt.connect("bonding_requested", func(c): fired["bonding_requested"] = c)
	apt.connect("travel_requested", func(dest): fired["travel_" + dest] = true)
	apt.connect("hotspot_activated", func(id): activated.append(id))
	var director: Node = apt.get("director")
	director.connect("cat_arrived", func(c, act): arrivals[act] = arrivals.get(act, 0) + 1)

	var hotspots: Dictionary = apt.get("hotspots")
	var hud: Node = apt.get("hud")
	var cam: Camera3D = apt.call("get_camera")
	var expected := {"feed": "feed_cats_requested", "bed": "sleep_requested", "planner": "plan_tomorrow_requested",
		"bond": "bonding_requested", "wardrobe": "wardrobe_requested", "door": "travel_cafe"}
	if hotspots.size() != expected.size():
		_fail("expected %d hotspots, got %d" % [expected.size(), hotspots.size()])

	# Start the cat watch in parallel with the clicks.
	var watch := {"bad": 0, "samples": 0, "start": {}, "dist": {}}
	var nav: Node = apt.get("nav")
	for cat in apt.get("cats"):
		watch["start"][cat] = cat.global_position
		watch["dist"][cat] = 0.0

	for id in ["feed", "planner", "wardrobe", "bond", "bed", "door"]:
		var h: Node = hotspots.get(id)
		if h == null:
			_fail("missing hotspot " + id)
			continue
		var sp: Vector2 = cam.unproject_position(h.call("get_focus_point"))
		_push_motion(sp)
		await _wait(3)
		if not bool(h.get("is_hovered")):
			_fail("%s: hover highlight did not turn on at %s (picked %s)" % [id, sp, apt.call("pick_hotspot_at", sp)])
		await _click(sp)
		if not activated.has(id):
			_fail("%s: hotspot_activated not fired" % id)
		if not bool(hud.call("is_card_open")) or str(hud.get("card_hotspot_id")) != id:
			_fail("%s: prompt card not open" % id)
			continue
		var primary: String = str(h.call("get_primary_action"))
		var btn: Button = (hud.get("card_buttons") as Dictionary).get(primary)
		if btn == null:
			_fail("%s: no card button for %s" % [id, primary])
			continue
		await _wait(12)  # card pop-in tween
		var bc: Vector2 = btn.get_global_rect().get_center()
		await _click(bc)
		if not fired.has(expected[id]):
			_fail("%s: %s not fired after clicking '%s' at %s (hovered: %s, card open: %s, card rect %s, btn visible %s)" % [id, expected[id], btn.text, bc, root.gui_get_hovered_control(), hud.call("is_card_open"), (hud.get("card") as Control).get_global_rect(), btn.is_visible_in_tree()])
		else:
			print("ok  %-9s -> %s" % [id, expected[id]])
		await _sample_cats(watch, nav, 30)
		if id == "feed":
			await _sample_cats(watch, nav, 500)

	# Door: second option, plus the HUD button.
	var door: Node = hotspots.get("door")
	await _click(cam.unproject_position(door.call("get_focus_point")))
	var tb: Button = (hud.get("card_buttons") as Dictionary).get("town")
	if tb != null:
		await _wait(12)
		await _click(tb.get_global_rect().get_center())
	if not fired.has("travel_town"):
		_fail("door: travel_requested(town) not fired")
	else:
		print("ok  door      -> travel_town")
	fired.erase("travel_cafe")
	var cb: Button = hud.get("cafe_button")
	await _click(cb.get_global_rect().get_center())
	if not fired.has("travel_cafe"):
		_fail("HUD Go to Cafe: travel_requested(cafe) not fired")
	else:
		print("ok  HUD button -> travel_cafe")

	# Watch cats a while longer (bonding nest, naps, wandering).
	await _sample_cats(watch, nav, 900)
	for cat in apt.get("cats"):
		var d: float = float(watch["dist"][cat])
		print("cat %s walked %.1f m, trust %.1f, state %s" % [cat.get("display_name"), d, float(cat.get("trust")), cat.get("state")])
		if d < 1.0:
			_fail("cat %s barely moved (%.2f m)" % [cat.name, d])
	if int(watch["bad"]) > 0:
		_fail("cats stood on non-walkable cells in %d of %d samples" % [watch["bad"], watch["samples"]])
	print("cat samples: %d, off-walkable: %d, arrivals: %s" % [watch["samples"], watch["bad"], arrivals])
	if int(arrivals.get("eat", 0)) < 1:
		_fail("no cat reached the bowls after feeding")
	if int(arrivals.get("bond", 0)) < 1:
		_fail("no cat reached the bonding nest")

	if failures.is_empty():
		print("PROBE APARTMENT: PASS")
		quit(0)
	else:
		print("PROBE APARTMENT: FAIL (%d)" % failures.size())
		quit(1)

var _last_pos: Dictionary = {}

func _sample_cats(watch: Dictionary, nav: Node, physics_frames: int) -> void:
	for _i in range(physics_frames):
		await physics_frame
		for cat in apt.get("cats"):
			var p: Vector3 = cat.global_position
			var g: Vector2i = nav.call("world_to_map", p)
			watch["samples"] = int(watch["samples"]) + 1
			if not bool(nav.call("is_walkable", g, false)):
				# Allow the moment a cat is between two cells: check the nearest cell centre.
				watch["bad"] = int(watch["bad"]) + 1
				if int(watch["bad"]) <= 3:
					printerr("cat %s on non-walkable cell %s at %s" % [cat.name, g, p])
			if _last_pos.has(cat):
				watch["dist"][cat] = float(watch["dist"][cat]) + Vector2(p.x, p.z).distance_to(Vector2(_last_pos[cat].x, _last_pos[cat].z))
			_last_pos[cat] = p
