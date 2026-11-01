extends Node3D

## Home apartment environment (Scenes/Environments/Apartment/Apartment.tscn).
##
## The player's small flat between cafe days: a place to feed and bond with newly rescued
## foster cats, plan tomorrow and sleep. Builds itself in _ready():
##   AptRoomBuilder (procedural diorama) -> AptNavGrid (cat "level" adapter) ->
##   foster cats (Cat3D.tscn with its own MainLevelCat3D state machine) -> AptCatDirector
##   -> hotspots (apt_hotspot.gd) -> HUD (apt_hud.gd) + iso camera (apt_iso_camera_rig.gd).
##
## Hotspots are STUBS: clicking one opens a prompt card; the card's primary button emits
## a signal below (and logs "[Apartment] ..."), plus a small visual reaction. Gameplay
## systems connect to these signals later. See Docs/environments/APARTMENT.md.

## Any hotspot clicked (opens its card).
signal hotspot_activated(hotspot_id: String)
## Any card button pressed (generic form of the specific signals below).
signal action_triggered(hotspot_id: String, action_id: String)
## Bowls: feed every cat at home. Gameplay: hunger/fed flag, cost of food.
signal feed_cats_requested
## Bed: sleep and end the day. day = the new day number (local stub counter).
signal sleep_requested(day: int)
## Desk notebook: open the planner for tomorrow (which cats go to the cafe, shopping).
signal plan_tomorrow_requested
## Bonding nest: quiet one-on-one time; cat = the cat that came over (may be null).
signal bonding_requested(cat)
## Wardrobe: future cosmetics screen.
signal wardrobe_requested
## Door / HUD button: "cafe" or "town".
signal travel_requested(destination: String)

const RoomBuilderScript := preload("res://Scripts/environments/apartment/apt_room_builder.gd")
const NavGridScript := preload("res://Scripts/environments/apartment/apt_nav_grid.gd")
const DirectorScript := preload("res://Scripts/environments/apartment/apt_cat_director.gd")
const HudScript := preload("res://Scripts/environments/apartment/apt_hud.gd")
const CameraRigScript := preload("res://Scripts/environments/common/apt_iso_camera_rig.gd")
const HotspotScript := preload("res://Scripts/environments/common/apt_hotspot.gd")
const Cat3DScene := preload("res://Scenes/Prototype3D/Cat3D.tscn")
const DataLoaderScript := preload("res://Scripts/data/DataLoader.gd")
const CatFactoryScript := preload("res://Scripts/data/CatFactory.gd")

@export var cafe_scene_path: String = "res://Scenes/Prototype3D/MainLevel3D.tscn"
## Changed to when it exists; otherwise "Go to Town" only emits travel_requested + a toast.
@export var town_scene_path: String = "res://Scenes/Environments/Town/Town.tscn"
## Probes turn this off so travel buttons only emit signals.
@export var allow_scene_change: bool = true
@export_range(0, 3) var foster_cat_count: int = 2
## 0 = random cats each visit.
@export var cat_seed: int = 0
@export var day: int = 1

var builder: Node3D
var nav: Node
var director: Node
var hud: CanvasLayer
var camera_rig: Node3D
var hotspots: Dictionary = {}
var cats: Array[Node3D] = []
var hovered_hotspot: Node = null
var data: Dictionary = {}

var _mouse_pos := Vector2(-1, -1)
var _travelling: bool = false

const HOTSPOT_DEFS: Array = [
	{"id": "feed", "title": "Cat bowls", "icon": "bowl", "verb": "Feed the cats",
		"body": "Kibble for the fosters and fresh water. A full tummy makes for a calmer cat tomorrow.",
		"actions": [{"id": "feed", "label": "Fill the bowls"}, {"id": "close", "label": "Not now"}]},
	{"id": "bed", "title": "Cozy bed", "icon": "bed", "verb": "Sleep",
		"body": "Tuck in and end the day. The cats will curl up too, and tomorrow is a new cafe day.",
		"actions": [{"id": "sleep", "label": "Sleep till morning"}, {"id": "close", "label": "Stay up"}]},
	{"id": "planner", "title": "Planner notebook", "icon": "notebook", "verb": "Plan tomorrow",
		"body": "Plan tomorrow: which fosters are ready for the cafe, what to restock, who might adopt.",
		"actions": [{"id": "plan", "label": "Plan tomorrow"}, {"id": "close", "label": "Later"}]},
	{"id": "bond", "title": "Bonding nest", "icon": "heart", "verb": "Sit with a cat",
		"body": "Sit quietly by the nest. Slow blinks, no pressure. Shy fosters warm up here before they meet the cafe.",
		"actions": [{"id": "bond", "label": "Sit with a cat"}, {"id": "close", "label": "Not now"}]},
	{"id": "wardrobe", "title": "Wardrobe", "icon": "hanger", "verb": "Change outfit",
		"body": "Aprons, cardigans and cat-ear hats for cafe days. Cosmetics are coming soon.",
		"actions": [{"id": "wardrobe", "label": "Open wardrobe"}, {"id": "close", "label": "Close"}]},
	{"id": "door", "title": "Front door", "icon": "door", "verb": "Head out",
		"body": "Where to? The cafe is waiting, and the town market is just down the street.",
		"actions": [{"id": "cafe", "label": "Go to Cafe"}, {"id": "town", "label": "Go to Town"}]},
]

func _ready() -> void:
	builder = RoomBuilderScript.new()
	builder.name = "Room"
	add_child(builder)
	builder.call("build")

	camera_rig = CameraRigScript.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.call("set_room_bounds", Vector2(RoomBuilderScript.X0, RoomBuilderScript.Z0), Vector2(RoomBuilderScript.X1, RoomBuilderScript.Z1))

	_load_data()
	nav = NavGridScript.new()
	nav.name = "NavGrid"
	add_child(nav)
	nav.call("setup", Vector2(RoomBuilderScript.X0, RoomBuilderScript.Z0), RoomBuilderScript.COLS, RoomBuilderScript.ROWS, RoomBuilderScript.CELL, builder.get("blockers"))
	nav.set("camera", camera_rig.get("camera"))
	nav.set("data", data)

	director = DirectorScript.new()
	director.name = "CatDirector"
	add_child(director)
	director.set("nav", nav)
	var pts: Dictionary = builder.get("points")
	var bowls: Array[Vector2i] = [nav.world_to_map(pts["bowl_cell_a"]), nav.world_to_map(pts["bowl_cell_b"])]
	director.set("bowl_cells", bowls)
	var nap_v: Vector3 = pts["nap_cell"]
	var naps: Array[Vector2i] = [Vector2i(int(nap_v.x), int(nap_v.z))]
	director.set("nap_cells", naps)
	nav.set("rest_cells", naps.duplicate())
	var bond_v: Vector3 = pts["bond_cell"]
	director.set("bond_cell", Vector2i(int(bond_v.x), int(bond_v.z)))

	_build_hotspots()
	_spawn_cats()

	hud = HudScript.new()
	hud.name = "HUD"
	add_child(hud)
	hud.call("set_time_text", "Evening  ·  Day %d" % day)
	hud.connect("action_pressed", _on_card_action)
	hud.connect("cafe_pressed", func(): _travel("cafe"))

# --- setup -----------------------------------------------------------------------------------

func _load_data() -> void:
	var loader: Node = DataLoaderScript.new()
	data = loader.call("load_all_data")
	loader.free()

func _build_hotspots() -> void:
	var anchors: Dictionary = builder.get("anchors")
	var pts: Dictionary = builder.get("points")
	# Pick boxes (world centre, size) per hotspot, sized to the furniture.
	var boxes: Dictionary = {
		"feed": [pts["feed"] + Vector3(0.05, 0.18, 0.0), Vector3(1.2, 0.4, 0.5), 0.9, 0.6],
		"bed": [pts["bed"] + Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 2.1), 1.45, 0.9],
		"planner": [pts["planner"] + Vector3(0, 0.75, 0.1), Vector3(1.5, 0.5, 0.75), 1.5, 0.8],
		"bond": [pts["bond"] + Vector3(-0.3, 0.15, -0.1), Vector3(1.4, 0.35, 1.1), 0.8, 0.8],
		"wardrobe": [pts["wardrobe"] + Vector3(0, 1.0, 0.05), Vector3(1.05, 1.95, 0.6), 2.35, 0.7],
		"door": [pts["door"] + Vector3(0.1, 1.0, 0), Vector3(0.35, 2.0, 1.05), 2.25, 0.7],
	}
	for def in HOTSPOT_DEFS:
		var id: String = def["id"]
		var b: Array = boxes[id]
		var center: Vector3 = b[0]
		var h: Area3D = HotspotScript.new()
		h.call("setup", id, def["title"], def["body"], def["actions"], anchors.get(id), b[1], Vector3.ZERO)
		h.set("verb", def["verb"])
		h.set("icon", def["icon"])
		h.set("label_height", float(b[2]) - center.y)
		h.set("ring_radius", float(b[3]))
		h.set("show_label", false)
		h.position = center
		add_child(h)
		h.connect("activated", _on_hotspot_activated)
		hotspots[id] = h

func _spawn_cats() -> void:
	var actors := Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	var factory = CatFactoryScript.new(data)
	var rng := RandomNumberGenerator.new()
	if cat_seed != 0:
		rng.seed = cat_seed
	else:
		rng.randomize()
	var balance: Dictionary = data.get("balance_config", {}) if data.get("balance_config", {}) is Dictionary else {}
	var spawn_cells: Array[Vector2i] = [Vector2i(8, 6), Vector2i(5, 8), Vector2i(10, 4)]
	var looks: Dictionary = {"coats": [], "names": []}
	var sources: Array[String] = ["alley", "shelter", "doorstep_event"]
	for i in range(foster_cat_count):
		var def: Dictionary = factory.generate_cat(rng, i, sources[i % sources.size()], looks)
		var g: Dictionary = def.get("genome", {}) if def.get("genome", {}) is Dictionary else {}
		(looks["coats"] as Array).append(str(g.get("coat", "")))
		(looks["names"] as Array).append(str(def.get("display_name", "")))
		var cat: Node3D = Cat3DScene.instantiate()
		cat.name = "FosterCat_%d" % i
		cat.set("pixel_art", true)
		cat.set("pixel_density", 56)
		actors.add_child(cat)
		var cell: Vector2i = nav.nearest_walkable_cell(spawn_cells[i % spawn_cells.size()], false)
		cat.call("configure", nav, cell, def, balance)
		# Home is calm: no overstim bar over the cats (their naps use the overstim value).
		cat.set("overstim_bar", null)
		var bar: Node = cat.get_node_or_null("BillboardAnchor/OverstimBar")
		if bar != null:
			(bar as Node3D).visible = false
		cats.append(cat)
		director.call("register_cat", cat)

# --- picking ----------------------------------------------------------------------------------

func get_camera() -> Camera3D:
	return camera_rig.get("camera")

## Hotspot under a screen position (ray query against the hotspot layer), or null.
func pick_hotspot_at(screen_pos: Vector2) -> Node:
	var cam: Camera3D = get_camera()
	if cam == null:
		return null
	var from: Vector3 = cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + cam.project_ray_normal(screen_pos) * 200.0
	var q := PhysicsRayQueryParameters3D.create(from, to, HotspotScript.HOTSPOT_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Object = hit.get("collider")
	return col if col is Area3D and hotspots.values().has(col) else null

## Explicit rect test (not Viewport.gui_get_hovered_control: changing the cursor shape
## resets that, which would let the hotspot ray pick "through" the card).
func _over_gui() -> bool:
	return hud != null and bool(hud.call("is_over_ui", _mouse_pos))

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_pos = (event as InputEventMouse).position

func _process(_delta: float) -> void:
	if _mouse_pos.x < 0.0 or _travelling:
		return
	var h: Node = null if _over_gui() else pick_hotspot_at(_mouse_pos)
	_set_hovered(h)

func _set_hovered(h: Node) -> void:
	if h != hovered_hotspot:
		if hovered_hotspot != null and is_instance_valid(hovered_hotspot):
			hovered_hotspot.call("set_hovered", false)
		hovered_hotspot = h
		if h != null:
			h.call("set_hovered", true)
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if hud != null:
		var card_open: bool = bool(hud.call("is_card_open"))
		if h != null:
			h.call("set_label_suppressed", card_open)
		if h != null and not card_open:
			hud.call("show_hover", "%s  ·  click to %s" % [h.get("title"), str(h.get("verb")).to_lower()], _mouse_pos)
		else:
			hud.call("hide_hover")

func _unhandled_input(event: InputEvent) -> void:
	if _travelling:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_mouse_pos = mb.position
			var h: Node = pick_hotspot_at(mb.position)
			if h != null:
				h.call("activate")
				get_viewport().set_input_as_handled()
			elif hud != null and hud.call("is_card_open"):
				hud.call("hide_card", true)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and hud != null:
			hud.call("hide_card", true)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE and hud != null:
			hud.call("hide_card", true)

# --- hotspot + card handling ------------------------------------------------------------------

func _on_hotspot_activated(h: Node) -> void:
	var id: String = str(h.get("hotspot_id"))
	print("[Apartment] hotspot_activated: %s" % id)
	hotspot_activated.emit(id)
	var screen: Vector2 = get_camera().unproject_position(h.call("get_focus_point"))
	hud.call("show_card", id, h.get("title"), h.get("body"), h.get("icon"), h.get("actions"), screen)

func _on_card_action(hotspot_id: String, action_id: String) -> void:
	if action_id == "close":
		return
	print("[Apartment] action: %s / %s" % [hotspot_id, action_id])
	action_triggered.emit(hotspot_id, action_id)
	var h: Node = hotspots.get(hotspot_id)
	if h != null:
		h.call("choose_action", action_id)
	match action_id:
		"feed":
			director.call("feed_all")
			hud.call("toast", "You fill the bowls. Crunch, crunch...")
			feed_cats_requested.emit()
		"sleep":
			hud.call("fade_cycle", _on_slept)
			sleep_requested.emit(day + 1)
		"plan":
			hud.call("toast", "Planner: tomorrow's plan goes here (coming soon).")
			plan_tomorrow_requested.emit()
		"bond":
			var cat: Node3D = director.call("bond")
			var nm: String = str(cat.get("display_name")) if cat != null else "A cat"
			hud.call("toast", "%s pads over to the nest..." % nm)
			bonding_requested.emit(cat)
		"wardrobe":
			hud.call("toast", "Wardrobe and outfits are coming soon.")
			wardrobe_requested.emit()
		"cafe":
			_travel("cafe")
		"town":
			_travel("town")

func _on_slept() -> void:
	day += 1
	director.call("all_sleep")
	hud.call("set_time_text", "Morning  ·  Day %d" % day)
	hud.call("toast", "Good morning! Day %d begins." % day, 3.2)

func _travel(dest: String) -> void:
	print("[Apartment] travel_requested: %s" % dest)
	travel_requested.emit(dest)
	if not allow_scene_change or _travelling:
		return
	var path: String = cafe_scene_path if dest == "cafe" else town_scene_path
	if not ResourceLoader.exists(path):
		hud.call("toast", "The town isn't open yet. Soon!")
		return
	_travelling = true
	hud.call("fade_out", func(): get_tree().change_scene_to_file(path))
