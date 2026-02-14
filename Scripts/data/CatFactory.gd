extends RefCounted
class_name CatFactory

var _data: Dictionary = {}

func _init(loaded_data: Dictionary = {}) -> void:
	_data = loaded_data

func generate_cat(rng: RandomNumberGenerator, seq: int) -> Dictionary:
	var traits: Array = _data.get("traits", [])
	var visual_pool: Array = _data.get("cat_visual_pool", [])
	var trait_count := rng.randi_range(2, 3)
	var picked_traits: Array = []
	var taken := {}

	for _i in trait_count:
		if traits.is_empty():
			break
		var idx := rng.randi_range(0, traits.size() - 1)
		var trait: Dictionary = traits[idx]
		var trait_id := str(trait.get("id", ""))
		if trait_id == "" or taken.has(trait_id):
			continue
		taken[trait_id] = true
		picked_traits.append(trait)

	var rarity_roll := rng.randf()
	var rarity := "common"
	if rarity_roll >= 0.97:
		rarity = "rare"
	elif rarity_roll >= 0.85:
		rarity = "uncommon"

	var visual: Dictionary = visual_pool[rng.randi_range(0, visual_pool.size() - 1)] if not visual_pool.is_empty() else {}
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
	var score := 0.0
	var patron_tags: Array = patron_archetype.get("tags", [])
	for trait in cat_def.get("traits", []):
		for tag in trait.get("adoption_match_tags", []):
			if patron_tags.has(tag):
				score += 1.0
	return score
