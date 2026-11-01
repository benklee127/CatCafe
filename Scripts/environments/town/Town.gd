extends Node3D

## Town environment (res://Scenes/Environments/Town/Town.tscn).
## A compact autumn town block seen with the cafe's iso camera: the player's cat cafe,
## the partner shelter, the back alley, the player's apartment, a pet supply shop, a
## park and a corner market. Clickable hotspots open a cozy prompt card; "Go" calls
## confirm_hotspot(), which emits hotspot_activated + one specific signal per spot.
## All gameplay behind the spots is a STUB for now: see Docs/environments/TOWN.md.

const L := preload("res://Scripts/environments/town/TownLayout.gd")
const Kit := preload("res://Scripts/environments/common/town_proc_kit.gd")
const Builder := preload("res://Scripts/environments/town/TownBuilder.gd")
const HotspotScript := preload("res://Scripts/environments/town/TownHotspot.gd")
const WalkerScript := preload("res://Scripts/environments/town/TownWalker.gd")
const StrayScript := preload("res://Scripts/environments/town/TownStray.gd")
const HUDScript := preload("res://Scripts/environments/town/TownHUD.gd")

const HUMAN_SCENE := "res://Scenes/Prototype3D/Human3D.tscn"
const CAT_SCENE := "res://Scenes/Prototype3D/Cat3D.tscn"
const CAFE_SCENE := "res://Scenes/Prototype3D/MainLevel3D.tscn"
const HOME_SCENE := "res://Scenes/Environments/Apartment/Apartment.tscn"
const RESCUE_SOURCES_PATH := "res://Data/rescue_sources.json"
const PATRON_ARCHETYPES_PATH := "res://Data/patron_archetypes.json"

## Generic: every confirmed hotspot (after the card's Go button or confirm_hotspot()).
signal hotspot_activated(id: StringName, info: Dictionary)
signal hotspot_hovered(id: StringName)
## Specific stubs (see TOWN.md for the intended gameplay).
signal enter_cafe_requested
signal visit_shelter_requested(source: Dictionary)
signal alley_searched(found_stray: bool, rarity: String, source: Dictionary)
signal go_home_requested(scene_available: bool)
signal shop_browse_requested
signal park_sit_requested
signal market_visit_requested
signal doorstep_event_found(spot_id: StringName, source: Dictionary)
## Emitted right before a scene change (also when auto_travel is off).
signal travel_requested(scene_path: String)

## 0 = day, ~0.55 = autumn evening (default), 1 = night.
@export_range(0.0, 1.0, 0.01) var time_of_day: float = 0.55:
	set(v):
		time_of_day = clampf(v, 0.0, 1.0)
		if is_inside_tree():
			_apply_time_of_day()
## Change scenes on "Go" (cafe / home). The probe turns this off.
@export var auto_travel: bool = true
## Chance that "Search the alley" turns up a stray (placeholder until the intake flow).
@export_range(0.0, 1.0) var alley_find_chance: float = 0.35
@export var walker_count: int = 5
@export var stray_count: int = 2
@export var rng_seed: int = 0

@onready var camera_rig: Node3D = $CameraRig
@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment

var kit: Kit
var builder: Builder
var hud: CanvasLayer
var hotspots: Dictionary = {}
var walkers: Array[Node3D] = []
var strays: Array[Node3D] = []
var peekers: Dictionary = {}
var rescue_sources: Dictionary = {}
var rng := RandomNumberGenerator.new()
var hovered_id: StringName = &""
var _mouse_pos: Vector2 = Vector2(-1, -1)
var _mouse_dirty: bool = false

func _ready() -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	_load_data()
	kit = Kit.new()
	builder = Builder.new(kit)
	builder.build($World)
	_build_doorstep_spots()
	_build_hotspots()
	_spawn_walkers()
	_spawn_strays()
	hud = HUDScript.new()
	hud.name = "TownHUD"
	add_child(hud)
	hud.go_pressed.connect(confirm_hotspot)
	camera_rig.set("height_range", Vector2(-0.8, 8.5))
	camera_rig.call("setup", L.GROUND, Vector3(-1.0, 0.0, -3.0), -1.0)
	_apply_time_of_day()

# ------------------------------------------------------------------ data

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var txt: String = FileAccess.get_file_as_string(path)
	return JSON.parse_string(txt)

func _load_data() -> void:
	var src = _load_json(RESCUE_SOURCES_PATH)
	if src is Array:
		for s in src:
			if s is Dictionary and s.has("id"):
				rescue_sources[String(s["id"])] = s

func get_rescue_source(id: String) -> Dictionary:
	return rescue_sources.get(id, {"id": id})

# ------------------------------------------------------------------ hotspots

## Hotspot table. ring = where the prompt ring sits; area = click volume (world).
func hotspot_defs() -> Array:
	var shelter: Dictionary = get_rescue_source("shelter")
	var alley: Dictionary = get_rescue_source("alley")
	var trust_s: Array = shelter.get("initial_trust", [30, 45])
	var trust_a: Array = alley.get("initial_trust", [5, 20])
	return [
		{"id": "cafe", "title": "The Cat Cafe", "subtitle": "Your cafe", "icon": "cat", "verb": "Enter cafe",
			"desc": "Warm lights, sleepy cats and the smell of cocoa. Step inside to open for the day.",
			"tags": ["Your business"], "ring": Vector3(-5.8, 0, -4.9),
			"area_center": Vector3(-5.8, 2.6, -8.0), "area_size": Vector3(7.6, 5.6, 4.6), "marker_y": 3.0},
		{"id": "shelter", "title": "Paws & Hearts Shelter", "subtitle": "Rescue source: %s" % String(shelter.get("display_name", "Partner Shelter")), "icon": "paw", "verb": "Visit shelter",
			"desc": "The partner shelter has calm, healthy cats waiting for a foster home.",
			"tags": ["$%d adoption fee" % int(shelter.get("cost_money", 20)), "Trust %d-%d" % [int(trust_s[0]), int(trust_s[1])], "Mostly common"],
			"ring": Vector3(2.0, 0, -4.9), "area_center": Vector3(2.0, 2.6, -8.0), "area_size": Vector3(7.2, 5.6, 4.6), "marker_y": 3.1},
		{"id": "alley", "title": "Back Alley", "subtitle": "Rescue source: %s" % String(alley.get("display_name", "Back Alley")), "icon": "search", "verb": "Search alley",
			"desc": "Something rustles behind the bins. Strays here are shy, but rare kitties hide in alleys.",
			"tags": ["Free", "Takes %dh" % int(alley.get("time_cost_hours", 2)), "Trust %d-%d" % [int(trust_a[0]), int(trust_a[1])], "Rare chance"],
			"ring": Vector3(8.1, 0, -6.6), "area_center": Vector3(8.05, 1.5, -8.8), "area_size": Vector3(4.9, 3.0, 5.6), "marker_y": 2.6},
		{"id": "home", "title": "Maple Court", "subtitle": "Your apartment", "icon": "house", "verb": "Go home",
			"desc": "Your cozy flat upstairs. Rest up, plan tomorrow, maybe foster a cat at home.",
			"tags": ["Home"], "ring": Vector3(-9.0, 0, -1.5),
			"area_center": Vector3(-12.0, 3.5, -1.5), "area_size": Vector3(5.0, 7.0, 8.4), "marker_y": 3.2},
		{"id": "shop", "title": "Kibble & Co.", "subtitle": "Pet supplies", "icon": "bone", "verb": "Browse shop",
			"desc": "Treats, toys, scratchers and cat trees. Soon: decor and treats for the cafe.",
			"tags": ["Decor", "Treats", "Coming soon"], "ring": Vector3(-9.0, 0, 6.6),
			"area_center": Vector3(-12.0, 2.5, 6.6), "area_size": Vector3(5.0, 5.0, 6.4), "marker_y": 3.0},
		{"id": "park", "title": "Maple Park", "subtitle": "A quiet bench under the maple", "icon": "tree", "verb": "Sit a while",
			"desc": "Regulars walk their adopted cats here. A good spot to meet future patrons and alumni.",
			"tags": ["Relax", "Patrons", "Alumni visits"], "ring": builder.points.get("park_ring", Vector3(2.6, 0, 9.4)),
			"area_center": Vector3(2.2, 1.0, 9.0), "area_size": Vector3(3.6, 2.2, 3.4), "marker_y": 2.0},
		{"id": "market", "title": "Corner Market", "subtitle": "Bakery & produce stall", "icon": "bread", "verb": "Browse stall",
			"desc": "Fresh bread, apples and pumpkins. Soon: ingredients for cafe recipes.",
			"tags": ["Ingredients", "Cooking", "Coming soon"], "ring": builder.points.get("market_ring", Vector3(11.6, 0, 9.6)),
			"area_center": Vector3(11.6, 1.5, 8.0), "area_size": Vector3(3.6, 3.2, 2.6), "marker_y": 3.6},
		{"id": "doorstep_cafe", "title": "A box by the door?", "subtitle": "Doorstep surprise", "icon": "box", "verb": "Peek inside",
			"desc": "A cardboard box sits by the cafe door. Two little ears are poking out...",
			"tags": ["Hidden", "Trust 0-10"], "ring": Vector3(-4.35, 0, -5.4), "hidden": true, "ring_size": 1.0,
			"area_center": Vector3(-4.35, 0.3, -5.4), "area_size": Vector3(0.9, 0.8, 0.9), "marker_y": 1.0},
		{"id": "doorstep_home", "title": "A rustling basket", "subtitle": "Doorstep surprise", "icon": "box", "verb": "Take a look",
			"desc": "A basket by the stoop wobbles on its own. Someone small might be hiding inside.",
			"tags": ["Hidden", "Trust 0-10"], "ring": Vector3(-9.6, 0, 0.55), "hidden": true, "ring_size": 1.0,
			"area_center": Vector3(-9.6, 0.3, 0.55), "area_size": Vector3(0.9, 0.8, 0.9), "marker_y": 1.0},
	]

func _build_hotspots() -> void:
	var layer := Node3D.new()
	layer.name = "Hotspots"
	add_child(layer)
	for def in hotspot_defs():
		var d: Dictionary = def
		var id: String = d["id"]
		if builder.buildings.has(id):
			d["highlight"] = builder.buildings[id]
		elif id.begins_with("doorstep") and builder.points.has(id + "_node"):
			d["highlight"] = builder.points[id + "_node"]
		var hs: Area3D = HotspotScript.new()
		layer.add_child(hs)
		hs.call("setup", d, kit.font())
		hotspots[StringName(id)] = hs

func get_hotspot_ids() -> Array:
	return hotspots.keys()

func get_hotspot(id: StringName) -> Area3D:
	return hotspots.get(id, null)

## Opens the prompt card for a hotspot (what a click does).
func activate_hotspot(id: StringName) -> void:
	var hs: Area3D = get_hotspot(id)
	if hs == null:
		return
	if hud != null:
		hud.call("show_card", hs.get("info"))

## Runs a hotspot (what the card's Go button does). Every spot emits hotspot_activated
## plus its specific signal; the gameplay behind each is a stub (toast) for now.
func confirm_hotspot(id: StringName) -> void:
	var hs: Area3D = get_hotspot(id)
	if hs == null:
		return
	var info: Dictionary = (hs.get("info") as Dictionary).duplicate()
	info.erase("highlight")
	hotspot_activated.emit(id, info)
	match String(id):
		"cafe":
			enter_cafe_requested.emit()
			_toast("Opening the cafe...")
			_travel(CAFE_SCENE)
		"shelter":
			visit_shelter_requested.emit(get_rescue_source("shelter"))
			_toast("The adoption desk opens soon. The cats say hi!")
		"alley":
			_search_alley()
		"home":
			var avail: bool = ResourceLoader.exists(HOME_SCENE)
			go_home_requested.emit(avail)
			if avail:
				_toast("Heading home...")
				_travel(HOME_SCENE)
			else:
				_toast("Home is still being unpacked. Coming soon!", 3.0)
		"shop":
			shop_browse_requested.emit()
			_toast("The shelves are still being stocked. Coming soon!")
		"park":
			park_sit_requested.emit()
			_toast("You sit for a while. Leaves drift past the bench.")
		"market":
			market_visit_requested.emit()
			_toast("Fresh loaves! Recipe ingredients coming soon.")
		_:
			if String(id).begins_with("doorstep"):
				var src: Dictionary = get_rescue_source("doorstep_event")
				doorstep_event_found.emit(id, src)
				if peekers.has(id):
					(peekers[id] as Node).call("startle")
				_toast("A frightened stray! (Doorstep intake coming soon)", 3.0)

func _search_alley() -> void:
	var src: Dictionary = get_rescue_source("alley")
	var found: bool = rng.randf() < alley_find_chance
	var rarity: String = ""
	if found:
		rarity = _roll_rarity(src.get("rarity_weights", {}))
	for s in strays:
		var ctl: Node = s.get_node_or_null("TownStray")
		if ctl != null:
			ctl.call("startle")
	alley_searched.emit(found, rarity, src)
	if found:
		_toast("You found a shy %s stray! (Intake coming soon)" % rarity, 3.0)
	else:
		_toast("Just a rustle in the bins... maybe next time.", 2.6)

func _roll_rarity(weights: Dictionary) -> String:
	var total: float = 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return "common"
	var roll: float = rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return "common"

func _travel(path: String) -> void:
	travel_requested.emit(path)
	if auto_travel and is_inside_tree() and ResourceLoader.exists(path):
		get_tree().call_deferred("change_scene_to_file", path)

func _toast(text: String, sec: float = 2.6) -> void:
	if hud != null:
		hud.call("show_toast", text, sec)

# ------------------------------------------------------------------ picking

func _unhandled_input(event: InputEvent) -> void:
	if camera_rig != null and camera_rig.call("handle_input", event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
		_mouse_dirty = true
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var id: StringName = pick_hotspot_at(mb.position)
			if id != &"":
				activate_hotspot(id)
				get_viewport().set_input_as_handled()
			elif hud != null and bool(hud.call("is_card_open")):
				hud.call("close_card")
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_T:
				cycle_time_of_day()
			elif key.keycode == KEY_ESCAPE and hud != null:
				hud.call("close_card")

## Hotspot under a screen position ("" if none). Camera ray vs. hotspot areas only.
func pick_hotspot_at(screen_pos: Vector2) -> StringName:
	var cam: Camera3D = camera_rig.get("camera")
	if cam == null:
		return &""
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var dir: Vector3 = cam.project_ray_normal(screen_pos)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, HotspotScript.HOTSPOT_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return &""
	var col = hit.get("collider")
	if col != null and col.get("hotspot_id") != null:
		return StringName(col.get("hotspot_id"))
	return &""

func set_hovered(id: StringName) -> void:
	if id == hovered_id:
		return
	if hotspots.has(hovered_id):
		(hotspots[hovered_id] as Node).call("set_hovered", false)
	hovered_id = id
	if hotspots.has(id):
		(hotspots[id] as Node).call("set_hovered", true)
		hotspot_hovered.emit(id)
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if id != &"" else Input.CURSOR_ARROW)

func _process(_delta: float) -> void:
	if _mouse_dirty:
		_mouse_dirty = false
		if hud != null and bool(hud.call("is_mouse_over_ui")):
			set_hovered(&"")
		else:
			set_hovered(pick_hotspot_at(_mouse_pos))

# ------------------------------------------------------------------ actors

func _spawn_walkers() -> void:
	if not ResourceLoader.exists(HUMAN_SCENE):
		return
	var packed: PackedScene = load(HUMAN_SCENE)
	var archetypes: Array = []
	var data = _load_json(PATRON_ARCHETYPES_PATH)
	if data is Array:
		archetypes = data
	var layer := Node3D.new()
	layer.name = "Townsfolk"
	add_child(layer)
	var routes: Array = L.walker_routes()
	var right: Vector3 = camera_rig.call("screen_right")
	for i in range(mini(walker_count, routes.size())):
		var h: Node3D = packed.instantiate()
		h.name = "Walker%d" % i
		layer.add_child(h)
		var look: Dictionary = {}
		if not archetypes.is_empty():
			look = archetypes[i % archetypes.size()]
			if String(look.get("id", "")) == "hyper_toddler" and i > 2:
				look = archetypes[0]
		var ctl: Node = WalkerScript.new()
		ctl.name = "TownWalker"
		h.add_child(ctl)
		ctl.set("screen_right", right)
		ctl.call("setup", h, routes[i], 1000 + i * 77 + (rng_seed if rng_seed != 0 else 0), 0.15 + 0.17 * float(i), look)
		walkers.append(h)

func _build_doorstep_spots() -> void:
	var g := Node3D.new()
	g.name = "DoorstepSpots"
	$World.add_child(g)
	# Cafe doorstep: an open cardboard box with flaps.
	var cafe_box := kit.node(g, "CafeBox", Vector3(-4.35, 0, -5.4), 12.0)
	var card_mat: Material = kit.mat(Color("C9A27A"), 0.95)
	var inner: Material = kit.mat(Color("8A6446"), 0.95)
	kit.box(cafe_box, Vector3(0, 0.005, 0), Vector3(0.6, 0.01, 0.5), inner, false)
	for p in [[Vector3(0, 0.15, 0.25), Vector3(0.6, 0.3, 0.03)], [Vector3(0, 0.15, -0.25), Vector3(0.6, 0.3, 0.03)], [Vector3(0.3, 0.15, 0), Vector3(0.03, 0.3, 0.5)], [Vector3(-0.3, 0.15, 0), Vector3(0.03, 0.3, 0.5)]]:
		kit.box(cafe_box, p[0], p[1], card_mat)
	var flap1: MeshInstance3D = kit.box(cafe_box, Vector3(0, 0.36, 0.36), Vector3(0.6, 0.02, 0.25), card_mat)
	flap1.rotation_degrees.x = 60.0
	var flap2: MeshInstance3D = kit.box(cafe_box, Vector3(0.42, 0.34, 0), Vector3(0.25, 0.02, 0.5), card_mat)
	flap2.rotation_degrees.z = -65.0
	kit.label(cafe_box, "FRAGILE", Vector3(0, 0.16, 0.27), 0.0, 22, Color("B5523B"), Color("C9A27A"), 0.004, 0)
	builder.points["doorstep_cafe_node"] = cafe_box
	# Apartment stoop: a wicker basket with a blanket that wobbles.
	var basket := kit.node(g, "StoopBasket", Vector3(-9.6, 0, 0.55))
	kit.cyl(basket, Vector3(0, 0.15, 0), 0.3, 0.3, kit.mat(Color("B9874E"), 0.95), 0.34, 16)
	kit.cyl(basket, Vector3(0, 0.3, 0), 0.35, 0.04, kit.mat(Color("8A5A3E"), 0.9), -1.0, 16)
	var blanket: MeshInstance3D = kit.ball(basket, Vector3(0, 0.3, 0), 0.28, 0.18, kit.mat(Color("E8A0B4"), 0.95), 12)
	blanket.name = "Blanket"
	var handle: MeshInstance3D = kit.cyl(basket, Vector3(0, 0.42, 0), 0.26, 0.03, kit.mat(Color("8A5A3E"), 0.9), -1.0, 16)
	handle.rotation_degrees.x = 90.0
	builder.points["doorstep_home_node"] = basket

func _spawn_strays() -> void:
	if not ResourceLoader.exists(CAT_SCENE):
		return
	var packed: PackedScene = load(CAT_SCENE)
	var layer := Node3D.new()
	layer.name = "Strays"
	add_child(layer)
	var right: Vector3 = camera_rig.call("screen_right")
	var coats: Array[String] = ["ginger", "tabby", "black", "calico"]
	var starts: Array[Vector3] = [Vector3(7.4, 0, -8.6), Vector3(9.2, 0, -7.0)]
	for i in range(mini(stray_count, starts.size())):
		var c: Node3D = packed.instantiate()
		c.name = "Stray%d" % i
		layer.add_child(c)
		c.global_position = starts[i]
		var ctl: Node = StrayScript.new()
		ctl.name = "TownStray"
		c.add_child(ctl)
		ctl.set("screen_right", right)
		ctl.call("setup", c, coats[i % coats.size()], 4100 + i * 31, StrayScript.Mode.ROAM, i == 1)
		strays.append(c)
	# Doorstep peeker hiding in the cafe box.
	var p: Node3D = packed.instantiate()
	p.name = "DoorstepPeeker"
	layer.add_child(p)
	p.global_position = Vector3(-4.35, 0.02, -5.4)
	var pc: Node = StrayScript.new()
	pc.name = "TownStray"
	p.add_child(pc)
	pc.set("screen_right", right)
	pc.call("setup", p, "tuxedo", 777, StrayScript.Mode.PEEK, true)
	peekers[&"doorstep_cafe"] = pc

func _physics_process(_delta: float) -> void:
	# Wobble the stoop basket like something small is inside.
	var b = builder.points.get("doorstep_home_node", null) if builder != null else null
	if b is Node3D:
		var t: float = Time.get_ticks_msec() / 1000.0
		var w: float = sin(t * 9.0) * 4.0 if fposmod(t, 4.0) < 0.8 else 0.0
		(b as Node3D).rotation_degrees.z = w

# ------------------------------------------------------------------ day / night

const TOD_PRESETS: Array[float] = [0.0, 0.55, 0.92]
const TOD_NAMES: Array[String] = ["Autumn afternoon", "Autumn evening", "Autumn night"]

func cycle_time_of_day() -> void:
	var idx: int = 0
	var best: float = INF
	for i in range(TOD_PRESETS.size()):
		var d: float = absf(TOD_PRESETS[i] - time_of_day)
		if d < best:
			best = d
			idx = i
	time_of_day = TOD_PRESETS[(idx + 1) % TOD_PRESETS.size()]
	_toast(_tod_name(), 1.4)

func _tod_name() -> String:
	if time_of_day < 0.3:
		return TOD_NAMES[0]
	if time_of_day < 0.8:
		return TOD_NAMES[1]
	return TOD_NAMES[2]

## Piecewise blend day (0) -> evening (0.55) -> night (1).
func _tod_lerp(day, eve, night):
	if time_of_day <= 0.55:
		return lerp(day, eve, time_of_day / 0.55)
	return lerp(eve, night, (time_of_day - 0.55) / 0.45)

func _apply_time_of_day() -> void:
	if sun == null or world_env == null or kit == null:
		return
	sun.light_color = _tod_lerp(Color("FFF1DC"), Color("FFB27A"), Color("9AA8E0"))
	sun.light_energy = _tod_lerp(1.25, 1.05, 0.16)
	sun.rotation_degrees = Vector3(_tod_lerp(-52.0, -30.0, -45.0), _tod_lerp(215.0, 235.0, 200.0), 0.0)
	var env: Environment = world_env.environment
	env.ambient_light_color = _tod_lerp(Color("FFE6CC"), Color("F2C7B4"), Color("5A5F96"))
	env.ambient_light_energy = _tod_lerp(0.62, 0.5, 0.3)
	env.background_color = _tod_lerp(Color("3A2E35"), Color("2B2129"), Color("1C1824"))
	env.adjustment_saturation = _tod_lerp(1.05, 1.1, 0.92)
	kit.apply_glow(_tod_lerp(0.35, 1.0, 1.4), _tod_lerp(0.0, 1.0, 1.7))
	if hud != null:
		hud.call("set_time_label", _tod_name())
