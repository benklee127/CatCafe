extends RefCounted

## Verb registry: step type id -> implementation path. No class_name; preload by path.
## For each type the registry tries the .tscn first (if a verb ships a scene), then the .gd.
## Missing files are tolerated: has_verb() returns false and create_step() returns null with a
## clear push_error naming the type and expected paths (unless quiet = true).

const STEPS_DIR := "res://Scripts/minigame/cooking/steps/"
const SCENES_DIR := "res://Scenes/Minigames/Steps/"
const DEBUG_STEP := "res://Scripts/minigame/cooking/steps/DebugInstantStep.gd"

## type -> base file name (without extension).
const VERBS: Dictionary = {
	"pour": "PourStep",
	"keep_zone": "KeepZoneStep",
	"stop_ring": "StopRingStep",
	"trace": "TraceStep",
	"place": "PlaceStep",
	"back_burner": "BackBurnerStep",
}

## Verbs that run in parallel with later cards (at most one per recipe).
const PARALLEL_TYPES: Array[String] = ["back_burner"]


static func known_types() -> Array:
	return VERBS.keys()


static func is_parallel(type: String) -> bool:
	return PARALLEL_TYPES.has(type)


## Candidate paths for a type, in lookup order.
static func candidate_paths(type: String) -> Array[String]:
	var out: Array[String] = []
	if not VERBS.has(type):
		return out
	var base: String = String(VERBS[type])
	out.append(SCENES_DIR + base + ".tscn")
	out.append(STEPS_DIR + base + ".gd")
	return out


static func resolve_path(type: String) -> String:
	for p in candidate_paths(type):
		if ResourceLoader.exists(p):
			return p
	return ""


static func has_verb(type: String) -> bool:
	return resolve_path(type) != ""


## Instantiates a step node for `type` (or for an explicit script/scene path / Script override).
## Returns null on failure (with push_error unless quiet).
static func create_step(type: String, override: Variant = null, quiet: bool = false) -> Node2D:
	var path: String = ""
	if override is Script:
		var inst: Object = (override as Script).new()
		return inst as Node2D
	if override is PackedScene:
		return (override as PackedScene).instantiate() as Node2D
	if override is String and String(override) != "":
		path = String(override)
	else:
		if not VERBS.has(type):
			if not quiet:
				push_error("StepRegistry: unknown step type '%s' (known: %s)" % [type, ", ".join(PackedStringArray(VERBS.keys()))])
			return null
		path = resolve_path(type)
		if path == "":
			if not quiet:
				push_error("StepRegistry: verb '%s' is not built yet - expected %s" % [type, " or ".join(PackedStringArray(candidate_paths(type)))])
			return null
	if not ResourceLoader.exists(path):
		if not quiet:
			push_error("StepRegistry: step file missing for '%s': %s" % [type, path])
		return null
	var res: Resource = load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate() as Node2D
	if res is Script:
		var obj: Object = (res as Script).new()
		if obj is Node2D:
			return obj as Node2D
		if obj != null and not (obj is RefCounted):
			obj.free()
	if not quiet:
		push_error("StepRegistry: '%s' at %s is not a Node2D step" % [type, path])
	return null
