extends Node
class_name SlotManager3D

var slots: Dictionary = {}
var actor_claims: Dictionary = {}
var _next_slot_id: int = 1

func add_slot(kind: StringName, grid: Vector2i, world_pos: Vector3, owner_key: String) -> int:
	var slot_id: int = _next_slot_id
	_next_slot_id += 1
	slots[slot_id] = {
		"kind": kind,
		"grid": grid,
		"world_pos": world_pos,
		"owner_key": owner_key,
		"claimed_by": null
	}
	return slot_id

func remove_slot(slot_id: int) -> void:
	if not slots.has(slot_id):
		return
	var claimed_by = slots[slot_id].get("claimed_by", null)
	if claimed_by != null and claimed_by is Node:
		actor_claims.erase((claimed_by as Node).get_instance_id())
		if (claimed_by as Node).has_method("on_slot_invalidated"):
			(claimed_by as Node).call_deferred("on_slot_invalidated", slot_id)
	slots.erase(slot_id)

func remove_slots(slot_ids: Array) -> void:
	for id_variant in slot_ids:
		remove_slot(int(id_variant))

func request_best_slot(kind: StringName, actor: Node, from_grid: Vector2i, level, allow_rest_area: bool = false) -> int:
	var best_id: int = -1
	var best_cost: int = 1_000_000
	for slot_id in slots.keys():
		var slot_data: Dictionary = slots[slot_id]
		if slot_data.get("kind", &"") != kind:
			continue
		if slot_data.get("claimed_by", null) != null:
			continue
		var slot_grid: Vector2i = slot_data.get("grid", Vector2i.ZERO)
		var cost: int = 0
		if slot_grid != from_grid:
			var path: Array[Vector2i] = level.build_path(from_grid, slot_grid, allow_rest_area)
			if path.is_empty():
				continue
			cost = path.size()
		if cost < best_cost:
			best_cost = cost
			best_id = int(slot_id)
	return best_id

func claim_slot(slot_id: int, actor: Node) -> bool:
	if not slots.has(slot_id):
		return false
	var slot_data: Dictionary = slots[slot_id]
	var existing = slot_data.get("claimed_by", null)
	if existing != null and existing != actor:
		return false
	release_actor_slot(actor)
	slot_data["claimed_by"] = actor
	slots[slot_id] = slot_data
	actor_claims[actor.get_instance_id()] = slot_id
	return true

func release_actor_slot(actor: Node) -> void:
	var actor_id: int = actor.get_instance_id()
	if not actor_claims.has(actor_id):
		return
	var slot_id: int = actor_claims[actor_id]
	actor_claims.erase(actor_id)
	if not slots.has(slot_id):
		return
	var slot_data: Dictionary = slots[slot_id]
	if slot_data.get("claimed_by", null) == actor:
		slot_data["claimed_by"] = null
		slots[slot_id] = slot_data

func has_slot(slot_id: int) -> bool:
	return slots.has(slot_id)

func get_slot_grid(slot_id: int) -> Vector2i:
	if not slots.has(slot_id):
		return Vector2i(-9999, -9999)
	return slots[slot_id].get("grid", Vector2i(-9999, -9999))

func get_slot_world(slot_id: int) -> Vector3:
	if not slots.has(slot_id):
		return Vector3.ZERO
	return slots[slot_id].get("world_pos", Vector3.ZERO)
