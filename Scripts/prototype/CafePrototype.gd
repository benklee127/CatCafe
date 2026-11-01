extends Node2D

const CatAgentScript = preload("res://Scripts/prototype/CatAgent.gd")
const PatronAgentScript = preload("res://Scripts/prototype/PatronAgent.gd")
const CatFactoryScript = preload("res://Scripts/data/CatFactory.gd")

@export var cat_count: int = 4
@export var patron_count: int = 3
@export var deterministic_seed: int = 240214
@export var use_deterministic_seed: bool = true
@export var world_bounds: Rect2 = Rect2(Vector2(180, 180), Vector2(1200, 560))

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var cats: Array = []
var patrons: Array = []
var data: Dictionary = {}
var cat_factory
## Live run state (day, money, reputation...). Restored from the save on boot.
var run_state: Dictionary = {}

@onready var world: Node2D = $World
@onready var cat_layer: Node2D = $World/CatLayer
@onready var patron_layer: Node2D = $World/PatronLayer
@onready var rest_area: Marker2D = $World/RestArea
@onready var debug_hud: CanvasLayer = $DebugHUD
@onready var data_loader: Node = $DataLoader
@onready var save_system: Node = $SaveSystem

func _ready() -> void:
	if use_deterministic_seed:
		rng.seed = deterministic_seed
	else:
		rng.randomize()

	data = data_loader.load_all_data()
	cat_factory = CatFactoryScript.new(data)
	_spawn_cats()
	_spawn_patrons()

	var loaded: Dictionary = save_system.load_run_state()
	if loaded.is_empty():
		run_state = _default_run_state()
		save_system.save_run_state(_snapshot_run_state())
	else:
		_apply_run_state(loaded)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not run_state.is_empty():
		save_system.save_run_state(_snapshot_run_state())

func _default_run_state() -> Dictionary:
	var economy: Dictionary = data.get("balance_config", {}).get("economy", {})
	return {
		"day": 1,
		"time_of_day": "morning",
		"money": int(economy.get("starting_money", 100)),
		"reputation": int(economy.get("starting_reputation", 0)),
		"adoptions_total": 0,
		"unlocked_content": ["basic_layout"]
	}

## Applies a loaded save: economy/day values and the placed decor.
func _apply_run_state(loaded: Dictionary) -> void:
	run_state = _default_run_state()
	for key in ["day", "time_of_day", "money", "reputation", "adoptions_total", "unlocked_content"]:
		if loaded.has(key):
			run_state[key] = loaded[key]
	var grid_placer: Node = $World/GridPlacer
	var placed: Variant = loaded.get("placed_decor", [])
	if placed is Array and grid_placer.has_method("restore_placed_decor"):
		grid_placer.call("restore_placed_decor", placed)

func _process(_delta: float) -> void:
	for patron in patrons:
		for cat in cats:
			var dist: float = patron.global_position.distance_to(cat.global_position)
			if dist <= patron.interaction_radius:
				cat.apply_stimulation(patron.overstim_impact * get_process_delta_time(), patron.archetype_id)

	debug_hud.render_debug(cats, patrons, run_state)

func _spawn_cats() -> void:
	for i in cat_count:
		var generated: Dictionary = cat_factory.generate_cat(rng, i)
		var cat = CatAgentScript.new()
		cat.name = "Cat_%d" % i
		cat.definition = generated
		cat.balance = data.get("balance_config", {})
		cat.rng_seed = rng.randi() | 1
		cat.rest_point = rest_area.global_position
		cat.world_bounds = world_bounds
		cat.global_position = _random_point_in_bounds()
		cat_layer.add_child(cat)
		cats.append(cat)

func _spawn_patrons() -> void:
	var archetypes: Array = data.get("patron_archetypes", [])
	for i in patron_count:
		var idx: int = rng.randi_range(0, max(0, archetypes.size() - 1))
		var source: Dictionary = archetypes[idx] if not archetypes.is_empty() else {}
		var patron = PatronAgentScript.new()
		patron.name = "Patron_%d" % i
		patron.configure(source)
		patron.rng_seed = rng.randi() | 1
		patron.world_bounds = world_bounds
		patron.global_position = _random_point_in_bounds()
		patron_layer.add_child(patron)
		patrons.append(patron)

func _snapshot_run_state() -> Dictionary:
	var out: Dictionary = run_state.duplicate(true)
	out["save_version"] = 1
	out["active_cats"] = cats.size()
	out["active_patrons"] = patrons.size()
	out["run_seed"] = deterministic_seed if use_deterministic_seed else 0
	out["placed_decor"] = $World/GridPlacer.get_placed_decor_payload()
	return out

func _random_point_in_bounds() -> Vector2:
	return Vector2(
		rng.randf_range(world_bounds.position.x, world_bounds.end.x),
		rng.randf_range(world_bounds.position.y, world_bounds.end.y)
	)
