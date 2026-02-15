extends RefCounted
class_name CatFactory

var _data: Dictionary = {}

func _init(loaded_data: Dictionary = {}) -> void:
	_data = loaded_data

func generate_cat(rng: RandomNumberGenerator, seq: int) -> Dictionary:
	var traits: Array = _data.get("traits", [])
	var visual_pool: Array = _data.get("cat_visual_pool", [])
	var trait_count: int = rng.randi_range(2, 3)
	var picked_traits: Array = []
	var taken: Dictionary = {}

	for _i in range(trait_count):
		if traits.is_empty():
			break
		var idx: int = rng.randi_range(0, traits.size() - 1)
		var trait_data: Dictionary = traits[idx]
		var trait_id: String = str(trait_data.get("id", ""))
		if trait_id == "" or taken.has(trait_id):
			continue
		taken[trait_id] = true
		picked_traits.append(trait_data)

	var rarity_roll: float = rng.randf()
	var rarity: String = "common"
	if rarity_roll >= 0.97:
		rarity = "rare"
	elif rarity_roll >= 0.85:
		rarity = "uncommon"

	var visual: Dictionary = {}
	if not visual_pool.is_empty():
		var visual_idx: int = rng.randi_range(0, visual_pool.size() - 1)
		visual = visual_pool[visual_idx]
	return {
		"id": "cat_%04d" % seq,
		"display_name": "Foster Cat %d" % (seq + 1),
		"rarity": rarity,
		"visual": visual,
		"traits": picked_traits,
		"trust": {"current": 10, "max": 100, "ready_for_adoption": false},
		"overstim": {"current": 0, "max": 100}
	}

func adoption_match_score(cat_def: Dictionary, patron_archetype: Dictionary) -> float:
	var score: float = 0.0
	var patron_tags: Array = patron_archetype.get("tags", [])
	for trait_data in cat_def.get("traits", []):
		for tag in trait_data.get("adoption_match_tags", []):
			if patron_tags.has(tag):
				score += 1.0
	return score
