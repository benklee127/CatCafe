extends Node2D

const CatAgentScript := preload("res://Scripts/prototype/CatAgent.gd")
const PatronAgentScript := preload("res://Scripts/prototype/PatronAgent.gd")
const CatFactoryScript := preload("res://Scripts/data/CatFactory.gd")

@export var cat_count: int = 4
@export var patron_count: int = 3
@export var deterministic_seed: int = 240214
@export var use_deterministic_seed: bool = true
@export var world_bounds := Rect2(Vector2(180, 180), Vector2(1200, 560))

var rng := RandomNumberGenerator.new()
var cats: Array = []
var patrons: Array = []
var data: Dictionary = {}
var cat_factory

@onready var world: Node2D = $World
@onready var cat_layer: Node2D = $World/CatLayer
@onready var patron_layer: Node2D = $World/PatronLayer
@onready var rest_area: Marker2D = $World/RestArea
@onready var debug_hud = $DebugHUD
@onready var data_loader = $DataLoader
@onready var save_system = $SaveSystem

func _ready() -> void:
	if use_deterministic_seed:
		rng.seed = deterministic_seed
	else:
		rng.randomize()

	data = data_loader.load_all_data()
	cat_factory = CatFactoryScript.new(data)
	_spawn_cats()
	_spawn_patrons()

	var loaded := save_system.load_run_state()
	if loaded.is_empty():
		save_system.save_run_state(_snapshot_run_state())

func _process(_delta: float) -> void:
	for patron in patrons:
		for cat in cats:
			var dist := patron.global_position.distance_to(cat.global_position)
			if dist <= patron.interaction_radius:
				cat.apply_stimulation(patron.overstim_impact * get_process_delta_time(), patron.archetype_id)

	debug_hud.render_debug(cats, patrons)

func _spawn_cats() -> void:
	for i in cat_count:
		var generated: Dictionary = cat_factory.generate_cat(rng, i)
		var cat = CatAgentScript.new()
		cat.name = "Cat_%d" % i
		cat.definition = generated
		cat.rest_point = rest_area.global_position
		cat.world_bounds = world_bounds
		cat.global_position = _random_point_in_bounds()
		cat_layer.add_child(cat)
		cats.append(cat)

func _spawn_patrons() -> void:
	var archetypes: Array = data.get("patron_archetypes", [])
	for i in patron_count:
		var idx := rng.randi_range(0, max(0, archetypes.size() - 1))
		var source: Dictionary = archetypes[idx] if not archetypes.is_empty() else {}
		var patron = PatronAgentScript.new()
		patron.name = "Patron_%d" % i
		patron.configure(source)
		patron.world_bounds = world_bounds
		patron.global_position = _random_point_in_bounds()
		patron_layer.add_child(patron)
		patrons.append(patron)

func _snapshot_run_state() -> Dictionary:
	return {
		"save_version": 1,
		"day": 1,
		"time_of_day": "morning",
		"money": 100,
		"reputation": 0,
		"active_cats": cats.size(),
		"active_patrons": patrons.size(),
		"adoptions_total": 0,
		"placed_decor": $World/GridPlacer.get_placed_decor_payload(),
		"unlocked_content": ["basic_layout"]
	}

func _random_point_in_bounds() -> Vector2:
	return Vector2(
		rng.randf_range(world_bounds.position.x, world_bounds.end.x),
		rng.randf_range(world_bounds.position.y, world_bounds.end.y)
	)
