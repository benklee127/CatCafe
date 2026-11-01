extends RefCounted
class_name CatFactory

# Builds cat definitions (see PLAN §1.2). Deterministic: the same rng state
# produces an identical def. New callers should preload this script.

const CatGenomeScript := preload("res://Scripts/prototype3d/CatGenome.gd")

const DEFAULT_RARITY_WEIGHTS: Dictionary = {"common": 0.85, "uncommon": 0.12, "rare": 0.03}
const RARITY_ORDER: Array[String] = ["common", "uncommon", "rare"]
const DEFAULT_TRUST_START: float = 10.0
const CAT_NAMES: Array[String] = [
	"Mochi", "Biscuit", "Pumpkin", "Miso", "Tofu", "Pepper", "Clover", "Maple",
	"Noodle", "Bean", "Hazel", "Juniper", "Oolong", "Waffles", "Pickles", "Sesame",
	"Marzipan", "Basil", "Cocoa", "Nutmeg", "Fig", "Dumpling", "Truffle", "Sprout",
	"Chai", "Latte", "Toast", "Olive", "Peanut", "Ginger", "Socks", "Button",
]

var _data: Dictionary = {}

func _init(loaded_data: Dictionary = {}) -> void:
	_data = loaded_data

## avoid: optional {"coats": Array, "names": Array} of looks already in the cafe.
## Coats and names in it are skipped when another option exists, so a cafe never
## fills up with identical cats (e.g. three gingers) or duplicate names.
func generate_cat(rng: RandomNumberGenerator, seq: int, source_id: String = "", avoid: Dictionary = {}) -> Dictionary:
	var source: Dictionary = _find_source(source_id)
	var picked_traits: Array = _pick_traits(rng, source)
	var trait_ids: Array[String] = []
	for t in picked_traits:
		trait_ids.append(str(t.get("id", "")))

	var rarity: String = _roll_rarity(rng, source)
	var visual: Dictionary = _pick_visual(rng, rarity, avoid.get("coats", []))
	var cat_seed: int = rng.randi()
	var genome: Dictionary = CatGenomeScript.from_visual(visual, cat_seed, rarity, trait_ids)
	var trust_start: float = _initial_trust(rng, source)
	var cat_name: String = _pick_name(rng, avoid.get("names", []))

	return {
		"id": "cat_%04d" % seq,
		"display_name": cat_name,
		"rarity": rarity,
		"trait_ids": trait_ids,
		"traits": picked_traits,
		"visual": visual,
		"genome": genome,
		"trust": {"current": trust_start, "max": 100, "ready_for_adoption": false, "state": _trust_state_for(trust_start)},
		"overstim": {"current": 0, "max": 100},
		"seed": cat_seed,
		"source": source_id,
	}

# Fraction (0..1) of the cat's unique adoption tags the patron shares.
func adoption_match_score(cat_def: Dictionary, patron_archetype: Dictionary) -> float:
	var patron_tags: Array = patron_archetype.get("tags", [])
	var unique: Dictionary = {}
	for trait_data in _traits_of(cat_def):
		if not (trait_data is Dictionary):
			continue
		for tag in trait_data.get("adoption_match_tags", []):
			unique[str(tag)] = true
	if unique.is_empty():
		return 0.0
	var hits: int = 0
	for tag in unique.keys():
		if patron_tags.has(tag):
			hits += 1
	return float(hits) / float(unique.size())

# ---------------------------------------------------------------- helpers

func _traits_of(cat_def: Dictionary) -> Array:
	var traits: Array = cat_def.get("traits", [])
	if not traits.is_empty():
		return traits
	var out: Array = []
	var all_traits: Variant = _data.get("traits", [])
	if not (all_traits is Array):
		return out
	for id in cat_def.get("trait_ids", []):
		for t in all_traits:
			if t is Dictionary and str(t.get("id", "")) == str(id):
				out.append(t)
	return out

func _find_source(source_id: String) -> Dictionary:
	if source_id.is_empty():
		return {}
	var sources: Variant = _data.get("rescue_sources", [])
	if sources is Array:
		for s in sources:
			if s is Dictionary and str(s.get("id", "")) == source_id:
				return s
	return {}

# Weighted sampling without replacement (trait_bias from the rescue source).
func _pick_traits(rng: RandomNumberGenerator, source: Dictionary) -> Array:
	var all_traits: Variant = _data.get("traits", [])
	if not (all_traits is Array) or all_traits.is_empty():
		return []
	var pool: Array = []
	var seen: Dictionary = {}
	for t in all_traits:
		if not (t is Dictionary):
			continue
		var id: String = str(t.get("id", ""))
		if id.is_empty() or seen.has(id):
			continue
		seen[id] = true
		pool.append(t)
	var bias: Dictionary = source.get("trait_bias", {}) if source.get("trait_bias", {}) is Dictionary else {}
	var weights: Array[float] = []
	for t in pool:
		weights.append(maxf(0.0, float(bias.get(str(t.get("id", "")), 1.0))))
	var count: int = mini(rng.randi_range(2, 3), pool.size())
	var picked: Array = []
	for _i in range(count):
		var total: float = 0.0
		for w in weights:
			total += w
		var idx: int = 0
		if total <= 0.0:
			idx = rng.randi_range(0, pool.size() - 1)
		else:
			var roll: float = rng.randf() * total
			idx = pool.size() - 1
			for j in range(pool.size()):
				roll -= weights[j]
				if roll < 0.0:
					idx = j
					break
		picked.append((pool[idx] as Dictionary).duplicate(true))
		pool.remove_at(idx)
		weights.remove_at(idx)
	return picked

func _roll_rarity(rng: RandomNumberGenerator, source: Dictionary) -> String:
	var weights: Dictionary = DEFAULT_RARITY_WEIGHTS
	var balance: Variant = _data.get("balance_config", {})
	if balance is Dictionary and balance.get("rarity_weights", null) is Dictionary:
		weights = balance["rarity_weights"]
	if source.get("rarity_weights", null) is Dictionary:
		weights = source["rarity_weights"]
	var total: float = 0.0
	for r in RARITY_ORDER:
		total += maxf(0.0, float(weights.get(r, 0.0)))
	var roll: float = rng.randf() * maxf(total, 0.0001)
	for r in RARITY_ORDER:
		roll -= maxf(0.0, float(weights.get(r, 0.0)))
		if roll < 0.0:
			return r
	return "common"

func _pick_visual(rng: RandomNumberGenerator, rarity: String, avoid_coats: Array = []) -> Dictionary:
	var pool_v: Variant = _data.get("cat_visual_pool", [])
	if not (pool_v is Array) or pool_v.is_empty():
		return {}
	var all_entries: Array = []
	var matching: Array = []
	for v in pool_v:
		if not (v is Dictionary):
			continue
		all_entries.append(v)
		if str(v.get("rarity", "common")) == rarity:
			matching.append(v)
	var choices: Array = matching if not matching.is_empty() else all_entries
	if choices.is_empty():
		return {}
	# Prefer coats not already in the cafe; fall back to the full list.
	var fresh: Array = choices.filter(func(v: Dictionary) -> bool: return not avoid_coats.has(str(v.get("coat", ""))))
	if not fresh.is_empty():
		choices = fresh
	return (choices[rng.randi_range(0, choices.size() - 1)] as Dictionary).duplicate(true)

func _pick_name(rng: RandomNumberGenerator, avoid_names: Array = []) -> String:
	var names: Array = []
	for n in CAT_NAMES:
		if not avoid_names.has(n):
			names.append(n)
	if names.is_empty():
		names = CAT_NAMES.duplicate()
	return str(names[rng.randi_range(0, names.size() - 1)])

func _initial_trust(rng: RandomNumberGenerator, source: Dictionary) -> float:
	var it: Variant = source.get("initial_trust", null)
	if it is Array and it.size() >= 2:
		return roundf(rng.randf_range(float(it[0]), float(it[1])))
	if it is float or it is int:
		return float(it)
	var balance: Variant = _data.get("balance_config", {})
	if balance is Dictionary and balance.get("trust", null) is Dictionary:
		return float(balance["trust"].get("start", DEFAULT_TRUST_START))
	return DEFAULT_TRUST_START

func _trust_state_for(value: float) -> String:
	var balance: Variant = _data.get("balance_config", {})
	var state: String = "fearful"
	if balance is Dictionary and balance.get("trust", null) is Dictionary:
		var states: Variant = balance["trust"].get("states", [])
		if states is Array:
			for s in states:
				if s is Dictionary and value >= float(s.get("min", 0.0)):
					state = str(s.get("id", state))
	return state
