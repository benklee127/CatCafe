extends SceneTree

## Town environment probe (Scenes/Environments/Town/Town.tscn).
##
## Run (from the project folder):
##   Godot_console.exe --headless --path . --fixed-fps 30 --script res://Tools/probe_town.gd
##
## Checks:
##   hotspots : every hotspot opens its prompt card (activate_hotspot) and the card's Go
##              button emits hotspot_activated(id) + that spot's specific signal.
##              Alley search is checked with find chance 1 (found + rarity) and 0.
##              Home reports go_home_requested(available) and shows "coming soon" when
##              the apartment scene is missing; cafe emits travel_requested(MainLevel3D).
##   picking  : a camera ray through each hotspot's click volume picks that hotspot.
##   walkers  : over SOAK_FRAMES every townsfolk stays on sidewalks / crosswalks / plaza /
##              park path (TownLayout.is_walkable) and actually walks.
##   strays   : every alley stray stays inside TownLayout.STRAY_AREA and moves at least once.
## Exit code: 0 when every check passes, 1 otherwise. auto_travel is off (no scene change).

const SCENE := "res://Scenes/Environments/Town/Town.tscn"
const L := preload("res://Scripts/environments/town/TownLayout.gd")
const SOAK_FRAMES: int = 1800
const EXPECTED_SIGNALS: Dictionary = {
	"cafe": "enter_cafe_requested",
	"shelter": "visit_shelter_requested",
	"alley": "alley_searched",
	"home": "go_home_requested",
	"shop": "shop_browse_requested",
	"park": "park_sit_requested",
	"market": "market_visit_requested",
	"doorstep_cafe": "doorstep_event_found",
	"doorstep_home": "doorstep_event_found",
}

var town: Node
var frame: int = 0
var fails: Array[String] = []
var passes: int = 0
var log_events: Array = []
var _phase: int = 0
var _soak: int = 0
var _walker_start: Dictionary = {}
var _walker_travel: Dictionary = {}
var _walker_prev: Dictionary = {}
var _stray_start: Dictionary = {}
var _stray_moved: Dictionary = {}
var _offwalk: Dictionary = {}
var _offalley: Dictionary = {}

func _initialize() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("FAIL could not load ", SCENE)
		quit(1)
		return
	town = packed.instantiate()
	town.set("auto_travel", false)
	town.set("rng_seed", 4242)
	root.add_child(town)

func _ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails.append(what)
		print("FAIL ", what)

func _rec(sig: String) -> Callable:
	return func(a = null, b = null, c = null): log_events.append([sig, a, b, c])

func _connect_all() -> void:
	var sigs: Array[String] = ["hotspot_activated", "enter_cafe_requested", "visit_shelter_requested", "alley_searched", "go_home_requested", "shop_browse_requested", "park_sit_requested", "market_visit_requested", "doorstep_event_found", "travel_requested"]
	for s in sigs:
		if town.has_signal(s):
			town.connect(s, _rec(s))
		else:
			_ok(false, "town has signal %s" % s)

func _events(sig: String) -> Array:
	var out: Array = []
	for e in log_events:
		if e[0] == sig:
			out.append(e)
	return out

func _check_hotspots() -> void:
	var hud: Node = town.get("hud")
	_ok(hud != null, "HUD exists")
	var ids: Array = town.call("get_hotspot_ids")
	for id in EXPECTED_SIGNALS.keys():
		_ok(ids.has(StringName(id)), "hotspot %s exists" % id)
	for id in EXPECTED_SIGNALS.keys():
		if id == "alley":
			town.set("alley_find_chance", 1.0)
		log_events.clear()
		town.call("activate_hotspot", StringName(id))
		_ok(bool(hud.call("is_card_open")), "%s: card opens" % id)
		_ok(StringName(hud.get("current_id")) == StringName(id), "%s: card shows this hotspot" % id)
		# Press the card's Go button.
		var go: Button = hud.get("card_go")
		go.pressed.emit()
		_ok(not bool(hud.call("is_card_open")), "%s: card closes on Go" % id)
		var act: Array = _events("hotspot_activated")
		_ok(act.size() == 1 and StringName(act[0][1]) == StringName(id), "%s: hotspot_activated(%s)" % [id, id])
		var spec: Array = _events(EXPECTED_SIGNALS[id])
		_ok(spec.size() == 1, "%s: %s emitted" % [id, EXPECTED_SIGNALS[id]])
		match id:
			"alley":
				if spec.size() == 1:
					_ok(spec[0][1] == true and String(spec[0][2]) in ["common", "uncommon", "rare"], "alley: found stray with a rarity (chance 1)")
				log_events.clear()
				town.set("alley_find_chance", 0.0)
				town.call("confirm_hotspot", &"alley")
				var e2: Array = _events("alley_searched")
				_ok(e2.size() == 1 and e2[0][1] == false, "alley: nothing found (chance 0)")
				town.set("alley_find_chance", 0.35)
			"home":
				var avail: bool = ResourceLoader.exists("res://Scenes/Environments/Apartment/Apartment.tscn")
				if spec.size() == 1:
					_ok(bool(spec[0][1]) == avail, "home: go_home_requested(available=%s)" % avail)
				if avail:
					_ok(_events("travel_requested").size() == 1, "home: travel_requested to the apartment")
				else:
					_ok(String(hud.call("toast_text")).to_lower().contains("coming soon"), "home: coming-soon toast when the apartment is missing")
			"cafe":
				var tr: Array = _events("travel_requested")
				_ok(tr.size() == 1 and String(tr[0][1]) == "res://Scenes/Prototype3D/MainLevel3D.tscn", "cafe: travel_requested(MainLevel3D)")
			"doorstep_cafe", "doorstep_home":
				if spec.size() == 1:
					_ok(StringName(spec[0][1]) == StringName(id) and (spec[0][2] as Dictionary).get("id", "") == "doorstep_event", "%s: doorstep_event_found(id, doorstep_event source)" % id)
	print("hotspots: checked %d spots" % EXPECTED_SIGNALS.size())

func _check_picking() -> void:
	var rig: Node = town.get_node("CameraRig")
	var cam: Camera3D = rig.get("camera")
	for id in EXPECTED_SIGNALS.keys():
		var hs: Node = town.call("get_hotspot", StringName(id))
		var info: Dictionary = hs.get("info")
		var c: Vector3 = info.get("area_center", hs.global_position)
		rig.call("snap_to", c, 10.0)
		var sp: Vector2 = cam.unproject_position(c)
		var got: StringName = town.call("pick_hotspot_at", sp)
		_ok(got == StringName(id), "picking: ray through %s picks it (got '%s')" % [id, got])
	rig.call("overview")

func _start_soak() -> void:
	for w in town.get("walkers"):
		_walker_start[w] = w.global_position
		_walker_prev[w] = w.global_position
		_walker_travel[w] = 0.0
	for s in town.get("strays"):
		_stray_start[s] = s.global_position
		_stray_moved[s] = false
	_ok((town.get("walkers") as Array).size() >= 3, "at least 3 townsfolk spawned")
	_ok((town.get("strays") as Array).size() >= 1, "at least 1 alley stray spawned")

func _soak_step() -> void:
	for w in town.get("walkers"):
		var p: Vector3 = w.global_position
		if not L.is_walkable(p, 0.05):
			_offwalk[w.name] = p
		_walker_travel[w] = float(_walker_travel[w]) + p.distance_to(_walker_prev[w])
		_walker_prev[w] = p
	for s in town.get("strays"):
		var p: Vector3 = s.global_position
		if not L.is_in_stray_area(p):
			_offalley[s.name] = p
		if p.distance_to(_stray_start[s]) > 0.3:
			_stray_moved[s] = true

func _finish_soak() -> void:
	for w in _walker_travel.keys():
		_ok(not _offwalk.has(w.name), "walker %s stays on sidewalks%s" % [w.name, (" (left at %s)" % str(_offwalk[w.name])) if _offwalk.has(w.name) else ""])
		_ok(float(_walker_travel[w]) > 5.0, "walker %s walks (%.1f m)" % [w.name, float(_walker_travel[w])])
	for s in _stray_moved.keys():
		_ok(not _offalley.has(s.name), "stray %s stays in the alley%s" % [s.name, (" (left at %s)" % str(_offalley[s.name])) if _offalley.has(s.name) else ""])
		_ok(bool(_stray_moved[s]), "stray %s moves" % s.name)

func _process(_delta: float) -> bool:
	frame += 1
	match _phase:
		0:
			if frame >= 10:
				_connect_all()
				_check_hotspots()
				_phase = 1
		1:
			if frame >= 14:
				_check_picking()
				_start_soak()
				_phase = 2
		2:
			_soak += 1
			_soak_step()
			if _soak >= SOAK_FRAMES:
				_finish_soak()
				_phase = 3
		3:
			print("probe_town: %d passed, %d failed" % [passes, fails.size()])
			for f in fails:
				print("  - ", f)
			print("RESULT: %s" % ("PASS" if fails.is_empty() else "FAIL"))
			quit(0 if fails.is_empty() else 1)
			return true
	return false
